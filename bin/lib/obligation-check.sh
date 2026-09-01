#!/usr/bin/env bash
# obligation-check.sh — the forward and reverse checks over bin/lib/obligations.tsv.
#
# WHY THIS EXISTS: read the header of bin/lib/obligations.tsv. In one line — install-manifest.sh
# made a missing FILE impossible to miss, and this does the same for a missing PASS.
#
# WHAT IT IS NOT: a judge. It never decides whether a review was any good, whether a sweep found
# the right things, or whether a page looks right. Those verdicts live in the skills the table's
# ninth column names (skills-over-scripts.md). This script fetches one fact per obligation —
# "is there a mark, and does it state its denominator" — and prints it. It is an instrument: it
# may report FAULT (I could not measure), never FAIL (this is wrong).
#
# Sourced by bin/gate-check.sh. Also runnable directly for a quick read:
#     bin/lib/obligation-check.sh <project-dir>
#
# Verdicts, per obligation × scope unit:
#   PASS     the mark is there and states its denominator
#   PENDING  not yet — the unit is in scope and no mark exists
#   FAULT    a mark exists but cannot be read as evidence (no denominator on a pass that owes one)
#   WAIVED   the register says this one is out of scope, with a reason
#   ADOPTED  the project joined the pipeline above this obligation's stage
#   N/A      this project is not running the pipeline at all (a-la-carte; existing-app-assurance.md)

set -uo pipefail

_OB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
OBLIGATIONS_TSV="${OBLIGATIONS_TSV:-$_OB_LIB_DIR/obligations.tsv}"

# Skills in the `verify` group that deliberately owe no per-module artifact. The reverse check
# warns about any verify-group skill NOT named by an obligation; anything listed here is an
# accepted absence WITH ITS REASON, exactly like MXTK_PROJECT_BIN_NOINSTALL in
# install-manifest.sh. Warning-only by design, for the reason that file already documents: a
# check that can brick a run gets commented out within a week, and then it checks nothing.
#
# The scope is the `verify` group specifically, not everything routed at stage 5/6. Every skill
# a build session loads is not a pass — an MDL cookbook owes no report — and a check that warns
# about forty of them is a check nobody reads. Adding a new verify-group skill should cost one
# line here or one row in obligations.tsv; that is the whole point.
MXTK_OBLIGATIONS_NOROUTE="
verify-module          the instrument; the journeys obligation measures its output
testing-shape          vocabulary for the brief's test plan, not a pass
harness-architecture   architecture rules for the instruments, not a pass over the app
report-schema          how a report must read; enforced inside the reports themselves
e2e-evidence-report    the denominator rule; enforced by the denominator column here
e2e-harness-base       setup for the harness, not a pass
fixture-seeding        setup for a pass, not a pass
learned-db-assertions  technique used inside the journeys obligation
journey-proof          the deep form of the journeys obligation, which already owes a mark
conformance-check      a script; runs inside verify-module.sh and lands in its summary
graph-sweep            a script; runs inside verify-module.sh and lands in its summary
lint-gate              lands in the build gate, not in a per-module review artifact
lint-that-actually-runs  same gate as lint-gate
test-stack-up          project-level setup, done once
coherence-cadence      the trigger for the coherence obligation, not a second obligation
process-coherence-pass the coherence obligation is its mark
monkey-test            runs inside verify-module.sh and lands in its summary
existing-app-assurance the a-la-carte entry; by definition owes the pipeline nothing
learned-skill-ux-audit  a technique applied during the LOOK, which already owes a mark
learned-skill-scope-delta  a technique, not a pass
wiring-sweep           the sweep obligation is its mark
"

# ── helpers ─────────────────────────────────────────────────────────────────
# Deliberately self-contained: gate-check.sh's reg_field() is defined after this file is sourced
# in some orders, and a lib that only works at one source position is a wiring bug waiting.
_ob_register_lines() {
  [ -f "$1" ] || return 0
  awk '/<!--/{c=1} c{if($0~/-->/)c=0;next}
       {l=$0; gsub(/^[ \t>*_-]+/,"",l); gsub(/\*/,"",l); print l}' "$1"
}

# _ob_waiver <register> <obligation> <unit>  → prints the reason, exits 0 if waived.
# Spelling, matching the per-stage waivers gate-check.sh already reads:
#     Waived obligation look/Orders: integration module, no pages
#     Waived obligation sweep: this project tests in the client's own suite   (all units)
# --- Register parsing: ONCE per file, not once per lookup ---------------------------------
#
# WHY (2026-08-25). _ob_waiver() is called for every (obligation x unit) pair, and each call
# re-read the whole register, forking `tr` AND `sed` for EVERY LINE. Measured on a one-module
# project: 603 `sed` + 345 `tr` out of 1,127 total forks in a single gate-check run — and it
# scaled at roughly +800 forks per module, so it got worse exactly as a project grew.
#
# That is free on Linux/macOS (~4ms a fork) and ruinous under Git Bash on Windows, where MSYS
# emulates fork() with CreateProcess and a spawn measured 152ms on a training laptop. 1,127
# forks x 152ms = 171s, which is why gate-check "hung" for 5-15 minutes there and got switched
# off. See the same root cause in project-bin/_common.sh's platform note.
#
# The parse is now one awk pass, memoized per register path. Trim + lowercase happen inside
# that pass rather than per line per lookup.
#
# NOTE ON \t: the old `sed 's/^[ \t]*//'` was not portable. BSD sed (macOS) does not read \t as
# tab inside a bracket expression — it read it as the literal characters backslash and 't', so
# a key beginning with 't' had it stripped. GNU sed (Git Bash, Linux) read a real tab. The
# awk below trims real whitespace on every platform, which is what the code always meant.
_OB_REG_NORM=""        # cached "key<TAB>value" lines, key lowercased, both trimmed
_OB_REG_NORM_FILE=""   # which register path _OB_REG_NORM was built from

_ob_register_norm() { # sets _OB_REG_NORM
  local reg="$1"
  [ "$_OB_REG_NORM_FILE" = "$reg" ] && return 0
  _OB_REG_NORM_FILE="$reg"
  _OB_REG_NORM="$(_ob_register_lines "$reg" | awk '
    { i = index($0, ":"); if (i == 0) next
      k = substr($0, 1, i-1); v = substr($0, i+1)
      gsub(/^[ \t]+/, "", k); gsub(/[ \t]+$/, "", k)
      gsub(/^[ \t]+/, "", v); gsub(/[ \t]+$/, "", v)
      if (v == "") next
      print tolower(k) "\t" v }')"
  return 0
}

# _ob_lc <string> — sets _OB_LC to the lowercased string. Sets a global instead of echoing
# because "$(_ob_lc x)" would fork a subshell, which is the cost this whole change removes.
# Hand-rolled because bash 3.2 (macOS's /bin/bash) has no ${var,,}.
_OB_LC=""
_ob_lc() {
  local s="$1" out="" c i=0 n=${#1}
  while [ $i -lt $n ]; do
    c=${s:$i:1}
    case $c in
      A) c=a ;; B) c=b ;; C) c=c ;; D) c=d ;; E) c=e ;; F) c=f ;; G) c=g ;; H) c=h ;;
      I) c=i ;; J) c=j ;; K) c=k ;; L) c=l ;; M) c=m ;; N) c=n ;; O) c=o ;; P) c=p ;;
      Q) c=q ;; R) c=r ;; S) c=s ;; T) c=t ;; U) c=u ;; V) c=v ;; W) c=w ;; X) c=x ;;
      Y) c=y ;; Z) c=z ;;
    esac
    out="$out$c"; i=$((i+1))
  done
  _OB_LC="$out"
}

_ob_waiver() {
  local reg="$1" ob="$2" unit="$3" line key val want_u want_a
  # Compared case-insensitively: reg_field() lowercases the key it reads, and a waiver that
  # silently missed because someone typed "orders" for module "Orders" would be a waiver the
  # author believes is in force and the gate does not — the worst of both.
  _ob_lc "waived obligation $ob/$unit"; want_u="$_OB_LC"
  _ob_lc "waived obligation $ob";       want_a="$_OB_LC"
  _ob_register_norm "$reg"
  local IFS=$'\n'
  for line in $_OB_REG_NORM; do
    key="${line%%$'\t'*}"; val="${line#*$'\t'}"
    if [ "$key" = "$want_u" ] || [ "$key" = "$want_a" ]; then
      printf '%s\n' "$val"; return 0
    fi
  done
  return 1
}

_ob_adopted_stage() {
  local reg="$1" line key val
  _ob_register_norm "$reg"
  local IFS=$'\n'
  for line in $_OB_REG_NORM; do
    key="${line%%$'\t'*}"; val="${line#*$'\t'}"
    [ "$key" = "adopted at stage" ] || continue
    # First whitespace-delimited word, as `awk '{print $1}'` gave. Value is already trimmed,
    # so the leading-blank case awk tolerated cannot arise here.
    printf '%s\n' "${val%%[ 	]*}"
    return 0
  done
  return 1
}

_ob_rank() { case "$1" in P|p) echo 0 ;; [0-7]) echo $(( $1 + 1 )) ;; *) echo 99 ;; esac; }

# The scope unit set. A module is IN SCOPE once it has been opened for work — a brief directory
# under architecture/modules/, or a verify run. NOT every module in the MPR: an app that predates
# the toolkit owes nothing for modules nobody is building (obligations.tsv header, and
# existing-app-assurance.md's matching rule for coverage).
_ob_modules() {
  local root="$1" d
  { [ -d "$root/architecture/modules" ] && for d in "$root/architecture/modules"/*/; do
      [ -d "$d" ] && basename "$d"; done
    [ -d "$root/.claude/loop/verify" ] && for d in "$root/.claude/loop/verify"/*/; do
      [ -d "$d" ] && basename "$d"; done
  } 2>/dev/null | sed '/^$/d' | sort -u
}

# Does the artifact exist for this unit? Echoes the file that discharges it, or nothing.
_ob_find() {
  local root="$1" match="$2" pattern="$3" unit="$4" resolved f
  if [ "$match" = "path" ]; then
    resolved="${pattern//<Module>/$unit}"
    [ -s "$root/$resolved" ] && printf '%s\n' "$root/$resolved"
    return 0
  fi
  # match=names: any non-empty file matching the glob that MENTIONS the unit — NEWEST FIRST.
  #
  # Glob order is alphabetical, which for `ui-review-<date>.html` means OLDEST first, and this
  # returned the first match. So a project that reviewed its module again — properly, with
  # PROOF-OF-LOOK citations and committed screenshots — still reported
  # `look FAULT: NO PROOF-OF-LOOK`, because a superseded report from an earlier date sorted
  # ahead of it and was the only one ever read. The remedy the message names (add the proof)
  # therefore could not clear the finding, which is the worst shape a guard can take: it points
  # at a fix that does not work.
  #
  # Newest-first is right for every obligation here, not just LOOK. These ask "has this pass
  # been performed on the model as it stands", and the newest evidence is the evidence;
  # `_ob_stale` already refuses a mark the model has been built past, so recency cannot smuggle
  # in a stale one. Sort by the filename's date when it has one (the modern schema names it),
  # falling back to mtime — a dateless file should not outrank a dated one by accident.
  #
  # Found 2026-09-01 on a dashboard-publishing migration: three review reports, the newest with
  # five citations and five committed captures, the oldest with none. The oldest won.
  local sorted f d mt
  sorted="$(for f in $root/$pattern; do
              [ -s "$f" ] || continue
              d="$(basename "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
              [ -n "$d" ] || d="0000-00-00"
              # SUB-SECOND mtime, GNU first then BSD — on GNU `stat -f` succeeds with the wrong
              # meaning, so GNU-first is mandatory here (bin/check-portability.sh enforces it).
              # Whole seconds are not enough: two reports written by the same session land in
              # the same second, tie, and fall through to the alphabetical last resort — which
              # is how a same-date pair was decided by a hyphen in the 2026-09-01 field case.
              mt="$(stat -c %.9Y "$f" 2>/dev/null || stat -f %Fm "$f" 2>/dev/null \
                    || stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
              printf '%s\t%s\t%s\n' "$d" "${mt:-0}" "$f"
            done | LC_ALL=C sort -k1,1r -k2,2nr -k3,3r | cut -f3)"
  for f in $sorted; do
    if [ "$unit" = "-" ] || grep -qF -- "$unit" "$f" 2>/dev/null; then printf '%s\n' "$f"; fi
  done
  return 0
}

# A denominator is a first line that counts something out of something: "12 of 12 pages reviewed".
# Deliberately loose — the wording belongs to the skill, only the shape is mechanical.
_ob_has_denominator() {
  head -c 4000 "$1" 2>/dev/null | tr -d '\r' \
    | grep -qiE '[0-9]+[[:space:]]+of[[:space:]]+[0-9]+|[0-9]+[[:space:]]*/[[:space:]]*[0-9]+'
}

# _ob_stale <project-root> <artifact>  → prints "<hash>+<n>" and returns 0 if the mark has
# expired; returns 1 if current, unstamped, or unmeasurable.
#
# A review artifact may stamp the commit it was true at: "VALID AT: <short-hash>"
# (module-review.md stage 5 — the LOOK report headline). If commits touching the model (*.mpr,
# mdlsource/) exist after that hash, the artifact describes a model that no longer exists and
# the pass is owed again. Measured consequence, 2026-08-22: a month-old green LOOK report was
# cited for a page several later build sessions had changed underneath it — no page title, an
# unstyled nav bar, a missing field, none of it in the report.
#
# Opt-in by the artifact itself carrying the stamp: reports that predate the rule are left
# alone (this check must never retro-brick a project — the reverse, a stamped report going
# quietly stale, is the failure being retired). Unmeasurable (no git, hash unknown here) also
# returns 1: an instrument reports what it measured, and "could not measure" must not read as
# "expired".
_ob_stale() {
  local root="$1" hit="$2" hash n
  hash="$(head -c 8000 "$hit" 2>/dev/null | tr -d '\r' \
    | grep -oiE 'VALID[[:space:]]+AT:?[[:space:]]*[0-9a-f]{7,40}' \
    | grep -oiE '[0-9a-f]{7,40}$' | head -1)"
  [ -n "$hash" ] || return 1
  git -C "$root" cat-file -e "${hash}^{commit}" 2>/dev/null || return 1
  n="$(git -C "$root" log --oneline "${hash}..HEAD" -- '*.mpr' mdlsource 2>/dev/null | wc -l | tr -d ' ')"
  [ "${n:-0}" -gt 0 ] || return 1
  printf '%s+%s' "$hash" "$n"
  return 0
}

# _ob_look_proof_broken <project-root> <report>  → prints WHY the proof is broken and returns 0;
# returns 1 when the proof holds or the report predates the rule.
#
# THE PROOF-OF-LOOK RULE (module-review.md stage 5). A LOOK verdict is only evidence if the
# reviewer actually looked at rendered pixels. The 2026-08-22 escape proved a report can cite
# CSS declarations page after page ("grid-template-columns: repeat(4,1fr) — matches wireframe")
# while the render is ragged, a field is missing and the page has no title. Prose rules did not
# stop it, because nothing mechanical distinguished a pixel review from a CSS read. This does:
#
#   Each reviewed page cites its screenshot, one line, greppable inside the HTML:
#       PROOF-OF-LOOK: <Module.PageName> = <path relative to the report>
#   and the checker verifies what a citation cannot fake:
#     1. at least as many citations as the headline's reviewed-page count;
#     2. every cited file EXISTS on disk and is ≥ 10 KB — a real full-page PNG is hundreds of
#        KB; a blank capture or a placeholder is not (base64 embeds in the report are display,
#        not proof: they cannot be checked for freshness);
#     3. every cited file is NEWER than the report's VALID AT commit — shots are taken during
#        the review, after the last model commit; citing last month's screenshots fails here.
#   A report that fails is treated exactly like no report (FAULT): a visual verdict with no
#   verifiable screenshot behind it is a CSS review wearing a LOOK report's clothes.
#
# Adoption boundary: reports whose filename date (ui-review-<YYYY-MM-DD>*.html) is on/after
# 2026-08-23 owe the proof; older reports are left alone (never retro-brick, same stance as
# _ob_stale). A dateless filename that matched the artifact glob owes it too — the modern
# schema names its date. Freshness (rule 3) is checked only when VALID AT resolves in git and
# the mtime is measurable; an instrument reports what it measured, and "could not measure"
# must not read as "broken".
_OB_LOOK_PROOF_SINCE="2026-08-23"
_ob_look_proof_broken() {
  local root="$1" hit="$2" fdate reldir entries n_cited=0 missing="" small="" oldshots=""
  fdate="$(basename "$hit" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
  if [ -n "$fdate" ] && [[ "$fdate" < "$_OB_LOOK_PROOF_SINCE" ]]; then return 1; fi

  entries="$(tr -d '\r' < "$hit" | grep -oE 'PROOF-OF-LOOK:[[:space:]]*[^=<]+=[[:space:]]*[^<>[:space:]]+')"
  if [ -z "$entries" ]; then
    printf 'no PROOF-OF-LOOK citations — verdicts with no screenshot on disk are a CSS review'
    return 0
  fi

  # Headline denominator: first number of "N of M pages" is how many pages claim review.
  local claimed
  claimed="$(head -c 4000 "$hit" 2>/dev/null | tr -d '\r' \
    | grep -oiE '[0-9]+[[:space:]]+of[[:space:]]+[0-9]+' | head -1 | awk '{print $1}')"

  # VALID AT commit time, for freshness. Unresolvable → freshness unmeasured, not failed.
  local vhash vtime=""
  vhash="$(head -c 8000 "$hit" 2>/dev/null | tr -d '\r' \
    | grep -oiE 'VALID[[:space:]]+AT:?[[:space:]]*[0-9a-f]{7,40}' \
    | grep -oiE '[0-9a-f]{7,40}$' | head -1)"
  [ -n "$vhash" ] && vtime="$(git -C "$root" show -s --format=%ct "${vhash}^{commit}" 2>/dev/null || true)"

  reldir="$(dirname "$hit")"
  local line page shot f sz mt
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    page="$(printf '%s' "$line" | sed 's/^PROOF-OF-LOOK:[[:space:]]*//;s/[[:space:]]*=.*$//')"
    shot="$(printf '%s' "$line" | sed 's/^.*=[[:space:]]*//')"
    n_cited=$((n_cited+1))
    case "$shot" in /*) f="$shot" ;; *) f="$reldir/$shot" ;; esac
    if [ ! -f "$f" ]; then missing="$missing $page"; continue; fi
    sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
    if [ "${sz:-0}" -lt 10240 ]; then small="$small $page"; continue; fi
    if [ -n "$vtime" ]; then
      mt="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || true)"
      [ -n "$mt" ] && [ "$mt" -lt "$vtime" ] && oldshots="$oldshots $page"
    fi
  done <<< "$entries"

  local why=""
  [ -n "$missing" ] && why="cited screenshots not on disk:$missing"
  [ -n "$small" ] && why="${why:+$why; }cited screenshots under 10KB (blank/placeholder):$small"
  [ -n "$oldshots" ] && why="${why:+$why; }screenshots older than VALID AT (a previous review's shots):$oldshots"
  if [ -n "$claimed" ] && [ "$n_cited" -lt "$claimed" ]; then
    why="${why:+$why; }$n_cited citation(s) for $claimed reviewed page(s)"
  fi
  [ -z "$why" ] && return 1
  printf '%s' "$why"
  return 0
}

# ── the forward check ───────────────────────────────────────────────────────
# mxtk_obligations_report <project-dir> [register-path]
# Prints one line per obligation. Sets MXTK_OB_STATUS to the worst verdict seen.
mxtk_obligations_report() {
  local root="$1" reg="${2:-$1/PROJECT.md}"
  MXTK_OB_STATUS="PASS"; MXTK_OB_LINES=""

  if [ ! -f "$OBLIGATIONS_TSV" ]; then
    # The table is the thing this check IS. Missing table is a fault in the check, and it says so
    # rather than printing a clean sheet — the exact failure mode the table exists to retire.
    printf 'Obligations: FAULT — %s not found; no pass was checked (this is the checker failing, not the project)\n' \
      "$OBLIGATIONS_TSV"
    MXTK_OB_STATUS="FAULT"; return 0
  fi

  # A-la-carte: no register and no module briefs means no pipeline. Say "does not apply" out loud
  # rather than printing nothing; silence is the failure mode this whole file exists to remove.
  if [ ! -f "$reg" ] && [ ! -d "$root/architecture/modules" ]; then
    printf 'Obligations: N/A — no PROJECT.md and no architecture/modules/; this is not a pipeline project (existing-app-assurance.md)\n'
    return 0
  fi

  local adopted; adopted="$(_ob_adopted_stage "$reg" || true)"
  local adopted_rank=0
  [ -n "$adopted" ] && adopted_rank="$(_ob_rank "$adopted")"

  local modules; modules="$(_ob_modules "$root")"
  local ob performer scope match artifact denom degradable from_stage skill

  while IFS=$'\t' read -r ob performer scope match artifact denom degradable from_stage skill; do
    case "$ob" in ''|'#'*|obligation) continue ;; esac

    if [ "$(_ob_rank "$from_stage")" -lt "$adopted_rank" ]; then
      printf 'Obligation %-10s ADOPTED — project joined at stage %s, above this pass'"'"'s stage %s (%s)\n' \
        "$ob" "$adopted" "$from_stage" "$skill"
      continue
    fi

    local units
    case "$scope" in
      module)  units="$modules" ;;
      cluster|project) units="$scope" ;;
      *) printf 'Obligation %-10s FAULT — unknown scope "%s" in %s\n' "$ob" "$scope" "$OBLIGATIONS_TSV"
         MXTK_OB_STATUS="FAULT"; continue ;;
    esac

    if [ -z "$units" ]; then
      printf 'Obligation %-10s PASS — no module has been opened for work yet; nothing owed (%s)\n' "$ob" "$skill"
      continue
    fi

    local total=0 done_n=0 waived_n=0 pending="" faulted="" stale="" noproof="" u hit reason stale_at proof_why candidates c newest
    while IFS= read -r u; do
      [ -n "$u" ] || continue
      total=$((total+1))
      if reason="$(_ob_waiver "$reg" "$ob" "$u")"; then
        waived_n=$((waived_n+1)); continue
      fi
      # For cluster/project scope the unit name is the scope word itself; nothing to match on.
      if [ "$scope" = "module" ]; then
        hit="$(_ob_find "$root" "$match" "$artifact" "$u")"
      else
        hit="$(_ob_find "$root" "$match" "$artifact" "-")"
      fi
      # Walk the candidates NEWEST FIRST and take the first that satisfies every rule.
      #
      # Not "judge the newest and stop". The three disqualifiers below (no denominator, broken
      # LOOK proof, stale) each turn one report into no-report, and if only the newest is ever
      # examined then a perfectly good earlier report — one whose denominator IS stated, whose
      # screenshots ARE on disk — is invisible behind it. Trying them in order is also what
      # makes the ordering safe: ties between same-date reports stop mattering, because a tie
      # no longer discards anyone. And an OLD report can only win here if `_ob_stale` clears
      # it, which means the model has not been built past it — in which case it is current
      # evidence whatever its filename says. Nothing is gamed by keeping old reports around.
      candidates="$hit"
      hit=""; newest=""
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        [ -n "$newest" ] || newest="$c"
        if [ "$denom" = "yes" ] && ! _ob_has_denominator "$c"; then continue; fi
        if [ "$ob" = "look" ] && _ob_look_proof_broken "$root" "$c" >/dev/null; then continue; fi
        if _ob_stale "$root" "$c" >/dev/null; then continue; fi
        hit="$c"; break
      done <<< "$candidates"

      if [ -n "$hit" ]; then
        done_n=$((done_n+1))
      elif [ -z "$newest" ]; then
        pending="$pending $u"
      # Nothing qualified: report why the NEWEST one failed. It is the report the author most
      # recently wrote and the one they will go and fix, so naming an older file's problem
      # would send them to the wrong place.
      elif [ "$denom" = "yes" ] && ! _ob_has_denominator "$newest"; then
        faulted="$faulted $u"
      elif [ "$ob" = "look" ] && proof_why="$(_ob_look_proof_broken "$root" "$newest")"; then
        # A LOOK whose screenshots cannot be verified is a CSS review — treated as no report.
        noproof="$noproof $u($proof_why)"
      elif stale_at="$(_ob_stale "$root" "$newest")"; then
        # A stamped mark the model has been built past is not a mark — the pass is owed again.
        pending="$pending $u"
        stale="$stale $u(valid-at ${stale_at%%+*}, ${stale_at##*+} model commit(s) since)"
      else
        pending="$pending $u"
      fi
    done <<< "$units"

    local scoped=$((total - waived_n)) tail=""
    [ "$waived_n" -gt 0 ] && tail=" ($waived_n waived)"
    if [ -n "$faulted" ] || [ -n "$noproof" ]; then
      local why_bits=""
      [ -n "$faulted" ] && why_bits="NO DENOMINATOR:$faulted — a pass that cannot say what it covered has not covered it"
      [ -n "$noproof" ] && why_bits="${why_bits:+$why_bits; }NO PROOF-OF-LOOK — a visual verdict with no verifiable screenshot is a CSS review, treated as no report"
      printf 'Obligation %-10s FAULT — %d of %d discharged%s; %s (%s)\n' \
        "$ob" "$done_n" "$scoped" "$tail" "$why_bits" "$skill"
      MXTK_OB_STATUS="FAULT"
    elif [ -n "$pending" ]; then
      printf 'Obligation %-10s PENDING — %d of %d discharged%s; NOT DONE:%s — owner: %s-agent, governed by %s\n' \
        "$ob" "$done_n" "$scoped" "$tail" "$pending" "$performer" "$skill"
      [ "$MXTK_OB_STATUS" = "PASS" ] && MXTK_OB_STATUS="PENDING"
    else
      printf 'Obligation %-10s PASS — %d of %d discharged%s (%s)\n' "$ob" "$done_n" "$scoped" "$tail" "$skill"
    fi
    # Printed under whichever verdict won: a stale unit is counted in NOT DONE above, and this
    # line says WHY it is owed again rather than letting it read as never-reviewed.
    [ -n "$stale" ] && printf 'Obligation %-10s   STALE:%s — the model was built past the report; re-run the pass (module-review.md stage 5, VALID AT)\n' \
      "$ob" "$stale"
    [ -n "$noproof" ] && printf 'Obligation %-10s   NO PROOF-OF-LOOK:%s — the pixel rule, made mechanical (module-review.md stage 5, PROOF-OF-LOOK)\n' \
      "$ob" "$noproof"
  done < "$OBLIGATIONS_TSV"

  return 0
}

# ── the reverse check ───────────────────────────────────────────────────────
# Every skill routed per-module that no obligation names is either a pass nobody will notice
# skipping, or a deliberate non-pass that belongs in MXTK_OBLIGATIONS_NOROUTE. WARNING ONLY, for
# the reason install-manifest.sh's own reverse check documents: a check that can brick the run
# gets disabled, and a disabled check is worse than a noisy one.
mxtk_obligations_reverse_check() {
  local tsv="${1:-${SKILL_ROUTING_TSV:-$_OB_LIB_DIR/skill-routing.tsv}}"
  # A check that cannot find its input must SAY so. Caught 2026-08-21 by running this file from
  # a copy in /tmp: the routing table resolved to a path that did not exist, the function
  # returned 0, and a deliberately-unlisted skill produced no warning at all. That is the
  # absence-renders-green bug this whole file exists to retire, sitting inside the retirement.
  if [ ! -f "$tsv" ]; then
    printf '⚠ Obligations reverse check: FAULT — routing table not found at %s; no skill was checked\n' "$tsv" >&2
    return 0
  fi
  [ -f "$OBLIGATIONS_TSV" ] || {
    printf '⚠ Obligations reverse check: FAULT — %s not found; no skill was checked\n' "$OBLIGATIONS_TSV" >&2
    return 0; }
  local named unnamed="" name path when agents stages tier group
  named="$(awk -F'\t' '!/^#/ && NF>=9 && $1!="obligation"{print $9}' "$OBLIGATIONS_TSV")"
  while IFS=$'\t' read -r name path when agents stages tier group; do
    case "$name" in ''|'#'*) continue ;; esac
    # Per-module passes live in the `verify` group. Filtering on stage 5/6 alone caught 46
    # skills — an MDL cookbook and a datagrid note among them — and a warning listing 46
    # names is one nobody reads, which is the same as no check at all.
    [ "$group" = "verify" ] || continue
    printf '%s\n' "$named" | grep -qxF "$path" && continue
    printf '%s' "$MXTK_OBLIGATIONS_NOROUTE" | awk '{print $1}' | grep -qxF "$name" && continue
    unnamed="$unnamed $name"
  done < "$tsv"
  if [ -n "$unnamed" ]; then
    printf '⚠ Obligations reverse check: routed per-module but owed by nothing:%s\n' "$unnamed" >&2
    printf '  Either give it an obligation row in %s, or list it in MXTK_OBLIGATIONS_NOROUTE with a reason.\n' \
      "$OBLIGATIONS_TSV" >&2
  fi
  return 0
}

# Direct invocation: run both checks against a project dir.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  mxtk_obligations_report "${1:-$(pwd)}"
  mxtk_obligations_reverse_check
fi
