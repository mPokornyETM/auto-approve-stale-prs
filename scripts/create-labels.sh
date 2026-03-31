#!/bin/bash
# Create countdown labels (idempotent)
set -euo pipefail

DAYS=${DAYS:-3}

declare -A LABELS=(
  ["merge-in-${DAYS}-days-without-review"]="c2e0c6"   # green
  ["merge-in-$((DAYS-1))-days-without-review"]="fbca04" # yellow
  ["merge-in-1-day-without-review"]="e99695"           # red-ish
  ["merged-without-review"]="d93f0b"                   # dark orange
)

# For 3-day countdown, we need labels for days 3, 2, 1
# Dynamically generate intermediate labels if DAYS > 3
if [ "$DAYS" -gt 3 ]; then
  for ((i=DAYS; i>1; i--)); do
    if [ "$i" -eq 1 ]; then
      LABELS["merge-in-1-day-without-review"]="e99695"
    else
      # Color gradient from green to yellow to red
      if [ "$i" -gt $((DAYS * 2 / 3)) ]; then
        color="c2e0c6"  # green
      elif [ "$i" -gt $((DAYS / 3)) ]; then
        color="fbca04"  # yellow
      else
        color="e99695"  # red-ish
      fi
      LABELS["merge-in-${i}-days-without-review"]="$color"
    fi
  done
fi

echo "Creating countdown labels for ${DAYS}-day countdown..."

for label in "${!LABELS[@]}"; do
  echo "  → Creating label: $label"
  gh label create "$label" \
    --repo "$REPO" \
    --color "${LABELS[$label]}" \
    --description "Auto-approve countdown" \
    --force 2>/dev/null || true
done

echo "Labels ready."
