#!/usr/bin/env bash

TRANSCRIPT=$(cat)

CLEANED_TRANSCRIPT=$(ollama run llama3.2:1b \
  --system "You are a helpful assistant that cleans up transcripts by removing filler words, stutters, unnecessary repetitions, and self-corrections while preserving the original meaning and context. When the speaker corrects themselves (e.g., 'Tuesday. No, actually, I mean Wednesday'), keep only the correction ('Wednesday')." \
  --prompt "Clean up the following transcript by:
1. Removing filler words (like 'um', 'uh', 'like')
2. Removing stutters and unnecessary repetitions
3. Handling self-corrections - when the speaker says something then corrects themselves (e.g., 'Tuesday, no actually Wednesday' or 'I mean Wednesday'), keep only the final corrected version
4. Preserve the original meaning and context

Transcript:
$TRANSCRIPT") || exit $?

# Keep type mode, but also make the final text available if focus was wrong.
# Ignore clipboard failures so VoxType can still type/fallback normally.
if [[ -n "$CLEANED_TRANSCRIPT" ]] && command -v wl-copy >/dev/null 2>&1; then
  printf '%s' "$CLEANED_TRANSCRIPT" | wl-copy >/dev/null 2>&1 || true
fi

printf '%s' "$CLEANED_TRANSCRIPT"
