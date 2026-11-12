#!/usr/bin/env bash
# fake-update.sh SRC MODULE MPR [mxcli flags...]: stands in for "mxcli marketplace update" in the stepupdate controls.
# It prints the real mxcli refusals seen in runs E4 and E5b; the module name picks the behaviour.
src=$1 mod=$2 mpr=$3; shift 3
args=" $* "
banner() { echo "WARNING: This is a vibe-coded PoC, alpha quality, use with caution."; }
case "$mod" in
  Fine*) cp "$src/step1-adds/App.mpr" "$mpr";;
  Guid*) cp "$src/guid-changed/App.mpr" "$mpr";;
  Removes*) cp "$src/base/App.mpr" "$mpr";;
  Widg*) cp "$src/step1-adds/App.mpr" "$mpr"; cp "$src"/widgets-new/*.mpk "$(dirname "$mpr")/widgets/";;   # NS-6: cdd62cc5 swapped Datagrid
  Recreate*) cp "$src/recreate/App.mpr" "$mpr";;   # NS-7: cc318c0b re-created DataWidgets, every unit id new   # on an app at step1-adds: a removal, idcheck REVIEW (E6-7)
  UiEdit*|LogicEdit*|ConvUi*|JarDep*|JavaAct*)
    if [[ "$args" == *" --force "* && "$args" == *" --save-edits "* ]]; then
      dir=$(echo "$args" | sed -E 's/.* --save-edits ([^ ]+) .*/\1/'); mkdir -p "$dir"; echo "page" > "$dir/Home.page.mdl"
      cp "$src/step1-adds/App.mpr" "$mpr"; exit 0
    fi
    banner
    echo "refusing to update: 2 element(s) have been changed locally and the update would discard them:"
    if [[ $mod == UiEdit* ]]; then echo "    PAGE Home"; echo "    LAYOUT Layout_Menu"
    elif [[ $mod == JarDep* ]]; then echo "    JAR_DEPENDENCY org.apache.commons:commons-lang3"; echo "    JAR_DEPENDENCY commons-io:commons-io"   # T7-15
    elif [[ $mod == JavaAct* ]]; then echo "    JAVA_ACTION GetCurrentIdToken"; echo "    JAVA_ACTION StartLogin"            # T5-9, T8-12
    else echo "    MICROFLOW Column_SetCorrectRefObjectType"; echo "    RULE ValidateColumn"; fi
    echo; echo "  - Save them first:  --save-edits <dir>"; echo "  - Then update:      --force"; exit 1;;
  OldBase*)
    [[ "$args" == *" --no-baseline "* ]] && { cp "$src/step1-adds/App.mpr" "$mpr"; exit 0; }
    banner; echo "mx module-import failed: exit status 117"
    echo "The package could not be imported, because it was created with version 9.6.0 of Mendix Studio Pro. Please open it in any version in the range from 9.18.0 to 9.24.99 first."
    exit 1;;
  OldPkg*)
    echo junk > "$(dirname "$mpr")/junk.txt"; cp "$src/step1-adds/App.mpr" "$mpr"
    banner; echo "mx module-import failed: exit status 117"
    echo "The package could not be imported, because it was created with version 9.3.0 of Mendix Studio Pro. Please open it in any version in the range from 9.18.0 to 9.24.99 first."
    exit 1;;
  Old11Base*)  # F13: the INSTALLED package (baseline) was made before 10.21; the --no-baseline route imports the target
    [[ "$args" == *" --no-baseline "* ]] && { cp "$src/step1-adds/App.mpr" "$mpr"; exit 0; }
    banner; echo "mx module-import failed: exit status 117"
    echo "The package could not be imported, because it was created with version 10.5.0 of Mendix Studio Pro. Please open it in any version in the range from 10.21.0 to 10.24.99 first."
    exit 1;;
  Old11Pkg*)  # F13 (Purchase Request 10.24, real run): the verbatim mx 11.12.5 refusal of a package made before 10.21
    echo junk > "$(dirname "$mpr")/junk.txt"; cp "$src/step1-adds/App.mpr" "$mpr"
    banner; echo "mx module-import failed: exit status 117"
    echo "The package could not be imported, because it was created with version 10.6.0 of Mendix Studio Pro. Please open it in any version in the range from 10.21.0 to 10.24.99 first."
    exit 1;;
  Gone*)
    [[ "$args" == *" --no-baseline "* ]] && { cp "$src/step1-adds/App.mpr" "$mpr"; exit 0; }
    banner; echo "download version 2.17.1: expected redirect, got HTTP 500"
    echo "hint: re-run with --no-baseline to update without that check (local edits are lost silently)"; exit 1;;
  NoBaseUi*)  # E7-1: the no-baseline route updates and saves nothing, even with --save-edits
    [[ "$args" == *" --no-baseline "* ]] && { echo "--no-baseline: skipping the local-edit check for $mod."; cp "$src/step1-adds/App.mpr" "$mpr"; exit 0; }
    banner; echo "download version 1.1.0: expected redirect, got HTTP 500"
    echo "hint: re-run with --no-baseline to update without that check (local edits are lost silently)"; exit 1;;
  Unread*)  # E6: the post-convert refusal that is not a --save-edits refusal
    if [[ "$args" == *" --force "* ]]; then
      if [[ "$args" == *" --save-edits "* ]]; then dir=$(echo "$args" | sed -E 's/.* --save-edits ([^ ]+) .*/\1/'); mkdir -p "$dir"; echo "page" > "$dir/P.page.mdl"; fi
      cp "$src/step1-adds/App.mpr" "$mpr"; exit 0
    fi
    echo "22 element(s) could not be read, so it cannot be shown that the module is unedited."
    echo "Re-run with --force to update anyway"; exit 1;;
  Administration)  # T5-17: the real module name, so the app MPR carries it; HTTP 500 on the baseline route, and the
                   # no-baseline route replaces the module's theme and JavaScript files like the real update does
    if [[ "$args" == *" --no-baseline "* ]]; then
      d=$(dirname "$mpr")
      if [ -d "$d/themesource/administration" ]; then
        cp "$UPG_NEWVARS" "$d/themesource/administration/web/_variables.scss"; echo "export const a = 3;" > "$d/javascriptsource/administration/actions/util.js"
      fi
      cp "$src/step1-adds/App.mpr" "$mpr"; exit 0
    fi
    banner; echo "download version 4.1.0: expected redirect, got HTTP 500"
    echo "hint: re-run with --no-baseline to update without that check (local edits are lost silently)"; exit 1;;
  Flaky*)  # T1-13, T2-21, T3-2: a Marketplace TLS timeout that clears on the next try (counter next to the mpr)
    c="$(dirname "$mpr")/.stepupdate/flaky.count"; n=$(cat "$c" 2>/dev/null || echo 0); echo $((n + 1)) > "$c"
    [ "$n" -ge 1 ] && { cp "$src/step1-adds/App.mpr" "$mpr"; exit 0; }
    banner; echo "download version 1.1.0: Get \"https://marketplace.mendix.com/v1/content\": net/http: TLS handshake timeout"; exit 1;;
  Offline*) banner; echo "read tcp 10.0.0.2:4431->1.2.3.4:443: read: connection reset by peer"; exit 1;;
  Cert*) banner; echo "tls: failed to verify certificate: x509: certificate signed by unknown authority"; exit 1;;
  Broken*) banner; echo "something unexpected"; exit 3;;
  *) echo "fake-update: unknown module $mod" >&2; exit 9;;
esac
