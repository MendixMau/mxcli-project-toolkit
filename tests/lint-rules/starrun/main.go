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
//   go run ./tests/lint-rules/starrun -rule lint-rules/x.star -fixture f.json [-strip-fields a,b]
// Prints a JSON array of {module,document_type,document_name,message,suggestion}.
// Exit 0 on success, 1 on a load/eval error (message on stderr).
//
// Fixture schema (every key optional, missing struct fields default to ""/false/0):
//   {"widgets":[{...}], "microflows":[{...}], "pages":[{...}],
//    "activities":{"Mod.Flow":[{...}]}, "refs_from":{"Mod.Flow":[{...}]}}
// Field names are the mxcli Starlark projection names (mdl/linter/starlark.go):
// widget: id name widget_type container_id container_qualified_name container_type
//   module_name entity_ref attribute_ref microflow_ref nanoflow_ref page_ref
//   parent_widget_id depth class_name style dynamic_classes action_type has_confirmation
// microflow: id name qualified_name module_name folder microflow_type description
//   return_type parameter_count activity_count total_activity_count complexity
// activity: id name caption activity_type action_type microflow_id
//   microflow_qualified_name module_name entity_ref service_ref action_ref
//   use_request_timeout timeout_expression auto_generate_caption description
//   parent_loop_id loop_depth condition_expression condition_rule error_handling_type
//   log_level log_node_expression log_message commit_type with_events retrieve_source queue_ref
// reference: source_type source_id source_name target_type target_id target_name ref_kind module_name
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
	Widgets    []map[string]any            `json:"widgets"`
	Microflows []map[string]any            `json:"microflows"`
	Pages      []map[string]any            `json:"pages"`
	Activities map[string][]map[string]any `json:"activities"`
	RefsFrom   map[string][]map[string]any `json:"refs_from"`
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
		"struct":     starlark.NewBuiltin("struct", starlarkstruct.Make),
		"widgets":    noArgs("widgets", list("widget", widgetFields, fx.Widgets)),
		"microflows": noArgs("microflows", list("microflow", microflowFields, fx.Microflows)),
		"pages":      noArgs("pages", list("page", pageFields, fx.Pages)),
		"activities_for": starlark.NewBuiltin("activities_for", func(t *starlark.Thread, b *starlark.Builtin, a starlark.Tuple, k []starlark.Tuple) (starlark.Value, error) {
			q, err := oneStr("activities_for")(t, b, a, k)
			if err != nil {
				return nil, err
			}
			return list("activity", activityFields, fx.Activities[q]), nil
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
