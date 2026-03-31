#!/bin/bash
# Process open PRs with countdown labels and advance/approve them
# OPT-IN MODEL: Only PRs with a countdown label are processed
# The author must manually add 'merge-in-X-days-without-review' to start
set -euo pipefail

DAYS=${DAYS:-3}
ASSOCIATIONS=${ASSOCIATIONS:-"OWNER,MEMBER"}
MERGE_METHOD=${MERGE_METHOD:-"squash"}
DRY_RUN=${DRY_RUN:-"false"}
SKIP_DRAFTS=${SKIP_DRAFTS:-"true"}
REQUIRE_GREEN_CI=${REQUIRE_GREEN_CI:-"true"}

# Convert comma-separated to array
IFS=',' read -ra ASSOC_ARRAY <<< "$ASSOCIATIONS"

echo "Configuration:"
echo "  Days until approve: $DAYS"
echo "  Author associations: $ASSOCIATIONS"
echo "  Merge method: $MERGE_METHOD"
echo "  Dry run: $DRY_RUN"
echo "  Skip drafts: $SKIP_DRAFTS"
echo "  Require green CI: $REQUIRE_GREEN_CI"
echo ""

# Generate all countdown label names
START_LABEL="merge-in-${DAYS}-days-without-review"
FINAL_LABEL="merged-without-review"
COUNTDOWN_LABELS=("$FINAL_LABEL")
for ((i=DAYS; i>=1; i--)); do
  if [ "$i" -eq 1 ]; then
    COUNTDOWN_LABELS+=("merge-in-1-day-without-review")
  else
    COUNTDOWN_LABELS+=("merge-in-${i}-days-without-review")
  fi
done

echo "Countdown labels: ${COUNTDOWN_LABELS[*]}"
echo "Start label (opt-in): $START_LABEL"
echo ""

remove_countdown_labels() {
  local pr=$1
  for lbl in "${COUNTDOWN_LABELS[@]}"; do
    if [ "$DRY_RUN" == "true" ]; then
      echo "    [DRY-RUN] Would remove label: $lbl"
    else
      gh pr edit "$pr" --repo "$REPO" --remove-label "$lbl" 2>/dev/null || true
    fi
  done
}

add_label() {
  local pr=$1
  local label=$2
  if [ "$DRY_RUN" == "true" ]; then
    echo "    [DRY-RUN] Would add label: $label"
  else
    gh pr edit "$pr" --repo "$REPO" --add-label "$label"
  fi
}

# Check if a comment containing a marker already exists (for deduplication)
comment_exists() {
  local pr=$1
  local marker=$2
  local existing
  existing=$(gh pr view "$pr" --repo "$REPO" --json comments --jq ".comments[].body" 2>/dev/null || echo "")
  if echo "$existing" | grep -qF "$marker"; then
    return 0  # Comment exists
  fi
  return 1  # Comment does not exist
}

add_comment() {
  local pr=$1
  local body=$2
  local dedup_marker=${3:-""}  # Optional marker for deduplication
  
  # If dedup marker provided, check if similar comment already exists
  if [ -n "$dedup_marker" ]; then
    if comment_exists "$pr" "$dedup_marker"; then
      echo "    Comment already exists (dedup: $dedup_marker) — skipping"
      return 0
    fi
  fi
  
  if [ "$DRY_RUN" == "true" ]; then
    echo "    [DRY-RUN] Would add comment: $body"
  else
    gh pr comment "$pr" --repo "$REPO" --body "$body"
  fi
}

approve_pr() {
  local pr=$1
  local body=$2
  if [ "$DRY_RUN" == "true" ]; then
    echo "    [DRY-RUN] Would approve PR with: $body"
  else
    gh pr review "$pr" --repo "$REPO" --approve --body "$body"
  fi
}

merge_pr() {
  local pr=$1
  if [ "$DRY_RUN" == "true" ]; then
    echo "    [DRY-RUN] Would enable auto-merge (${MERGE_METHOD})"
  else
    gh pr merge "$pr" --repo "$REPO" --auto --"$MERGE_METHOD" || true
  fi
}

# Check if PR has passing CI checks
check_ci_status() {
  local pr=$1
  if [ "$REQUIRE_GREEN_CI" != "true" ]; then
    return 0  # Skip check if disabled
  fi
  
  # Get combined status from GitHub
  local status
  status=$(gh pr checks "$pr" --repo "$REPO" 2>/dev/null || echo "UNKNOWN")
  
  if echo "$status" | grep -qE "fail|pending|UNKNOWN"; then
    return 1  # CI not green
  fi
  return 0  # CI green
}

# Get current countdown position from labels
get_countdown_position() {
  local labels=$1
  
  for ((i=DAYS; i>=1; i--)); do
    local check_label
    if [ "$i" -eq 1 ]; then
      check_label="merge-in-1-day-without-review"
    else
      check_label="merge-in-${i}-days-without-review"
    fi
    
    if echo "$labels" | grep -q "$check_label"; then
      echo "$i"
      return
    fi
  done
  
  echo "0"  # No countdown label found
}

# Build label filter - only PRs with countdown labels
LABEL_FILTER=""
for lbl in "${COUNTDOWN_LABELS[@]}"; do
  if [ "$lbl" == "$FINAL_LABEL" ]; then
    continue  # Skip merged-without-review - those are done
  fi
  if [ -n "$LABEL_FILTER" ]; then
    LABEL_FILTER="${LABEL_FILTER},"
  fi
  LABEL_FILTER="${LABEL_FILTER}${lbl}"
done

echo "Fetching open PRs with countdown labels..."
echo "  Label filter: $LABEL_FILTER"

# Fetch PRs with countdown labels
prs=$(gh pr list --repo "$REPO" --state open --label "$START_LABEL" --json number,title,author,labels,isDraft 2>/dev/null || echo "[]")

# Also fetch PRs with other countdown labels
for ((i=DAYS-1; i>=1; i--)); do
  check_label=""
  if [ "$i" -eq 1 ]; then
    check_label="merge-in-1-day-without-review"
  else
    check_label="merge-in-${i}-days-without-review"
  fi
  more_prs=$(gh pr list --repo "$REPO" --state open --label "$check_label" --json number,title,author,labels,isDraft 2>/dev/null || echo "[]")
  # Merge arrays (dedup by number)
  prs=$(echo "$prs $more_prs" | jq -s 'add | unique_by(.number)')
done

if [ "$(echo "$prs" | jq 'length')" -eq 0 ]; then
  echo ""
  echo "No open PRs with countdown labels found."
  echo "To opt-in a PR for auto-merge, add label: $START_LABEL"
  exit 0
fi

echo ""
echo "Found $(echo "$prs" | jq 'length') PR(s) with countdown labels."
echo ""

# Process each PR
echo "$prs" | jq -c '.[]' | while IFS= read -r pr; do
  PR_NUMBER=$(echo "$pr" | jq -r '.number')
  TITLE=$(echo "$pr" | jq -r '.title')
  AUTHOR=$(echo "$pr" | jq -r '.author.login')
  IS_DRAFT=$(echo "$pr" | jq -r '.isDraft')
  PR_LABELS=$(echo "$pr" | jq -r '[.labels[].name] | join(",")')

  echo "────────────────────────────────────────"
  echo "PR #${PR_NUMBER}: ${TITLE}"
  echo "  Author: ${AUTHOR}"
  echo "  Draft: ${IS_DRAFT}"
  echo "  Labels: ${PR_LABELS}"

  # Skip drafts if configured
  if [ "$SKIP_DRAFTS" == "true" ] && [ "$IS_DRAFT" == "true" ]; then
    echo "  Status: Draft PR — skipping"
    continue
  fi

  # Skip if PR already has an approving review
  APPROVALS=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" \
    --jq '[.[] | select(.state == "APPROVED")] | length' 2>/dev/null || echo "0")
  
  if [ "$APPROVALS" -gt 0 ]; then
    echo "  Status: Already approved — removing countdown labels"
    remove_countdown_labels "$PR_NUMBER"
    continue
  fi

  # Check CI status
  echo "  Checking CI status..."
  if ! check_ci_status "$PR_NUMBER"; then
    echo "  Status: CI not green — PAUSED (countdown frozen)"
    add_comment "$PR_NUMBER" "⏸️ **Auto-merge countdown PAUSED**: CI checks are not passing. The countdown will resume when all checks are green." "Auto-merge countdown PAUSED"
    continue
  fi
  echo "  CI: ✓ Green"

  # Get current position in countdown
  CURRENT_POS=$(get_countdown_position "$PR_LABELS")
  echo "  Countdown position: ${CURRENT_POS} days remaining"

  # Remove existing countdown labels before adding new one
  remove_countdown_labels "$PR_NUMBER"

  # Advance countdown or approve
  if [ "$CURRENT_POS" -le 1 ]; then
    # Time to approve!
    echo "  Action: AUTO-APPROVE"
    add_comment "$PR_NUMBER" "✅ **Auto-approved**: No review received within ${DAYS} days. Merging now."
    add_label "$PR_NUMBER" "$FINAL_LABEL"
    approve_pr "$PR_NUMBER" "Auto-approved: no review received within ${DAYS} days of opening."
    merge_pr "$PR_NUMBER"
  else
    # Advance to next day
    NEXT_POS=$((CURRENT_POS - 1))
    if [ "$NEXT_POS" -eq 1 ]; then
      NEXT_LABEL="merge-in-1-day-without-review"
      EMOJI="⚠️"
    else
      NEXT_LABEL="merge-in-${NEXT_POS}-days-without-review"
      EMOJI="⏳"
    fi

    echo "  Action: Advance → ${NEXT_LABEL}"
    add_label "$PR_NUMBER" "$NEXT_LABEL"
    add_comment "$PR_NUMBER" "${EMOJI} **Auto-merge countdown**: This PR will be auto-approved in **${NEXT_POS} day(s)** if no review is submitted."
  fi
done

echo ""
echo "════════════════════════════════════════"
echo "Done."
