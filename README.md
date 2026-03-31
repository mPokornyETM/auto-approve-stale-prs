# Auto-approve Stale PRs

A GitHub Action that auto-approves PRs from repository owners/members after a configurable number of days without review. Eliminates wasted time waiting for reviews that never come.

## Features

- 🕐 **Configurable countdown** — Set any number of days (default: 3)
- 🏷️ **Visual countdown labels** — Clear visibility into merge timeline
- 💬 **PR comments** — Notifies when countdown starts and at each stage
- 🔒 **Safety guards** — Only processes OWNER/MEMBER PRs, skips already-approved PRs
- 📝 **Dry-run mode** — Test without making changes
- ⚙️ **Flexible merge methods** — Supports squash, merge, or rebase

## How It Works

| Day | Label | Comment |
|-----|-------|---------|
| 0 | `merge-in-3-days-without-review` | 📋 Auto-merge countdown started... |
| 1 | `merge-in-2-days-without-review` | ⏳ Auto-merge countdown: 2 days... |
| 2 | `merge-in-1-day-without-review` | ⚠️ Auto-merge countdown: 1 day... |
| 3 | `merged-without-review` | ✅ Auto-approved: Merging now. |

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

- ✅ Only PRs from OWNER/MEMBER are processed
- ✅ External contributor PRs are **never** touched
- ✅ PRs with existing approvals are skipped
- ✅ Draft PRs are skipped by default
- ✅ CI must still pass (auto-merge respects branch protection)

## License

MIT © [mPokornyETM](https://github.com/mPokornyETM)
