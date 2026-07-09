#!/usr/bin/env bash
#
# SETUP — this is a template Claude Code status line. To install it:
#
#   1. cp -n <toolkit>/setup/claude-code/statusline-command.example.sh \
#           ~/.claude/statusline-command.sh
#   2. chmod +x ~/.claude/statusline-command.sh
#   3. Add this block to ~/.claude/settings.json (merge, do not clobber):
#
#        "statusLine": {
#          "type": "command",
#          "command": "~/.claude/statusline-command.sh"
#        }
#
#   Requires: jq, and a terminal with UTF-8 + box-drawing glyphs (the ⟳ reset
#   marker renders best in a Nerd Font). Nothing else — no network, no state
#   beyond one tiny TTL cache file in /tmp.
#
#   Delete this SETUP block from the live copy once installed.
# -----------------------------------------------------------------------------
#
# Claude Code status line — Claude.ai subscription build.
#
# Everything shown comes straight from the JSON Claude Code puts on stdin, so
# the numbers match the built-in footer and `/context` exactly. In particular:
#   - context uses the exact token count (context_window.total_input_tokens),
#     never a lossy percentage-times-size estimate;
#   - cost uses the native client-side figure (cost.total_cost_usd), never a
#     transcript re-parse against hardcoded pricing;
#   - the plan badge is read from Claude Code's own account record and the
#     subscription's rate-limit windows are surfaced, because on a plan those
#     matter more than a per-token dollar estimate.
#
# Performance: the render path is pure bash plus one jq over the (small) stdin
# payload. The account file is parsed at most once every few minutes behind a
# TTL cache, so a busy session does not re-scan it on every message.
#
# Field schema: https://code.claude.com/docs/en/statusline

set -u

input=$(cat)

# --- ANSI colors (literal escapes) ---
RST=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
WHITE=$'\033[97m'
GRAY=$'\033[90m'
ORANGE=$'\033[1;38;2;255;140;0m'

NOW=$(date +%s)

# --- Fields we render, declared up front so nothing is ever unset ---
# (Explicit declaration also lets the linter see through the eval below.)
model="Claude"
used_pct=""
used_tokens=""
context_size=""
cost_usd=""
rl_5h=""
rl_5h_reset=""
rl_7d=""
effort=""

# One jq pass over stdin. @sh quotes every value, so the eval is injection-safe.
# Absent fields (rate_limits before the first API response, effort on a model
# without the parameter) come back empty, and each row guards on that.
eval "$(echo "$input" | jq -r '
  "model="        + (.model.display_name // "Claude"                    | @sh) + " " +
  "used_pct="     + (.context_window.used_percentage // ""    | tostring | @sh) + " " +
  "used_tokens="  + (.context_window.total_input_tokens // ""  | tostring | @sh) + " " +
  "context_size=" + (.context_window.context_window_size // "" | tostring | @sh) + " " +
  "cost_usd="     + (.cost.total_cost_usd // ""               | tostring | @sh) + " " +
  "rl_5h="        + (.rate_limits.five_hour.used_percentage // ""  | tostring | @sh) + " " +
  "rl_5h_reset="  + (.rate_limits.five_hour.resets_at // ""        | tostring | @sh) + " " +
  "rl_7d="        + (.rate_limits.seven_day.used_percentage // "" | tostring | @sh) + " " +
  "effort="       + (.effort.level // ""                             | @sh)
' 2>/dev/null)" 2>/dev/null

: "${model:=Claude}"

# --- Helpers (pure bash, no subprocess in the render path; each sets a global) ---

# Threshold color: green calm, yellow watch, red act. Sets _c.
_pct_color() {
    if [ "$1" -ge 80 ]; then
        _c="$RED"
    elif [ "$1" -ge 50 ]; then
        _c="$YELLOW"
    else _c="$GREEN"; fi
}

# Fixed-width usage bar. Sets _bar.
_build_bar() {
    local pct="$1" width="${2:-12}" color="$3" filled i
    filled=$((pct * width / 100))
    _bar="${DIM}[${RST}${color}"
    for ((i = 0; i < filled; i++)); do _bar+="█"; done
    _bar+="${GRAY}"
    for ((i = filled; i < width; i++)); do _bar+="░"; done
    _bar+="${DIM}]${RST}"
}

# Token count in Claude's own style: 639600 -> "639.6k", 1000000 -> "1M". Sets _fmt.
_format_tokens() {
    local n="$1" h
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        _fmt="$n"
        return
    fi
    if [ "$n" -ge 1000000 ]; then
        h=$((n / 100000)) # tenths of a million
        _fmt="$((h / 10)).$((h % 10))M"
    elif [ "$n" -ge 1000 ]; then
        h=$((n / 100)) # tenths of a thousand
        _fmt="$((h / 10)).$((h % 10))k"
    else
        _fmt="$n"
    fi
    _fmt="${_fmt/.0M/M}"
    _fmt="${_fmt/.0k/k}"
}

# Human countdown from a unix-epoch reset to NOW: "2h13m" / "9m" / "3d". Sets _time.
_time_until() {
    _time=""
    [ -z "$1" ] && return
    [[ "${1%.*}" =~ ^[0-9]+$ ]] || return
    local reset="${1%.*}" diff days hours mins
    diff=$((reset - NOW))
    if [ "$diff" -le 0 ]; then
        _time="now"
        return
    fi
    days=$((diff / 86400))
    if [ "$days" -ge 1 ]; then
        _time="${days}d"
        return
    fi
    hours=$((diff / 3600))
    mins=$(((diff % 3600) / 60))
    if [ "$hours" -gt 0 ]; then
        _time="${hours}h${mins}m"
    else _time="${mins}m"; fi
}

# Visible width, ignoring ANSI escapes, so box padding stays aligned. Sets _vlen.
_visible_len() {
    local s="$1" clean=""
    while [[ "$s" ]]; do
        if [[ "$s" == $'\033'* ]]; then
            s="${s#*m}"
        else
            clean+="${s:0:1}"
            s="${s:1}"
        fi
    done
    _vlen=${#clean}
}

# --- Effort styling. Levels differ by model: Opus 4.8/4.7, Sonnet 5, and Fable 5
# expose low/medium/high/xhigh/max; Opus 4.6 / Sonnet 4.6 top out at max (no
# xhigh); Sonnet 4.5 / Haiku 4.5 have no effort at all (field absent). The JSON
# reports the live value, so we colour the known ones and show any other
# non-empty value (e.g. "auto") verbatim rather than hiding it. "ultracode" is
# not a distinct level — it reports as xhigh — but is handled if it appears. ---
case "$effort" in
    max) effort_styled="${BOLD}${RED}max${RST}" ;;
    ultracode) effort_styled="${BOLD}${RED}ultracode${RST}" ;;
    xhigh) effort_styled="${BOLD}${MAGENTA}xhigh${RST}" ;;
    high) effort_styled="${ORANGE}high${RST}" ;;
    medium) effort_styled="${BOLD}${YELLOW}medium${RST}" ;;
    low) effort_styled="${BOLD}${GREEN}low${RST}" ;;
    auto) effort_styled="${BOLD}${CYAN}auto${RST}" ;;
    "") effort_styled="" ;;                             # model has no effort parameter
    *) effort_styled="${BOLD}${CYAN}${effort}${RST}" ;; # unknown/future level — show it, don't hide
esac

# --- Plan badge: the live subscription tier from Claude Code's own account
# record, so it reflects the active plan (Stripe subscription, not AWS/API)
# with no guessing and self-corrects on a plan change. Cached with a short TTL
# because the tier almost never changes but the account file churns constantly.
#
# The account file lives in the running instance's config dir: CLAUDE_CONFIG_DIR
# (set e.g. by a `claude1` alias for a second account) moves it under that dir,
# while the default instance keeps it at ~/.claude.json. Read the wrong one and
# a Max 5x session shows Max 20x — so resolve it per instance and key the cache
# to it, or two parallel instances would clobber each other's cached tier. ---
if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ -f "$CLAUDE_CONFIG_DIR/.claude.json" ]; then
    acct="$CLAUDE_CONFIG_DIR/.claude.json"
else
    acct="$HOME/.claude.json"
fi
tier_cache="/tmp/claude_statusline_tier_${UID}_${acct//\//_}"
status_text=""
if [ -f "$tier_cache" ]; then
    cache_mtime=$(stat -c %Y "$tier_cache" 2>/dev/null || echo 0)
    [ $((NOW - cache_mtime)) -lt 300 ] && IFS= read -r status_text <"$tier_cache"
fi
if [ -z "$status_text" ]; then
    tier=$(jq -r '.oauthAccount.organizationRateLimitTier
                  // .oauthAccount.userRateLimitTier // ""' "$acct" 2>/dev/null)
    case "$tier" in
        *max_20x*) status_text="Max 20x" ;;
        *max_5x*) status_text="Max 5x" ;;
        *pro*) status_text="Pro" ;;
        *free*) status_text="Free" ;;
        *team*) status_text="Team" ;;
        *enterprise*) status_text="Enterprise" ;;
        *) status_text="Claude" ;;
    esac
    printf '%s' "$status_text" >"$tier_cache" 2>/dev/null || true
fi

# --- Build each row's text first, so the card can be sized to fit them ---

# Context: prefer the exact token count; if that field is absent (older Claude
# Code) derive it from the percentage as a fallback so the count is never blank.
if [[ "$used_pct" =~ ^[0-9.]+$ ]] && [[ "$context_size" =~ ^[0-9]+$ ]]; then
    printf -v used_int '%.0f' "$used_pct" 2>/dev/null || used_int=0
    _pct_color "$used_int"
    ctx_pct_color="$_c"
    _build_bar "$used_int" 12 "$CYAN"
    ctx_bar="$_bar"
    [[ "$used_tokens" =~ ^[0-9]+$ ]] || used_tokens=$((used_int * context_size / 100))
    _format_tokens "$used_tokens"
    used_fmt="$_fmt"
    _format_tokens "$context_size"
    total_fmt="$_fmt"
    printf -v row_context " %s%-8s%s %s %s%3d%%%s  %s%s%s/%s%s" \
        "$CYAN$BOLD" "context" "$RST" "$ctx_bar" \
        "$ctx_pct_color" "$used_int" "$RST" \
        "$WHITE" "$used_fmt" "$GRAY" "$total_fmt" "$RST"
else
    printf -v row_context " %s%-8s%s  %s—%s" "$CYAN$BOLD" "context" "$RST" "$GRAY" "$RST"
fi

# Limits: Claude.ai subscribers only, and only after the first API response.
row_limits=""
if [ -n "$rl_5h" ] || [ -n "$rl_7d" ]; then
    seg=""
    if [ -n "$rl_5h" ]; then
        printf -v f5 '%.0f' "$rl_5h" 2>/dev/null || f5=0
        _pct_color "$f5"
        printf -v part '%s5h%s %s%2d%%%s' "$GRAY" "$RST" "$_c" "$f5" "$RST"
        seg+="$part"
        _time_until "$rl_5h_reset"
        [ -n "$_time" ] && {
            printf -v part ' %s⟳%s%s' "$DIM" "$_time" "$RST"
            seg+="$part"
        }
    fi
    if [ -n "$rl_7d" ]; then
        printf -v f7 '%.0f' "$rl_7d" 2>/dev/null || f7=0
        _pct_color "$f7"
        [ -n "$seg" ] && seg+="  ${DIM}·${RST}  "
        printf -v part '%s7d%s %s%2d%%%s' "$GRAY" "$RST" "$_c" "$f7" "$RST"
        seg+="$part"
    fi
    printf -v row_limits " %s%-8s%s %s" "$MAGENTA$BOLD" "limits" "$RST" "$seg"
fi

# Cost: native client-side figure. On a subscription it estimates equivalent
# API spend, not the actual bill — so it is labelled "est", honestly.
if [ -n "$cost_usd" ]; then
    printf -v cost_fmt '$%.2f' "$cost_usd" 2>/dev/null || cost_fmt="\$0.00"
else
    cost_fmt="\$0.00"
fi
printf -v row_cost " %s%-8s%s %s%s%s %sest%s" \
    "$GREEN$BOLD" "cost" "$RST" "$WHITE" "$cost_fmt" "$RST" "$DIM" "$RST"

# --- Size the card to the widest row (and the header) ---
rows=("$row_context" "$row_cost")
[ -n "$row_limits" ] && rows=("$row_context" "$row_limits" "$row_cost")

# Non-dash width of the header, exactly. The two layouts carry different fixed
# punctuation: with effort it is "␣model␣ … ␣effort␣·␣label␣" (7 fixed chars);
# without effort it is "␣model␣ … ␣label␣" (4 fixed chars). Get this wrong and
# the dash run over- or under-shoots the box border.
if [ -n "$effort_styled" ]; then
    header_extra=$((${#model} + ${#effort} + ${#status_text} + 7))
else
    header_extra=$((${#model} + ${#status_text} + 4))
fi

inner_w=$header_extra
for r in "${rows[@]}"; do
    _visible_len "$r"
    [ "$_vlen" -gt "$inner_w" ] && inner_w="$_vlen"
done
[ "$inner_w" -lt 44 ] && inner_w=44

# Dashes fill the header from the model name to the badges, so the top border
# ends level with the footer at inner_w.
header_fill=$((inner_w - header_extra))
[ "$header_fill" -lt 1 ] && header_fill=1
hdr_dashes=""
for ((i = 0; i < header_fill; i++)); do hdr_dashes+="─"; done
ftr_dashes=""
for ((i = 0; i < inner_w; i++)); do ftr_dashes+="─"; done

# One padded row inside the box borders.
_row() {
    _visible_len "$1"
    local pad=$((inner_w - _vlen))
    [ "$pad" -lt 0 ] && pad=0
    printf "%s│%s%s%*s%s│%s\n" "$DIM" "$RST" "$1" "$pad" "" "$DIM" "$RST"
}

# --- Render (header omits the effort badge when the model has no effort param) ---
if [ -n "$effort_styled" ]; then
    printf "%s┌%s %s%s%s %s%s%s %s %s·%s %s%s%s %s┐%s\n" \
        "$DIM" "$RST" "$BOLD$WHITE" "$model" "$RST" \
        "$DIM" "$hdr_dashes" "$RST" "$effort_styled" \
        "$DIM" "$RST" "$GREEN" "$status_text" "$RST" "$DIM" "$RST"
else
    printf "%s┌%s %s%s%s %s%s%s %s%s%s %s┐%s\n" \
        "$DIM" "$RST" "$BOLD$WHITE" "$model" "$RST" \
        "$DIM" "$hdr_dashes" "$RST" "$GREEN" "$status_text" "$RST" "$DIM" "$RST"
fi

_row "$row_context"
[ -n "$row_limits" ] && _row "$row_limits"
_row "$row_cost"

printf "%s└%s┘%s\n" "$DIM" "$ftr_dashes" "$RST"
