# VoxType wake-word daemon

VoxType itself is push-to-talk only — upstream rejects always-on mode by
design. `dot-config/scripts/voxtype-vad` is a small Python daemon that wraps
VoxType with a wake word: it listens continuously on the default PipeWire
source, fires when it hears the configured phrase, and drives
`voxtype record start|stop` so the following utterance gets transcribed.

Opt-in. Toggle with `SUPER+SHIFT+V` (Hyprland) or
`systemctl --user start|stop voxtype-vad`. Status: `● VAD` (green) in Waybar
while armed; hidden when off.

## Stock wake words

`openWakeWord` ships four wake-word models and two intent-style models.
Only the first four are useful as dictation triggers.

| Name           | Kind       | Notes                                      |
| -------------- | ---------- | ------------------------------------------ |
| `hey_jarvis`   | wake word  | Default. Distinct phonemes, low FPR.       |
| `hey_mycroft`  | wake word  |                                            |
| `hey_rhasspy`  | wake word  |                                            |
| `alexa`        | wake word  | Collides with real Alexa devices.          |
| `timer`        | intent     | Fires on any timer-related speech.         |
| `weather`      | intent     | Fires on any weather-related speech.       |

### Switching stock models

Edit `dot-config/scripts/voxtype-vad`:

```python
WAKE_WORD = "hey_mycroft"
WAKE_MODEL_BASENAME = "hey_mycroft_v0.1.onnx"
```

Then `systemctl --user restart voxtype-vad`. First run downloads the new
model into `~/.cache/voxtype-vad/openwakeword/`.

## Training a custom wake word

"Hey Jarvis" is fine but long. All stock models use the `hey_<something>`
pattern, so anything shorter (e.g. `computer`, `dictate`) means training
your own.

Upstream offers two paths:

### Easy: Colab notebook

<https://colab.research.google.com/drive/1q1oe2zOyZp7UsB3jJiQ1IFn8z5YfjwEb>

1. Runtime → Change runtime type → **T4 GPU** (free tier).
2. Enter the wake phrase as a plain lowercase string (e.g. `computer`).
3. Runtime → Run all. Takes roughly 30–60 min. Synthetic TTS generates
   thousands of positive examples across voices/accents; negatives come
   bundled.
4. Final cell produces `.tflite` and `.onnx` files. Download the `.onnx`.

Upstream caveat, copied verbatim: *"the performance of the model may be
low in some deployment scenarios."* Expect more false triggers and misses
than the stock models. Usually tolerable; occasionally not.

### Advanced: full notebook

`notebooks/automatic_model_training.ipynb` in
<https://github.com/dscripka/openWakeWord>. More TTS variety, negative
dataset control, longer training. Higher quality, more setup.

### Installing the trained model

```bash
cp ~/Downloads/computer.onnx ~/.cache/voxtype-vad/openwakeword/
```

Edit `dot-config/scripts/voxtype-vad`:

```python
WAKE_WORD = "computer"
WAKE_MODEL_BASENAME = "computer.onnx"
```

Restart: `systemctl --user restart voxtype-vad`.

## Choosing a phrase

- **3+ syllables** works far more reliably than 1–2. Less phonetic material
  means more false triggers and more missed wakes.
- **Avoid words you'll dictate.** If you dictate PR descriptions that
  mention "Claude", don't use "hey Claude" as your wake word.
- **Say-ability when tired or quiet** matters more than cleverness. You'll
  say this dozens of times a day.

## Tuning

If the wake word misses too often, lower `WAKE_THRESHOLD` in the daemon
(default `0.5`; try `0.4`). If it false-triggers during conversation,
raise it (try `0.6`–`0.7`).

`SILENCE_HANGOVER_MS` (default `1500`) controls how long the daemon waits
in silence before calling `voxtype record stop`. Lower if dictation ends
feel sluggish; raise if it cuts off during mid-sentence pauses.

`SPEECH_THRESHOLD` (default `0.5`) is the silero-VAD probability above
which a frame counts as speech for the end-of-utterance detector —
separate from wake detection.

## Watching what it's doing

```bash
journalctl --user -u voxtype-vad -f
```

Triggers log a line with the score:

```
wake word triggered (score=0.872) -> voxtype record start
silence -> voxtype record stop
```

## How it fits together

1. `pw-cat` reads 16kHz mono PCM from the default PipeWire source into the
   daemon's stdin. PipeWire's multi-consumer sources mean this doesn't
   conflict with VoxType's own capture.
2. openWakeWord runs on 80ms frames; silero-VAD (used only for
   end-of-utterance detection) runs on 32ms frames.
3. When the wake score crosses `WAKE_THRESHOLD`, the daemon calls
   `voxtype record start`. VoxType captures independently from that moment,
   so the wake word itself is not transcribed — dictation starts clean.
4. While recording, wake detection pauses. The silero state machine stops
   VoxType after `SILENCE_HANGOVER_MS` of trailing silence.

## Dependencies

Declared in `Archfile`:

- `python-openwakeword` (AUR) — the PKGBUILD at 0.6.0 is missing
  `python-scikit-learn` as a dep, so that's listed explicitly too.
- `python-onnxruntime-cpu`
- `python-numpy`
- `python-scikit-learn`
- `pipewire` (for `pw-cat`; already present).

The silero-VAD ONNX model is fetched to `~/.cache/voxtype-vad/` on first
run; openWakeWord feature + wake models land in
`~/.cache/voxtype-vad/openwakeword/`. Nothing is committed — models live
outside the repo.
