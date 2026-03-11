# my-claude-statusline

My custom Claude Code statusline — shows usage quota with projected usage, context window, tokens, duration, and line changes in one line.

## What it looks like

```
[Opus] myproject | ██░░░░░░░░ 25% | S █▒▒░░░░░░░ 10% 3h6m→26% | W ██▒░░░░░░░ 20% 2d12h→31% | IN 12.3k OUT 4.5k | 15.2s (API 8.3s) | +10 -3
```

- `S` / `W` — session (5h) and weekly (7d) usage with reset countdown and projected usage at reset
- `█▒░` — three-level bar: current (bright) → projected (dark) → empty (dim)
- Colors shift green → yellow → red as usage increases; projection turns red when exceeding 100%
- Stale cache (>10min) dims the usage bars and shows `(Xh ago)`

## Setup

```bash
cp statusline-command.sh usage-fetch.sh usage-config.json ~/.claude/
chmod +x ~/.claude/statusline-command.sh ~/.claude/usage-fetch.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusline": {
    "command": "~/.claude/statusline-command.sh"
  }
}
```

## Config

`usage-config.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `cache_ttl` | `120` | Cache refresh interval (seconds) |
| `usage_api_url` | `https://api.anthropic.com/api/oauth/usage` | API endpoint |

## Notes

- macOS only (reads OAuth token from Keychain)
- Requires `jq` and `curl`
- Cache is shared across Claude Code instances with atomic locking
