#!/bin/bash
# Process open PRs and apply countdown labels / auto-approve
set -euo pipefail

DAYS=${DAYS:-3}
ASSOCIATIONS=${ASSOCIATIONS:-"OWNER,MEMBER"}
MERGE_METHOD=${MERGE_METHOD:-"squash"}
DRY_RUN=${DRY_RUN:-"false"}
SKIP_DRAFTS=${SKIP_DRAFTS:-"true"}

# Convert comma-separated to array
IFS=',' read -ra ASSOC_ARRAY <<< "$ASSOCIATIONS"

# Build jq filter for author associations
ASSOC_FILTER=""
for assoc in "${ASSOC_ARRAY[@]}"; do
  assoc=$(echo "$assoc" | xargs)  # trim whitespace
  if [ -n "$ASSOC_FILTER" ]; then
    ASSOC_FILTER="$ASSOC_FILTER or"
  fi
  ASSOC_FILTER="$ASSOC_FILTER .author_association == \"$assoc\""
done

echo "Configuration:"
echo "  Days until approve: $DAYS"
echo "  Author associations: $ASSOCIATIONS"
echo "  Merge method: $MERGE_METHOD"
echo "  Dry run: $DRY_RUN"
echo "  Skip drafts: $SKIP_DRAFTS"
echo ""

# Generate all countdown label names for cleanup
COUNTDOWN_LABELS=("merged-without-review")
for ((i=DAYS; i>=1; i--)); do
  if [ "$i" -eq 1 ]; then
    COUNTDOWN_LABELS+=("merge-in-1-day-without-review")
  else
    COUNTDOWN_LABELS+=("merge-in-${i}-days-without-review")
  fi
done

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

add_comment() {
  local pr=$1
  local body=$2
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

# Build jq query for fetching PRs
JQ_QUERY=".[] | select($ASSOC_FILTER)"
if [ "$SKIP_DRAFTS" == "true" ]; then
  JQ_QUERY="$JQ_QUERY | select(.draft == false)"
fi
JQ_QUERY="$JQ_QUERY | {number: .number, created_at: .created_at, user: .user.login, author_association: .author_association, draft: .draft, title: .title}"

# Fetch open PRs
echo "Fetching open PRs..."
prs=$(gh api "repos/${REPO}/pulls?state=open&per_page=100" --jq "$JQ_QUERY" 2>/dev/null || echo "")

if [ -z "$prs" ]; then
  echo "No matching open PRs found."
  exit 0
fi

# Process each PR
echo "$prs" | jq -c '.' | while IFS= read -r pr; do
  PR_NUMBER=$(echo "$pr" | jq -r '.number')
  CREATED_AT=$(echo "$pr" | jq -r '.created_at')
  AUTHOR=$(echo "$pr" | jq -r '.user')
  ASSOC=$(echo "$pr" | jq -r '.author_association')
  TITLE=$(echo "$pr" | jq -r '.title')
  IS_DRAFT=$(echo "$pr" | jq -r '.draft')

  echo "────────────────────────────────────────"
  echo "PR #${PR_NUMBER}: ${TITLE}"
  echo "  Author: ${AUTHOR} (${ASSOC})"
  echo "  Draft: ${IS_DRAFT}"

  # Skip if PR already has an approving review
  APPROVALS=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" \
    --jq '[.[] | select(.state == "APPROVED")] | length' 2>/dev/null || echo "0")
  
  if [ "$APPROVALS" -gt 0 ]; then
    echo "  Status: Already approved — skipping"
    continue
  fi

  # Calculate age in whole days
  CREATED_TS=$(date -d "$CREATED_AT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CREATED_AT" +%s 2>/dev/null)
  NOW_TS=$(date +%s)
  AGE_DAYS=$(( (NOW_TS - CREATED_TS) / 86400 ))

  echo "  Age: ${AGE_DAYS} day(s)"

  # Remove existing countdown labels
  remove_countdown_labels "$PR_NUMBER"

  # Determine action based on age
  if [ "$AGE_DAYS" -ge "$DAYS" ]; then
    echo "  Action: AUTO-APPROVE"
    add_comment "$PR_NUMBER" "✅ **Auto-approved**: No review received within ${DAYS} days. Merging now."
    add_label "$PR_NUMBER" "merged-without-review"
    approve_pr "$PR_NUMBER" "Auto-approved: no review received within ${DAYS} days of opening."
    merge_pr "$PR_NUMBER"
  else
    REMAINING=$((DAYS - AGE_DAYS))
    if [ "$REMAINING" -eq 1 ]; then
      LABEL="merge-in-1-day-without-review"
      EMOJI="⚠️"
    elif [ "$REMAINING" -eq "$DAYS" ]; then
      LABEL="merge-in-${REMAINING}-days-without-review"
      EMOJI="📋"
    else
      LABEL="merge-in-${REMAINING}-days-without-review"
      EMOJI="⏳"
    fi

    echo "  Action: Label → ${LABEL}"
    add_label "$PR_NUMBER" "$LABEL"
    
    if [ "$REMAINING" -eq "$DAYS" ]; then
      add_comment "$PR_NUMBER" "${EMOJI} **Auto-merge countdown started**: This PR will be auto-approved in **${REMAINING} days** if no review is submitted."
    elif [ "$REMAINING" -eq 1 ]; then
      add_comment "$PR_NUMBER" "${EMOJI} **Auto-merge countdown**: This PR will be auto-approved in **1 day** if no review is submitted."
    else
      add_comment "$PR_NUMBER" "${EMOJI} **Auto-merge countdown**: This PR will be auto-approved in **${REMAINING} days** if no review is submitted."
    fi
  fi
done

echo ""
echo "════════════════════════════════════════"
echo "Done."
