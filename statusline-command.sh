#!/bin/bash
input=$(cat)

# Config
CONF="$HOME/.claude/statusline-config.json"
BAR_ROUND=5
if [ -f "$CONF" ]; then
  jq -e '.bar_round == false' "$CONF" >/dev/null 2>&1 && BAR_ROUND=0
  SESSION_MIN_PROJ_ELAPSED=$(jq -r '.session_min_proj_elapsed // 1800' "$CONF" 2>/dev/null || echo 1800)
  WEEKLY_MIN_PROJ_ELAPSED=$(jq -r '.weekly_min_proj_elapsed // 86400' "$CONF" 2>/dev/null || echo 86400)
else
  SESSION_MIN_PROJ_ELAPSED=1800
  WEEKLY_MIN_PROJ_ELAPSED=86400
fi

MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Tokens
IN_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
OUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')

# Durations
TOTAL_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
API_MS=$(echo "$input" | jq -r '.cost.total_api_duration_ms // empty')

# Lines changed
ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')

# Usage quota (from native rate_limits)
NOW=$(date +%s)
SESSION_PCT=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
WEEKLY_PCT=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)
S_RESET_AT=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' | cut -d. -f1)
W_RESET_AT=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' | cut -d. -f1)
S_RESET_SECS=""; [ -n "$S_RESET_AT" ] && { s=$((S_RESET_AT - NOW)); [ "$s" -lt 0 ] && s=0; S_RESET_SECS=$s; }
W_RESET_SECS=""; [ -n "$W_RESET_AT" ] && { s=$((W_RESET_AT - NOW)); [ "$s" -lt 0 ] && s=0; W_RESET_SECS=$s; }

# Colors
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; MAGENTA='\033[35m'; DIM='\033[2m'; RESET='\033[0m'
DGREEN='\033[38;5;22m'; DYELLOW='\033[38;5;94m'; DRED='\033[38;5;52m'

# Context bar color
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

# Progress bar
FILLED=$(( (PCT + BAR_ROUND) / 10 )); EMPTY=$((10 - FILLED))
BAR_F=$(printf "%${FILLED}s" | tr ' ' '█')
BAR_E=$(printf "%${EMPTY}s" | tr ' ' '░')

# Format token count (e.g. 12345 -> 12.3k)
fmt_tokens() {
    n=$1
    [ -z "$n" ] && return
    if [ "$n" -ge 1000000 ]; then
        printf '%s.%sM' $((n / 1000000)) $(((n % 1000000) / 100000))
    elif [ "$n" -ge 1000 ]; then
        printf '%s.%sk' $((n / 1000)) $(((n % 1000) / 100))
    else
        printf '%s' "$n"
    fi
}

# Format ms to human-readable duration
fmt_sec() {
    ms=$1
    [ -z "$ms" ] && return
    local secs=$((ms / 1000))
    if [ "$secs" -ge 3600 ]; then
        printf '%dh%dm' $((secs / 3600)) $(((secs % 3600) / 60))
    elif [ "$secs" -ge 60 ]; then
        printf '%dm%ds' $((secs / 60)) $((secs % 60))
    else
        printf '%s.%ss' $((ms / 1000)) $(((ms % 1000) / 100))
    fi
}

# Build tokens segment
TOKENS=""
[ -n "$IN_TOKENS" ] && TOKENS="⇡$(fmt_tokens "$IN_TOKENS")"
[ -n "$OUT_TOKENS" ] && TOKENS="${TOKENS:+$TOKENS }⇣$(fmt_tokens "$OUT_TOKENS")"

# Build duration segment
DURATION=""
[ -n "$TOTAL_MS" ] && DURATION="$(fmt_sec "$TOTAL_MS")"
[ -n "$API_MS" ] && DURATION="$DURATION (API $(fmt_sec "$API_MS"))"

# Build lines segment
LINES=""
[ -n "$ADDED" ] && [ "$ADDED" != "0" ] && LINES="${GREEN}+${ADDED}${RESET}"
[ -n "$REMOVED" ] && [ "$REMOVED" != "0" ] && { [ -n "$LINES" ] && LINES="$LINES "; LINES="${LINES}${RED}-${REMOVED}${RESET}"; }

# Assemble single line
OUT="${CYAN}[${MODEL}]${RESET} ${DIR##*/}"
[ -n "$BRANCH" ] && OUT="$OUT ${DIM}(${RESET}${MAGENTA}${BRANCH}${RESET}${DIM})${RESET}"
OUT="$OUT ${DIM}|${RESET} ${BAR_COLOR}${BAR_F}${RESET}${BAR_COLOR}${DIM}${BAR_E}${RESET} ${PCT}%"

# Format seconds to human-readable remaining time
fmt_remaining() {
  local secs=$1
  [ -z "$secs" ] && return
  local d=$((secs / 86400))
  local h=$(((secs % 86400) / 3600))
  local m=$(((secs % 3600) / 60))
  if [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  else printf '%dm' "$m"
  fi
}

# Usage quota segment
usage_bar() {
  local v=$1 label=$2 reset_secs=$3 window=$4 min_proj_elapsed=$5
  local color dcolor
  if [ "$v" -ge 80 ] 2>/dev/null; then color="$RED"; dcolor="$DRED"
  elif [ "$v" -ge 50 ] 2>/dev/null; then color="$YELLOW"; dcolor="$DYELLOW"
  else color="$GREEN"; dcolor="$DGREEN"; fi
  local filled=$(( (v + BAR_ROUND) / 10 ))
  [ "$filled" -gt 10 ] && filled=10
  local proj="" proj_filled=0
  local suffix=""
  if [ -n "$reset_secs" ] && [ -n "$window" ]; then
    local elapsed=$((window - reset_secs))
    local eff_elapsed=$elapsed
    [ "$eff_elapsed" -lt "$min_proj_elapsed" ] && eff_elapsed=$min_proj_elapsed
    if [ "$elapsed" -gt 300 ] && [ "$v" -gt 0 ]; then
      proj=$((v * window / eff_elapsed))
      proj_filled=$(( (proj + BAR_ROUND) / 10 ))
      [ "$proj_filled" -gt 10 ] && proj_filled=10
    fi
    suffix=" ${DIM}$(fmt_remaining "$reset_secs")"
    if [ -n "$proj" ]; then
      if [ "$proj" -gt 100 ]; then
        dcolor="$DRED"
        suffix="${suffix}${RESET}${RED}→${proj}%${RESET}${DIM}"
      else
        suffix="${suffix}→${proj}%"
      fi
    fi
    suffix="${suffix}${RESET}"
  fi
  # Bar: █ current | ▒ projected | ░ empty
  local proj_extra=0
  [ "$proj_filled" -gt "$filled" ] && proj_extra=$((proj_filled - filled))
  local empty=$((10 - filled - proj_extra))
  local bar_f=$(printf "%${filled}s" | tr ' ' '█')
  local bar_p=$(printf "%${proj_extra}s" | tr ' ' '▒')
  local bar_e=$(printf "%${empty}s" | tr ' ' '░')
  printf '%b' "${label} ${color}${bar_f}${RESET}${dcolor}${bar_p}${RESET}${color}${DIM}${bar_e}${RESET} ${v}%${suffix}"
}
[ -n "$SESSION_PCT" ] && OUT="$OUT ${DIM}|${RESET} $(usage_bar "$SESSION_PCT" "S" "$S_RESET_SECS" 18000 "$SESSION_MIN_PROJ_ELAPSED")"
[ -n "$WEEKLY_PCT" ] && OUT="$OUT ${DIM}|${RESET} $(usage_bar "$WEEKLY_PCT" "W" "$W_RESET_SECS" 604800 "$WEEKLY_MIN_PROJ_ELAPSED")"

[ -n "$TOKENS" ] && OUT="$OUT ${DIM}|${RESET} ${TOKENS}"
[ -n "$DURATION" ] && OUT="$OUT ${DIM}|${RESET} ${DURATION}"
[ -n "$LINES" ] && OUT="$OUT ${DIM}|${RESET} ${LINES}"

printf '%b' "$OUT"