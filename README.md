# my-claude-statusline

My custom Claude Code statusline — shows usage quota with projected usage, context window, tokens, duration, and line changes in one line.

## What it looks like

```
[Opus] myproject | ██░░░░░░░░ 25% | S █▒▒░░░░░░░ 10% 3h6m→26% | W ██▒░░░░░░░ 20% 2d12h→31% | ⇡12.3k ⇣4.5k | 15.2s (API 8.3s) | +10 -3
```

- `S` / `W` — session (5h) and weekly (7d) usage with reset countdown and projected usage at reset
- `█▒░` — three-level bar: current (bright) → projected (dark) → empty (dim)
- Colors shift green → yellow → red as usage increases; projection turns red when exceeding 100%

## Setup

```bash
cp statusline-command.sh statusline-config.json ~/.claude/
chmod +x ~/.claude/statusline-command.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

## Config

`statusline-config.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `bar_round` | `true` | Round progress bar segments instead of truncating |
| `session_min_proj_elapsed` | `1800` | Minimum elapsed seconds for session projection (default: 30 min) |
| `weekly_min_proj_elapsed` | `86400` | Minimum elapsed seconds for weekly projection (default: 24 hrs) |

## Notes

- Requires `jq`; `git` is optional (branch name won't display without it)
- Usage quota (S/W bars) requires Claude Code >= 2.1.80 and Claude.ai Pro/Max subscription
