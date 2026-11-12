#!/usr/bin/env bash
# vendorlib_mvn.sh APP DEPS [--apply]: fill APP/vendorlib with managed Java dependencies (and their runtime
# transitives) through HOST Maven, when `mx sync-java-dependencies` fails in a cloud container.
#
# Why (T2-9, T3-13, T4, T5, T6-2, T7-8, T8-14): Gradle inside the toolkit container has no proxy ("Could not resolve
# the CycloneDX Gradle plugin"); with proxy flags it still fails "Failed to find some hosts" because the shared egress
# gets 429 from one Maven Central host or another (T6, T7: repo.maven.apache.org; T2, T8: repo1.maven.org). Host Maven
# through a mirror that answers worked for T6 and T7 (scripts/vendorlib_mvn.sh, tools/mvn-deps).
#
# DEPS: a text file; every group:artifact:version found on a line is a dependency, so a deps list or the output of a
# failed `mx sync-java-dependencies` both work. Version ranges are refused (T6: a [2,3) range crawled 437 MB of poms).
# Mirrors are tried in order (UPG_MAVEN_MIRRORS, space separated). Only jars whose file name is in neither vendorlib/
# nor userlib/ are added; nothing is removed (jardedupe.py decides duplicates afterwards).
# Without --apply: print the plan, run nothing.
# Exit: 0 resolved (or plan), 1 every mirror failed, 2 usage or no dependency found, 3 version range (pin it).
set -uo pipefail
MVN=${UPG_MVN:-mvn}
MIRRORS=${UPG_MAVEN_MIRRORS:-https://maven-central.storage-download.googleapis.com/maven2 https://repo1.maven.org/maven2 https://repo.maven.apache.org/maven2}
[ $# -ge 2 ] || { echo "usage: vendorlib_mvn.sh APP DEPS [--apply]"; exit 2; }
app=$1; deps=$2; apply=0; [ "${3:-}" = "--apply" ] && apply=1
[ -d "$app" ] || { echo "no app folder: $app"; exit 2; }
[ -f "$deps" ] || { echo "no deps file: $deps"; exit 2; }
list=$(grep -oE '[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[][(),A-Za-z0-9_.-]+' "$deps" \
  | grep -E '^[A-Za-z]' | sed -E '/:[[(][^:]*$/!s/[],)]+$//' | sort -u)
[ -n "$list" ] || { echo "NO DEPENDENCY found in $deps (want group:artifact:version)"; exit 2; }
ranges=$(printf '%s\n' "$list" | grep -E ':[[(][^:]*$' || true)
if [ -n "$ranges" ]; then
  echo "RANGE: version ranges make Maven crawl every pom (T6); pin them in $deps:"; printf '  %s\n' $ranges; exit 3
fi
n=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
echo "plan: $n dependencies into $app/vendorlib; mirrors: $MIRRORS"
printf '  %s\n' $list
[ "$apply" = 1 ] || { echo "dry run (add --apply)"; exit 0; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>'
  echo '<groupId>upg</groupId><artifactId>vendorlib</artifactId><version>1</version><dependencies>'
  printf '%s\n' "$list" | while IFS=: read -r g a v; do
    echo "<dependency><groupId>$g</groupId><artifactId>$a</artifactId><version>$v</version></dependency>"; done
  echo '</dependencies></project>'; } > "$tmp/pom.xml"
ok=0
for m in $MIRRORS; do
  printf '<settings><mirrors><mirror><id>upg</id><mirrorOf>*</mirrorOf><url>%s</url></mirror></mirrors></settings>' "$m" > "$tmp/settings.xml"
  rm -rf "$tmp/out"; mkdir -p "$tmp/out"
  if "$MVN" -q -B -s "$tmp/settings.xml" -f "$tmp/pom.xml" dependency:copy-dependencies -DincludeScope=runtime \
       -DoutputDirectory="$tmp/out" > "$tmp/mvn.log" 2>&1; then ok=1; echo "resolved through $m"; break; fi
  echo "mirror failed: $m ($(grep -m1 -oE '(status code|code:|Status code) ?[0-9]{3}|ERROR.{0,120}' "$tmp/mvn.log" || echo 'see mvn output'))"
done
[ "$ok" = 1 ] || { echo "FAILED: every mirror failed; last Maven output:"; tail -n 15 "$tmp/mvn.log"; exit 1; }
mkdir -p "$app/vendorlib"; added=0; present=0
for j in "$tmp"/out/*.jar; do
  [ -e "$j" ] || continue; b=$(basename "$j")
  if [ -e "$app/vendorlib/$b" ] || [ -e "$app/userlib/$b" ]; then present=$((present + 1)); continue; fi
  cp "$j" "$app/vendorlib/$b"; echo "added: $b"; added=$((added + 1))
done
echo "vendorlib_mvn: $added added, $present already present"
