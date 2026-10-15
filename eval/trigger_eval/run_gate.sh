#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT
#
# Trigger-eval gate runner. Drives the eval_set.json queries
# against a RUNNING MCP surface (the `mix ash_agent.serve` daemon, or the
# ash_ai router mounting AshAgentTools.AshAi): fetches the real
# `tools/list` cards, then asks a real client model (`opencode run`) which
# tool — if any — it would call for each query. Scores per the gate rules
# in README.md and labels failures with the phxagents taxonomy.
#
# Usage:
#   mix ash_agent.serve --port 4199        # in the target project, first
#   eval/trigger_eval/run_gate.sh [--port 4199 | --url URL] \
#       [--model provider/id] [--runs N] [--out results.md]
#
#   --url takes a full endpoint, e.g. http://localhost:4000/ash_agent/mcp
#   for the ash_ai-mounted surface. --port N is shorthand for
#   http://127.0.0.1:N (the daemon). ash_ai wraps tool arguments in an
#   "input" object; the cards are rendered from inside it.
#
# Scoring (README.md "Gate"):
#   should-trigger row  -> pass iff the model picks `expected_tool` (or a
#                          tool the row lists in `also_accept`);
#                          else `missing_term` (picked none) or
#                          `neighbor_collision` (picked another daemon tool).
#   should-not row      -> pass iff the model picks no daemon tool
#                          (the row's `neighbor` surface answers);
#                          a daemon pick is a `too_broad` hit charged to
#                          the picked tool.
#   per-tool rate       = targeted_passes / (targeted + too_broad hits);
#                          gate: >= 0.75 for every tool with rows.

set -euo pipefail

PORT=4199
URL=""
MODEL=""
RUNS=1
OUT=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_SET="$SCRIPT_DIR/eval_set.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

BASE="${URL:-http://127.0.0.1:$PORT}"
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }
command -v opencode >/dev/null || { echo "opencode required (the judge client)" >&2; exit 1; }

# --- 1. Handshake with the real server -------------------------------------
# The daemon is stateless; ash_ai's router hands out an mcp-session-id on
# initialize, which later requests echo back.
HEADERS_FILE="$(mktemp)"
trap 'rm -f "$HEADERS_FILE"' EXIT
post() {
  local session=()
  [[ -n "${SESSION:-}" ]] && session=(-H "mcp-session-id: $SESSION")
  curl -sf -m 10 -X POST "$BASE" -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' "${session[@]}" "$@"
}
SESSION=""
post -D "$HEADERS_FILE" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"trigger-gate","version":"1.0"}}}' >/dev/null \
  || { echo "MCP server not reachable on $BASE — boot it first (e.g. mix ash_agent.serve --port $PORT)" >&2; exit 1; }
SESSION="$(grep -i '^mcp-session-id:' "$HEADERS_FILE" | head -1 | cut -d' ' -f2 | tr -d '\r' || true)"
post -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null || true

CARDS_JSON="$(post -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
TOOL_NAMES="$(jq -r '.result.tools[].name' <<<"$CARDS_JSON")"

# --- 2. Render the cards the way a client sees them -------------------------
CARDS_TEXT="$(jq -r '
  .result.tools[] |
  "### " + .name + "\n" + .description + "\nArguments:\n" +
  (.inputSchema.properties.input.properties // .inputSchema.properties) as $props |
  (if $props == {} then "  (none)" else
    [$props | to_entries[] |
      "  - " + .key + " (" + (.value.type // "any" | tostring) + ")" +
      (if .value.description then ": " + .value.description else "" end)]
    | join("\n") end)
' <<<"$CARDS_JSON")"

judge() {
  local query="$1"
  local prompt picked
  prompt="You are an AI coding agent working in an Elixir/Phoenix project that uses the Ash framework. You have these MCP tools connected:

$CARDS_TEXT

The user says: \"$query\"

Decide: to handle this request, would you call one of these tools right now? If yes, which one?
Respond with EXACTLY one line and nothing else:
PICK: <tool-name>
or, if none of these tools fit the request:
PICK: none (<one short clause naming what you would use instead>)"
  # </dev/null: opencode would otherwise consume the caller loop's stdin
  # (the here-string / process-substitution feeding the query loops).
  if [[ -n "$MODEL" ]]; then
    raw="$(opencode run --model "$MODEL" "$prompt" </dev/null 2>/dev/null)"
  else
    raw="$(opencode run "$prompt" </dev/null 2>/dev/null)"
  fi
  # Take the LAST "PICK:" line, collapse all whitespace to single spaces,
  # so a chatty model can never inject tabs/newlines into the TSV below.
  pick="$(grep -o 'PICK:.*' <<<"$raw" | tail -1 | tr -s '[:space:]' ' ' | sed 's/[[:space:]]*$//')"
  pick="${pick#PICK: }"
  pick="${pick#PICK:}"
  pick="${pick# }"
  printf '%s' "${pick:-none (judge produced no parseable PICK line)}"
  printf '\n'
}

# --- 3. Drive every query ----------------------------------------------------
RESULTS="$(jq -c '.queries[]' "$EVAL_SET")"
declare -A TARGETED=( ) TPASS=( ) TOOBROAD=( )
declare -a ROWS=()

run_one() {
  local q_json="$1" r
  local query should exp neighbor also
  query="$(jq -r '.query' <<<"$q_json")"
  should="$(jq -r '.should_trigger' <<<"$q_json")"
  exp="$(jq -r '.expected_tool // ""' <<<"$q_json")"
  neighbor="$(jq -r '.neighbor // ""' <<<"$q_json")"
  also="$(jq -r '(.also_accept // []) | join(",")' <<<"$q_json")"
  for _ in $(seq 1 "$RUNS"); do
    r="$(judge "$query")"
    [[ -n "$r" ]] || r="none (judge produced no parseable answer)"
    printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' "$query" "$should" "$exp" "$r" "$also" "$neighbor"
  done
}

while IFS= read -r q_json; do
  while IFS=$'\x1f' read -r query should exp picked also neighbor; do
    [[ -z "${query:-}" ]] && continue
    [[ -n "$picked" ]] || picked="none (empty pick)"
    row_status=PASS row_label="-"
    if [[ "$should" == "true" ]]; then
      TARGETED["$exp"]=$(( ${TARGETED["$exp"]:-0} + 1 ))
      if [[ "$picked" == "$exp" || ",$also," == *",$picked,"* ]]; then
        TPASS["$exp"]=$(( ${TPASS["$exp"]:-0} + 1 ))
      elif [[ "$picked" == none* ]]; then
        row_status=FAIL; row_label="missing_term"
      else
        row_status=FAIL; row_label="neighbor_collision(->$picked)"
      fi
    else
      if [[ "$picked" == none* ]]; then
        row_label="ok: $picked [expected neighbor: $neighbor]"
      else
        row_status=FAIL; row_label="too_broad($picked)"
        TOOBROAD["$picked"]=$(( ${TOOBROAD["$picked"]:-0} + 1 ))
      fi
    fi
    ROWS+=("$query	$should	$exp	$picked	$row_status	$row_label")
  done < <(run_one "$q_json")
done <<<"$RESULTS"

# --- 4. Score + report --------------------------------------------------------
report() {
  echo "| tool | rate | passes/targeted | too_broad | gate (>=0.75) |"
  echo "|---|---|---|---|---|"
  for t in $TOOL_NAMES; do
    tgot="${TARGETED[$t]:-0}"; tpass="${TPASS[$t]:-0}"; tb="${TOOBROAD[$t]:-0}"
    denom=$(( tgot + tb ))
    if [[ "$denom" -eq 0 ]]; then
      echo "| $t | n/a | 0/0 | $tb | no rows |"
    else
      rate=$(awk -v p="$tpass" -v d="$denom" 'BEGIN{printf "%.2f", p/d}')
      verdict=$([[ $(awk -v p="$tpass" -v d="$denom" 'BEGIN{print (p/d >= 0.75) ? 1 : 0}') == 1 ]] && echo "PASS" || echo "FAIL")
      echo "| $t | $rate | $tpass/$denom | $tb | $verdict |"
    fi
  done
  echo
  echo "| query | should | expected | picked | result | label |"
  echo "|---|---|---|---|---|---|"
  for row in "${ROWS[@]}"; do
    echo "| $(echo "$row" | sed 's/|/\\|/g; s/\t/ | /g') |"
  done
}

if [[ -n "$OUT" ]]; then
  report >"$OUT"
  echo "results written to $OUT"
fi
report
