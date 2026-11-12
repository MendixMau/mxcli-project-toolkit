#!/usr/bin/env bash
# Internal/company hostnames this repo's export must never carry — kept OUTSIDE the
# repo for the same reason bin/private_names.sh keeps customer names outside: a
# tracked pattern naming the company domain is itself the leak.
#
# $UPG_PRIVATE_HOSTS (default ~/.config/upgrade-toolkit/private-hosts.txt): one
# extended-regex domain pattern per line to flag; blank/# ignored.
# $UPG_PRIVATE_HOSTS.allow (same path + .allow): specific full hostnames under
# those domains that are publicly fine (e.g. a public security-advisories
# subdomain) and should not be flagged.
PRIVATE_HOSTS_FILE=${UPG_PRIVATE_HOSTS:-$HOME/.config/upgrade-toolkit/private-hosts.txt}
if [ -f "$PRIVATE_HOSTS_FILE" ]; then
  HOSTS_DENY=$(grep -vE '^[[:space:]]*(#|$)' "$PRIVATE_HOSTS_FILE" | paste -sd '|' -)
else
  HOSTS_DENY=''
fi
if [ -f "$PRIVATE_HOSTS_FILE.allow" ]; then
  HOSTS_ALLOW=$(grep -vE '^[[:space:]]*(#|$)' "$PRIVATE_HOSTS_FILE.allow" | paste -sd '|' -)
else
  HOSTS_ALLOW=''
fi
