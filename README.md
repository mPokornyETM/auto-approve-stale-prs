# Auto-approve Stale PRs

A GitHub Action that auto-approves PRs after a configurable countdown. Uses an **opt-in model** where the PR author must manually start the countdown by adding a label.

## Features

- 🔐 **Opt-in model** — Author must manually add label to start countdown
- 🕐 **Configurable countdown** — Set any number of days (default: 3)
- 🚦 **Respects CI status** — Countdown pauses when checks are failing
- 🏷️ **Visual countdown labels** — Clear visibility into merge timeline
- 💬 **PR comments** — Notifies at each countdown stage
- 📝 **Dry-run mode** — Test without making changes

## How It Works

1. **Opt-in**: PR author adds `merge-in-3-days-without-review` label
2. **Daily run**: Workflow advances countdown (if CI is green)
3. **Auto-approve**: After countdown reaches 0, PR is approved and auto-merged

| Day | Label | Comment |
|-----|-------|---------|
| 0 (manual) | `merge-in-3-days-without-review` | Author adds label to opt-in |
| 1 | `merge-in-2-days-without-review` | ⏳ Auto-merge countdown: 2 days... |
| 2 | `merge-in-1-day-without-review` | ⚠️ Auto-merge countdown: 1 day... |
| 3 | `merged-without-review` | ✅ Auto-approved: Merging now. |

### CI Check

If CI checks are failing, the countdown **pauses**:
- No label change
- No comment posted
- Countdown resumes when CI turns green

## Usage

### Basic Setup

```yaml
# .github/workflows/auto-approve.yml
name: Auto-approve stale PRs

on:
  schedule:
    - cron: "0 8 * * *"  # Daily at 08:00 UTC
  workflow_dispatch:      # Manual trigger

permissions:
  contents: write
  pull-requests: write

jobs:
  auto-approve:
    runs-on: ubuntu-latest
    steps:
      - uses: mPokornyETM/auto-approve-stale-prs@v1
```

### With Options

```yaml
- uses: mPokornyETM/auto-approve-stale-prs@v1
  with:
    days-until-approve: '5'           # Wait 5 days instead of 3
    author-associations: 'OWNER,MEMBER,COLLABORATOR'
    merge-method: 'rebase'            # Use rebase instead of squash
    skip-drafts: 'true'               # Skip draft PRs (default)
    dry-run: 'false'                  # Set to 'true' to test
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `days-until-approve` | Days to wait before auto-approving | `3` |
| `author-associations` | Comma-separated list: OWNER, MEMBER, COLLABORATOR | `OWNER,MEMBER` |
| `merge-method` | Merge method: squash, merge, rebase | `squash` |
| `skip-drafts` | Skip draft PRs | `true` |
| `require-green-ci` | Pause countdown when CI checks are failing | `true` |
| `dry-run` | Log actions without making changes | `false` |
| `token` | GitHub token (needs PR write access) | `github.token` |

## Prerequisites

1. **Enable auto-merge** in repository settings:
   - Settings → General → Allow auto-merge ✓

2. **Branch protection** (recommended):
   - Require status checks to pass before merging
   - This ensures CI must pass even for auto-approved PRs

## Labels Created

The action automatically creates these labels (idempotent):

- 🟢 `merge-in-X-days-without-review` — Countdown in progress
- 🟡 `merge-in-2-days-without-review` — Getting closer
- 🔴 `merge-in-1-day-without-review` — Final warning
- 🟠 `merged-without-review` — Auto-approved

## Safety

- ✅ **Opt-in only** — PRs must have countdown label to be processed
- ✅ **CI must be green** — Countdown pauses when checks fail
- ✅ PRs with existing approvals are skipped
- ✅ Draft PRs are skipped by default
- ✅ Auto-merge respects branch protection rules

## License

MIT © [mPokornyETM](https://github.com/mPokornyETM)
