'use strict';
const path = require('node:path');

// Adapters accept normalized mono 16kHz PCM and return text only.
// Model paths, languages and download assets live in speech-models.json.
const adapters = {
  'sherpa-sensevoice': (model, directory, language) => {
    const sherpa = require('sherpa-onnx-node');
    const recognizer = new sherpa.OfflineRecognizer({
      featConfig: {sampleRate: 16000, featureDim: 80},
      modelConfig: {
        senseVoice: {model: path.join(directory, model.file), language,
          useInverseTextNormalization: 1},
        tokens: path.join(__dirname, model.tokens), numThreads: 2,
        provider: 'cpu', debug: 0,
      },
    });
    return {
      transcribe(samples) {
        const stream = recognizer.createStream();
        stream.acceptWaveform({sampleRate: 16000, samples});
        recognizer.decode(stream);
        return recognizer.getResult(stream).text.replace(/<\|[^|]*\|>/g, '').trim();
      },
      // Native handles are GC managed; the worker exits after each capture.
      dispose() {},
    };
  },
};

function createEngine(model, directory, language = 'auto') {
  if (!model.languages.includes(language)) throw new Error('Unsupported speech language');
  const adapter = adapters[model.engine];
  if (!adapter) throw new Error('Unsupported speech engine: ' + model.engine);
  return adapter(model, directory, language);
}
module.exports = {createEngine};
