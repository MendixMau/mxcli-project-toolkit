// starrun — run one toolkit Starlark lint rule under the real Go Starlark interpreter
// (go.starlark.net, the engine mxcli embeds) with the mxcli builtins the rule needs
// served from a JSON fixture instead of a live catalog.
//
// Why: lint-rules/*.star have no test path that does not need an mxcli binary and a
// real .mpr. This harness proves a rule's LOGIC and its blindness self-checks against
// fixed input, using the same struct type (starlarkstruct) and the same regexp engine
// (Go RE2 via `matches`) the real linter uses, so a wrong attribute name or a
// Python-only idiom fails here the way it fails in `mxcli lint`.
//
// What it does NOT prove: the vocabulary of a real catalog (action type strings,
// casing). That is the field calibration, still owed per lint-rules/README.md.
//
// Usage:
//
//	go run ./tests/lint-rules/starrun -rule lint-rules/x.star -fixture f.json [-strip-fields a,b]
//
// Prints a JSON array of {module,document_type,document_name,message,suggestion}.
// Exit 0 on success, 1 on a load/eval error (message on stderr).
//
// Fixture schema (every key optional, missing struct fields default to ""/false/0):
//
//	{"widgets":[{...}], "microflows":[{...}], "pages":[{...}],
//	 "entities":[{...}], "associations":[{...}], "strings":[{...}],
//	 "activities":{"Mod.Flow":[{...}]}, "refs_from":{"Mod.Flow":[{...}]},
//	 "permissions":[{...}], "attributes":{"Mod.Entity":[{...}]},
//	 "user_roles":[{...}], "role_mappings":[{...}], "options":{"key":value}}
//
// "options" is what .claude/lint-config.yaml `rules: <ID>: options:` passes; get_option()
// converts it the way mxcli 0.26.0's goValueToStarlark does: bool, int (a whole JSON
// number), float, string — and a list, map or null becomes None.
//
// Field names are the mxcli Starlark projection names (mdl/linter/starlark.go):
// widget: id name widget_type container_id container_qualified_name container_type
//
//	module_name entity_ref attribute_ref microflow_ref nanoflow_ref page_ref
//	parent_widget_id depth class_name style dynamic_classes action_type has_confirmation
//
// microflow: id name qualified_name module_name folder microflow_type description
//
//	return_type parameter_count activity_count total_activity_count complexity
//
// activity: id name caption activity_type action_type microflow_id
//
//	microflow_qualified_name module_name entity_ref service_ref action_ref
//	use_request_timeout timeout_expression auto_generate_caption description
//	parent_loop_id loop_depth condition_expression condition_rule error_handling_type
//	log_level log_node_expression log_message commit_type with_events retrieve_source queue_ref
//
// entity: id name qualified_name module_name folder entity_type description generalization
//
//	attribute_count access_rule_count validation_rule_count has_event_handlers is_external
//	has_created_date has_changed_date has_owner has_changed_by
//
// association: name qualified_name module_name from_entity to_entity type owner storage_format
//
//	description to_delete_behavior from_delete_behavior
//
// reference: source_type source_id source_name target_type target_id target_name ref_kind module_name
//
// catalog_string (strings(language=None)): qualified_name object_type value context language
//
//	element_id module_name
//
// entity_permission (permissions_for(entity), fixture "permissions" filtered on entity_name;
// permissions() serves every row, with element_type / element_name):
//
//	module_role_name module_name entity_name access_type member_name xpath_constraint
//	is_constrained default_member_access_rights element_type element_name
//
// attribute (attributes_for(entity)): id name entity_id entity_qualified_name module_name
//
//	data_type length is_unique is_required default_value is_calculated description
//
// user_role: name is_anonymous module_roles (list of strings)
// role_mapping: user_role_name module_role_name module_name
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"

	"go.starlark.net/starlark"
	"go.starlark.net/starlarkstruct"
)

type fixture struct {
	Widgets      []map[string]any            `json:"widgets"`
	Microflows   []map[string]any            `json:"microflows"`
	Pages        []map[string]any            `json:"pages"`
	Activities   map[string][]map[string]any `json:"activities"`
	RefsFrom     map[string][]map[string]any `json:"refs_from"`
	Entities     []map[string]any            `json:"entities"`
	Associations []map[string]any            `json:"associations"`
	Strings      []map[string]any            `json:"strings"`
	Permissions  []map[string]any            `json:"permissions"`
	Attributes   map[string][]map[string]any `json:"attributes"`
	UserRoles    []map[string]any            `json:"user_roles"`
	RoleMappings []map[string]any            `json:"role_mappings"`
	Options      map[string]any              `json:"options"`
}

// Projection field lists with their zero values. Order does not matter to Starlark.
var widgetFields = fields{
	s: []string{"id", "name", "widget_type", "container_id", "container_qualified_name", "container_type",
		"module_name", "entity_ref", "attribute_ref", "microflow_ref", "nanoflow_ref", "page_ref",
		"parent_widget_id", "class_name", "style", "dynamic_classes", "action_type"},
	b: []string{"has_confirmation"},
	i: []string{"depth"},
}
var microflowFields = fields{
	s: []string{"id", "name", "qualified_name", "module_name", "folder", "microflow_type", "description",
		"return_type", "document_noun", "document_noun_title"},
	i: []string{"parameter_count", "activity_count", "total_activity_count", "complexity"},
}
var pageFields = fields{
	s: []string{"id", "name", "qualified_name", "module_name", "folder", "title", "url", "description"},
	i: []string{"widget_count"},
}
var activityFields = fields{
	s: []string{"id", "name", "caption", "activity_type", "action_type", "microflow_id",
		"microflow_qualified_name", "module_name", "entity_ref", "service_ref", "action_ref",
		"timeout_expression", "description", "parent_loop_id", "condition_expression", "condition_rule",
		"error_handling_type", "log_level", "log_node_expression", "log_message", "commit_type",
		"retrieve_source", "queue_ref"},
	b: []string{"use_request_timeout", "auto_generate_caption", "with_events"},
	i: []string{"loop_depth"},
}
var refFields = fields{
	s: []string{"source_type", "source_id", "source_name", "target_type", "target_id", "target_name",
		"ref_kind", "module_name"},
}

type fields struct{ s, b, i []string }

var strip = map[string]bool{}

func toStruct(kind string, f fields, m map[string]any) starlark.Value {
	d := starlark.StringDict{}
	for _, k := range f.s {
		if strip[k] {
			continue
		}
		v, _ := m[k].(string)
		d[k] = starlark.String(v)
	}
	for _, k := range f.b {
		if strip[k] {
			continue
		}
		v, _ := m[k].(bool)
		d[k] = starlark.Bool(v)
	}
	for _, k := range f.i {
		if strip[k] {
			continue
		}
		v, _ := m[k].(float64)
		d[k] = starlark.MakeInt(int(v))
	}
	for k := range m {
		if _, known := d[k]; !known && !strip[k] {
			fmt.Fprintf(os.Stderr, "starrun: fixture %s has unknown field %q (not in the mxcli projection)\n", kind, k)
			os.Exit(1)
		}
	}
	return starlarkstruct.FromStringDict(starlark.String(kind), d)
}

func list(kind string, f fields, rows []map[string]any) *starlark.List {
	out := make([]starlark.Value, 0, len(rows))
	for _, r := range rows {
		out = append(out, toStruct(kind, f, r))
	}
	return starlark.NewList(out)
}

func str(v starlark.Value) string {
	if s, ok := starlark.AsString(v); ok {
		return s
	}
	return ""
}

func main() {
	rule := flag.String("rule", "", "path to the .star rule")
	fix := flag.String("fixture", "", "path to the fixture JSON")
	stripFlag := flag.String("strip-fields", "", "comma-separated struct fields to omit (simulate an older mxcli)")
	flag.Parse()
	if *rule == "" || *fix == "" {
		fmt.Fprintln(os.Stderr, "usage: starrun -rule file.star -fixture file.json [-strip-fields a,b]")
		os.Exit(2)
	}
	for _, f := range strings.Split(*stripFlag, ",") {
		if f = strings.TrimSpace(f); f != "" {
			strip[f] = true
		}
	}
	raw, err := os.ReadFile(*fix)
	if err != nil {
		fmt.Fprintln(os.Stderr, "starrun:", err)
		os.Exit(1)
	}
	var fx fixture
	if err := json.Unmarshal(raw, &fx); err != nil {
		fmt.Fprintln(os.Stderr, "starrun: fixture:", err)
		os.Exit(1)
	}

	oneStr := func(name string) func(*starlark.Thread, *starlark.Builtin, starlark.Tuple, []starlark.Tuple) (string, error) {
		return func(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (string, error) {
			var s string
			err := starlark.UnpackArgs(name, args, kwargs, "qualified_name", &s)
			return s, err
		}
	}
	noArgs := func(name string, v starlark.Value) *starlark.Builtin {
		return starlark.NewBuiltin(name, func(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			if len(args) != 0 || len(kwargs) != 0 {
				return nil, fmt.Errorf("%s() takes no arguments", name)
			}
			return v, nil
		})
	}

	predeclared := starlark.StringDict{
		"struct":       starlark.NewBuiltin("struct", starlarkstruct.Make),
		"widgets":      noArgs("widgets", list("widget", widgetFields, fx.Widgets)),
		"microflows":   noArgs("microflows", list("microflow", microflowFields, fx.Microflows)),
		"pages":        noArgs("pages", list("page", pageFields, fx.Pages)),
		"entities":     noArgs("entities", list("entity", entityFields, fx.Entities)),
		"associations": noArgs("associations", list("association", associationFields, fx.Associations)),
		"permissions_for": starlark.NewBuiltin("permissions_for", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			var q string
			if err := starlark.UnpackArgs(b.Name(), args, kwargs, "entity_qualified_name", &q); err != nil {
				return nil, err
			}
			keep := []map[string]any{}
			for _, r := range fx.Permissions {
				if v, _ := r["entity_name"].(string); v == q {
					keep = append(keep, r)
				}
			}
			return list("entity_permission", permissionFields, keep), nil
		}),
		"attributes_for": starlark.NewBuiltin("attributes_for", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			var q string
			if err := starlark.UnpackArgs(b.Name(), args, kwargs, "entity_qualified_name", &q); err != nil {
				return nil, err
			}
			return list("attribute", attributeFields, fx.Attributes[q]), nil
		}),
		// permissions() mirrors the catalog-wide builtin: every row with element_type /
		// element_name. A fixture row written for permissions_for (entity_name only) is
		// served as an ENTITY row for that entity.
		"permissions": starlark.NewBuiltin("permissions", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			if len(args) != 0 || len(kwargs) != 0 {
				return nil, fmt.Errorf("permissions() takes no arguments")
			}
			rows := make([]map[string]any, 0, len(fx.Permissions))
			for _, r := range fx.Permissions {
				c := map[string]any{}
				for k, v := range r {
					c[k] = v
				}
				if _, ok := c["element_name"]; !ok {
					if en, ok := c["entity_name"].(string); ok {
						c["element_name"] = en
						c["element_type"] = "ENTITY"
					}
				}
				rows = append(rows, c)
			}
			return list("entity_permission", permissionFields, rows), nil
		}),
		"user_roles":    noArgs("user_roles", userRoles(fx.UserRoles)),
		"role_mappings": noArgs("role_mappings", list("role_mapping", roleMappingFields, fx.RoleMappings)),
		"get_option": starlark.NewBuiltin("get_option", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			var key string
			var def starlark.Value = starlark.None
			if err := starlark.UnpackArgs(b.Name(), args, kwargs, "key", &key, "default?", &def); err != nil {
				return nil, err
			}
			v, ok := fx.Options[key]
			if !ok {
				return def, nil
			}
			switch x := v.(type) {
			case bool:
				return starlark.Bool(x), nil
			case float64:
				if x == float64(int(x)) {
					return starlark.MakeInt(int(x)), nil
				}
				return starlark.Float(x), nil
			case string:
				return starlark.String(x), nil
			default:
				return starlark.None, nil
			}
		}),
		// strings(language=None) mirrors mxcli 0.25.0+: every catalog string, optionally
		// filtered to one language.
		"strings": starlark.NewBuiltin("strings", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			var lang starlark.Value = starlark.None
			if err := starlark.UnpackArgs(b.Name(), args, kwargs, "language?", &lang); err != nil {
				return nil, err
			}
			rows := fx.Strings
			if l, ok := lang.(starlark.String); ok && string(l) != "" {
				keep := make([]map[string]any, 0, len(rows))
				for _, r := range rows {
					if v, _ := r["language"].(string); v == string(l) {
						keep = append(keep, r)
					}
				}
				rows = keep
			}
			return list("catalog_string", stringFields, rows), nil
		}),
		// activities_for(q, nested=False) mirrors mxcli 0.25.0: the fixture lists every
		// object of a flow, loop bodies included (with parent_loop_id / loop_depth), and the
		// default call returns only the rows whose loop_depth is 0 or absent, exactly as the
		// real builtin leaves loop bodies out unless nested=True (mendixlabs/mxcli#1266).
		"activities_for": starlark.NewBuiltin("activities_for", func(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			var q string
			var nested bool
			if err := starlark.UnpackArgs("activities_for", args, kwargs, "qualified_name", &q, "nested?", &nested); err != nil {
				return nil, err
			}
			rows := fx.Activities[q]
			if !nested {
				top := make([]map[string]any, 0, len(rows))
				for _, r := range rows {
					if d, ok := r["loop_depth"].(float64); ok && d > 0 {
						continue
					}
					top = append(top, r)
				}
				rows = top
			}
			return list("activity", activityFields, rows), nil
		}),
		"refs_from": starlark.NewBuiltin("refs_from", func(t *starlark.Thread, b *starlark.Builtin, a starlark.Tuple, k []starlark.Tuple) (starlark.Value, error) {
			q, err := oneStr("refs_from")(t, b, a, k)
			if err != nil {
				return nil, err
			}
			return list("reference", refFields, fx.RefsFrom[q]), nil
		}),
		// Same signature and engine as mxcli's builtinMatches: Go regexp (RE2).
		"matches": starlark.NewBuiltin("matches", func(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			var s, pattern string
			if err := starlark.UnpackArgs("matches", args, kwargs, "s", &s, "pattern", &pattern); err != nil {
				return nil, err
			}
			ok, err := regexp.MatchString(pattern, s)
			if err != nil {
				return nil, fmt.Errorf("matches: %v", err)
			}
			return starlark.Bool(ok), nil
		}),
		"location": starlark.NewBuiltin("location", func(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			var module, docType, docName, docID starlark.String
			if err := starlark.UnpackArgs("location", args, kwargs, "module", &module, "document_type", &docType, "document_name", &docName, "document_id?", &docID); err != nil {
				return nil, err
			}
			return starlarkstruct.FromStringDict(starlark.String("location"), starlark.StringDict{
				"module": module, "document_type": docType, "document_name": docName, "document_id": docID}), nil
		}),
		"violation": starlark.NewBuiltin("violation", func(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
			var message, suggestion starlark.String
			var loc starlark.Value = starlark.None
			if err := starlark.UnpackArgs("violation", args, kwargs, "message", &message, "location?", &loc, "suggestion?", &suggestion); err != nil {
				return nil, err
			}
			return starlarkstruct.FromStringDict(starlark.String("violation"), starlark.StringDict{
				"message": message, "location": loc, "suggestion": suggestion}), nil
		}),
	}

	thread := &starlark.Thread{Name: "starrun"}
	globals, err := starlark.ExecFile(thread, *rule, nil, predeclared)
	if err != nil {
		fmt.Fprintln(os.Stderr, "starrun: load:", err)
		os.Exit(1)
	}
	check, ok := globals["check"]
	if !ok {
		fmt.Fprintln(os.Stderr, "starrun: rule defines no check()")
		os.Exit(1)
	}
	res, err := starlark.Call(thread, check, nil, nil)
	if err != nil {
		fmt.Fprintln(os.Stderr, "starrun: check():", err)
		os.Exit(1)
	}
	type out struct {
		Module, DocumentType, DocumentName, Message, Suggestion string
	}
	rows := []map[string]string{}
	iter := res.(starlark.Iterable).Iterate()
	defer iter.Done()
	var v starlark.Value
	for iter.Next(&v) {
		st := v.(*starlarkstruct.Struct)
		row := map[string]string{"module": "", "document_type": "", "document_name": ""}
		if m, err := st.Attr("message"); err == nil {
			row["message"] = str(m)
		}
		if s, err := st.Attr("suggestion"); err == nil {
			row["suggestion"] = str(s)
		}
		if l, err := st.Attr("location"); err == nil {
			if ls, ok := l.(*starlarkstruct.Struct); ok {
				for _, k := range []string{"module", "document_type", "document_name"} {
					if x, err := ls.Attr(k); err == nil {
						row[k] = str(x)
					}
				}
			}
		}
		rows = append(rows, row)
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", " ")
	_ = enc.Encode(rows)
}

var entityFields = fields{
	s: []string{"id", "name", "qualified_name", "module_name", "folder", "entity_type", "description", "generalization"},
	b: []string{"has_event_handlers", "is_external", "has_created_date", "has_changed_date", "has_owner", "has_changed_by"},
	i: []string{"attribute_count", "access_rule_count", "validation_rule_count"},
}
var associationFields = fields{
	s: []string{"name", "qualified_name", "module_name", "from_entity", "to_entity", "type", "owner",
		"storage_format", "description", "to_delete_behavior", "from_delete_behavior"},
}
var stringFields = fields{
	s: []string{"qualified_name", "object_type", "value", "context", "language", "element_id", "module_name"},
}
var permissionFields = fields{
	s: []string{"module_role_name", "module_name", "entity_name", "access_type", "member_name",
		"xpath_constraint", "default_member_access_rights", "element_type", "element_name"},
	b: []string{"is_constrained"},
}
var attributeFields = fields{
	s: []string{"id", "name", "entity_id", "entity_qualified_name", "module_name", "data_type",
		"default_value", "description"},
	b: []string{"is_unique", "is_required", "is_calculated"},
	i: []string{"length"},
}
var roleMappingFields = fields{
	s: []string{"user_role_name", "module_role_name", "module_name"},
}

// userRoles builds user_role structs; module_roles is a list of strings, which the generic
// toStruct does not handle.
func userRoles(rows []map[string]any) *starlark.List {
	out := make([]starlark.Value, 0, len(rows))
	for _, r := range rows {
		d := starlark.StringDict{}
		for k := range r {
			if k != "name" && k != "is_anonymous" && k != "module_roles" {
				fmt.Fprintf(os.Stderr, "starrun: fixture user_role has unknown field %q (not in the mxcli projection)\n", k)
				os.Exit(1)
			}
		}
		name, _ := r["name"].(string)
		anon, _ := r["is_anonymous"].(bool)
		mrs := []starlark.Value{}
		if xs, ok := r["module_roles"].([]any); ok {
			for _, x := range xs {
				if s, ok := x.(string); ok {
					mrs = append(mrs, starlark.String(s))
				}
			}
		}
		if !strip["name"] {
			d["name"] = starlark.String(name)
		}
		if !strip["is_anonymous"] {
			d["is_anonymous"] = starlark.Bool(anon)
		}
		if !strip["module_roles"] {
			d["module_roles"] = starlark.NewList(mrs)
		}
		out = append(out, starlarkstruct.FromStringDict(starlark.String("user_role"), d))
	}
	return starlark.NewList(out)
}
