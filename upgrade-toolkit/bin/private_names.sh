#!/usr/bin/env bash
# Sourced by the leak checks. Sets DENY to the private denylist (customer, app and person names), joined with |.
# The list lives OUTSIDE the repo, so the repo itself never names a customer:
#   UPG_PRIVATE_NAMES (default ~/.config/upgrade-toolkit/private-names.txt), one extended regex per line, # comments.
# No file: DENY stays empty and PRIVATE_NAMES_FILE is unset; each caller decides whether that is allowed.
PRIVATE_NAMES_FILE=${UPG_PRIVATE_NAMES:-$HOME/.config/upgrade-toolkit/private-names.txt}
if [ -f "$PRIVATE_NAMES_FILE" ]; then
  DENY=$(grep -vE '^[[:space:]]*(#|$)' "$PRIVATE_NAMES_FILE" | paste -sd '|' -)
else
  DENY=''; unset PRIVATE_NAMES_FILE
fi
