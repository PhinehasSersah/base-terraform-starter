#!/usr/bin/env bash
set -euo pipefail

INVENTORY_DIR="ansible/inventory"
INVENTORY_FILE="${INVENTORY_DIR}/hosts.ini"

mkdir -p "$INVENTORY_DIR"
touch "$INVENTORY_FILE"

ENV="$(terraform workspace show)"
IPS="$(terraform output -json web_public_ips | jq -r '.[]')"

# Strip any existing [ENV] section (header + its IP lines) so re-running
# this script for the same workspace doesn't produce duplicate headers.
awk -v env="[$ENV]" '
  BEGIN { skip = 0 }
  {
    if ($0 == env) { skip = 1; next }
    if (skip == 1 && ($0 == "" || $0 ~ /^\[/)) { skip = 0 }
    if (skip == 0) print
  }
' "$INVENTORY_FILE" > "${INVENTORY_FILE}.tmp" && mv "${INVENTORY_FILE}.tmp" "$INVENTORY_FILE"

# Append this environment's fresh section
{
  echo "[$ENV]"
  echo "$IPS"
  echo ""
} >> "$INVENTORY_FILE"

echo "Wrote [$ENV] section to $INVENTORY_FILE"
