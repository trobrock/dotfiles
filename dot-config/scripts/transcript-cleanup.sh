#!/usr/bin/env bash

TRANSCRIPT=$(cat)
CLEANUP_INPUT=$(printf '%s' "$TRANSCRIPT" | perl -0pe 's/^.*\b(?:no actually|I mean)\b\s*//is')

SYSTEM_PROMPT='You clean dictation transcripts. Return JSON only: {"text":"..."}.'

USER_PROMPT=$(cat <<EOF
Rules:
- Remove filler words like "um", "uh", and "like".
- Remove stutters and unnecessary repetitions.
- For corrections, delete everything before the correction phrase and keep the corrected text. Correction phrases include "no actually", "actually", and "I mean".
- Preserve the original meaning and context.

Examples:
Input: Tuesday no actually Wednesday
Output: {"text":"Wednesday"}
Input: um I I need the like report
Output: {"text":"I need the report"}

Transcript:
$CLEANUP_INPUT
EOF
)

REQUEST=$(jq -n \
  --arg system "$SYSTEM_PROMPT" \
  --arg user "$USER_PROMPT" \
  '{model:"llama3.2:1b", stream:false, format:"json", options:{temperature:0}, messages:[{role:"system", content:$system}, {role:"user", content:$user}]}')
RESPONSE=$(curl -fsS -H 'Content-Type: application/json' http://127.0.0.1:11434/api/chat -d "$REQUEST") || exit $?
CLEANED_TRANSCRIPT=$(printf '%s' "$RESPONSE" | jq -r '.message.content | fromjson? | .text // empty')

if [ -n "$CLEANED_TRANSCRIPT" ]; then
  printf '%s' "$CLEANED_TRANSCRIPT"
else
  printf '%s' "$TRANSCRIPT"
fi
