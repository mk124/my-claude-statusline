#!/bin/bash
# Fetch and cache Claude usage quota data
# Outputs JSON: {"session":N,"weekly":N} or {} on failure
# Multi-instance safe with lock + atomic write

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG="$SCRIPT_DIR/usage-config.json"

CACHE="$HOME/.claude/usage-cache.json"
CACHE_TTL=$(jq -r '.cache_ttl // 120' "$CONFIG" 2>/dev/null || echo 120)
USAGE_API_URL=$(jq -r '.usage_api_url // "https://api.anthropic.com/api/oauth/usage"' "$CONFIG" 2>/dev/null || echo "https://api.anthropic.com/api/oauth/usage")
LOCK="$HOME/.claude/usage-cache.lock"

file_mtime() {
  stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0
}

needs_refresh() {
  [ ! -f "$CACHE" ] && return 0
  local mtime
  mtime=$(file_mtime "$CACHE")
  [ $(($(date +%s) - mtime)) -gt $CACHE_TTL ] && return 0
  return 1
}

refresh() {
  mkdir "$LOCK" 2>/dev/null || return
  (
    TOKEN=$(security find-generic-password -s "Claude Code-credentials" -a "$(whoami)" -w 2>/dev/null \
      | jq -r '.claudeAiOauth.accessToken // empty')
    if [ -n "$TOKEN" ]; then
      curl -s --max-time 5 \
        -H "Authorization: Bearer $TOKEN" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "User-Agent: claude-code/$(claude --version 2>/dev/null | awk '{print $1}' || echo 'unknown')" \
        "$USAGE_API_URL" > "$CACHE.tmp" \
        && jq -e '.five_hour and .seven_day' "$CACHE.tmp" >/dev/null 2>&1 \
        && mv "$CACHE.tmp" "$CACHE" \
        || rm -f "$CACHE.tmp"
    fi
    rmdir "$LOCK" 2>/dev/null
  ) &
}

needs_refresh && refresh

# Output parsed values as compact JSON
NOW=$(date +%s)
CACHE_MTIME=$(file_mtime "$CACHE")
CACHE_AGE=$((NOW - CACHE_MTIME))
jq -r --argjson now "$NOW" --argjson age "$CACHE_AGE" '
  def remaining($ts):
    ($ts | split(".")[0] + "Z" | fromdate) - $now | if . < 0 then 0 else . end;
  if .five_hour and .seven_day then
    { session:  (.five_hour.utilization | floor),
      weekly:   (.seven_day.utilization | floor),
      s_reset:  remaining(.five_hour.resets_at),
      w_reset:  remaining(.seven_day.resets_at),
      cache_age: $age }
  else {} end
' "$CACHE" 2>/dev/null || printf '{}'
