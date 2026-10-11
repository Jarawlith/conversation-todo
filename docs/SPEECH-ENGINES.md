# Local speech engines

Capture UI and `VoiceNative.cs` own the microphone and global hotkey. They produce mono 16 kHz signed 16-bit PCM. `speech-worker.js` owns verified model downloads, conversion to normalized Float32 samples, bounded 30-second inference windows, status files and temporary audio cleanup. `Voice.ps1` stores confirmed text independently in `manual-tasks.json`; the conversation analyzer cannot overwrite those tasks.

`speech-models.json` is the model catalog. Each record contains an ID, display name, engine adapter key, supported languages, model filename, tokenizer asset, download URL, compression, SHA256 of the uncompressed model and license notice. The SHA256 is checked before every inference; incomplete or corrupted downloads are never loaded.

`speech-engine.js` exposes `createEngine(model, directory, language)`. An adapter returns:

```js
{
  transcribe(samples) { /* Float32Array, mono 16kHz; return plain text */ },
  dispose() { /* release owned resources if required */ }
}
```

To add or replace a model, add its adapter to the registry and its catalog entry. Use that backend's supported language codes and tokenizer. If the model requires a different native dependency, add the pinned package and its license to the build. UI, microphone, PCM transport, confirmation and task persistence stay the same. A different sample rate is resampled inside its adapter; cloud APIs are not part of the current local speech contract.

Initial model: SenseVoiceSmall, INT8 ONNX conversion by sherpa-onnx, upstream version 2024-07-17. Source: https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17 . Native runtime: sherpa-onnx-node / sherpa-onnx-win-x64 1.13.8, CPU with two threads. No VocoType application code is copied.

The gzip release asset is a lossless compression of the upstream ONNX file; its uncompressed SHA256 is `c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51`. It is downloaded on first use, not bundled into the application installer. The tokenizer is bundled in `voice-tokens.txt`. Follow the model agreement and retain SenseVoice naming and attribution when distributing derivatives.

Tests use synthetic text, a localhost model fixture and public upstream audio. `tests/test-speech.cjs` covers download integrity, offline reuse, recovery, silence and bounded chunks. `tests/test-voice-ui.ps1` covers confirmation, cancellation, full text storage, settings and native hotkey collisions without opening the microphone. Widget `-Preview -SelfTest` covers completion and priority for captured tasks after analysis state replacement.

Audio is transient. The worker deletes the PCM file after inference, and closing capture cancels the worker and deletes its temporary audio. A crash may leave temporary PCM until the next launch; launch cleanup removes it. Stored tasks contain text, not audio, and are not sent to the conversation analysis service. First-use downloads require GitHub connectivity; a failed download can be retried. Cold start loads the model per capture, releasing model RAM when the worker exits. This is a deliberate first-version tradeoff; a resident worker can be added behind the same adapter contract after measuring memory and latency.
