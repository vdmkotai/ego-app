Upstream: https://github.com/argmaxinc/argmax-oss-swift
Commit: ea872ffd35705aa757f33033500b9b0d40bd38df
Included targets: ArgmaxCore, WhisperKit. CLI/TTS/diarization/test targets omitted.
Ego patch: ModelUtilities.loadTokenizer throws when local tokenizer load fails. It cannot fall back to Hub downloads. All tokenizer files are downloaded by Ego using pinned URLs and verified alongside the model. No transcript is uploaded.
