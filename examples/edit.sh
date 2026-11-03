#!/usr/bin/env bash
# Edit a clip with the Aisma REST API: upload, price, confirm, start, wait, download.
#
# Usage (needs curl and jq):
#   export AISMA_API_KEY=aisma_live_...
#   ./edit.sh clip.mp4 "change the background to a snowy forest" [720p|1080p]
#
# Nothing is charged until you answer "y" to the price question.
set -euo pipefail

FILE="${1:?usage: edit.sh clip.mp4 \"what to change\" [720p|1080p]}"
BRIEF="${2:?usage: edit.sh clip.mp4 \"what to change\" [720p|1080p]}"
QUALITY="${3:-720p}"
API="https://api.aisma.ai/v1"
UA="aisma-example-curl/1.0"   # use your own app name
AUTH="Authorization: Bearer ${AISMA_API_KEY:?set AISMA_API_KEY}"

case "$FILE" in *.mov|*.MOV) TYPE="video/quicktime" ;; *) TYPE="video/mp4" ;; esac
BYTES=$(wc -c < "$FILE" | tr -d ' ')

api() { # api METHOD PATH [JSON] [extra header]; prints the JSON answer or the error and stops
  local out
  if ! out=$(curl -sS --fail-with-body -X "$1" "$API$2" -H "$AUTH" -H "User-Agent: $UA" \
      -H "Content-Type: application/json" ${4:+-H "$4"} ${3:+-d "$3"}); then
    echo "$1 $2 failed: $out" >&2
    exit 1
  fi
  printf '%s\n' "$out"
}

# 1. Ask for a one-time upload link, then PUT the file there with the headers it names.
UPLOAD=$(api POST /uploads "$(jq -nc --arg t "$TYPE" --argjson b "$BYTES" '{kind:"video",contentType:$t,bytes:$b}')")
ASSET=$(jq -r .assetId <<<"$UPLOAD")
URL=$(jq -r .uploadUrl <<<"$UPLOAD")
PUT_HEADERS=()
while IFS= read -r h; do PUT_HEADERS+=(-H "$h"); done < <(jq -r '.headers | to_entries[] | "\(.key): \(.value)"' <<<"$UPLOAD")
curl -sS --fail -X PUT "$URL" -H "Content-Type: $TYPE" -H "User-Agent: $UA" "${PUT_HEADERS[@]}" --data-binary @"$FILE" >/dev/null

# 2. Wait until Aisma has checked the clip.
while :; do
  STATUS=$(api GET "/assets/$ASSET" | jq -r .status)
  [ "$STATUS" = ready ] && break
  case "$STATUS" in failed|expired) echo "Upload $STATUS" >&2; exit 1 ;; esac
  sleep 3
done

# 3. Price the edit. Nothing is charged; a pending answer means "ask again after retryAfterMs".
while :; do
  QUOTE=$(api POST /quotes "$(jq -nc --arg s "$ASSET" --arg b "$BRIEF" --arg q "$QUALITY" '{sourceId:$s,brief:$b,quality:$q}')")
  WAIT=$(jq -r '.retryAfterMs // empty' <<<"$QUOTE")
  [ -z "$WAIT" ] && break
  sleep $(( (WAIT + 999) / 1000 ))
done

read -r -p "Start this edit for $(jq -r .credits <<<"$QUOTE") credits? [y/N] " ANSWER
[ "$ANSWER" = y ] || { echo "Not started. Nothing was charged."; exit 0; }

# 4. Start it. The Idempotency-Key makes a retry return the same edit.
QUOTE_ID=$(jq -r .id <<<"$QUOTE")
JOB=$(api POST /jobs "{\"quoteId\":\"$QUOTE_ID\"}" "Idempotency-Key: edit-$QUOTE_ID" | jq -r .jobId)
echo "Started edit $JOB"

# 5. Follow it (no more often than every 10 seconds), then fetch the one-hour link.
while :; do
  STATE=$(api GET "/jobs/$JOB")
  echo "  $(jq -r '"\(.stage) \(.progress)%"' <<<"$STATE")"
  [ "$(jq -r .resultReady <<<"$STATE")" = true ] && break
  [ "$(jq -r .status <<<"$STATE")" = failed ] && { echo "The edit failed: $(jq -c .issues <<<"$STATE")" >&2; exit 1; }
  sleep 10
done

OUT="${FILE%.*}-edited.mp4"
curl -sS --fail -A "$UA" -o "$OUT" "$(api POST "/jobs/$JOB/result" | jq -r .url)"
echo "Saved $OUT. The edit is also in your Aisma Library."
