# MLX Swift LM used by Ego

Source: https://github.com/ml-explore/mlx-swift-lm
Version: 2.31.3
Revision: 25b00d4e22e61ec9c41efda47990cd2084ec87ff
License: MIT; upstream LICENSE retained.

One patch in Libraries/MLXLLM/LLMModel.swift adds cooperative task cancellation before and between prompt-prefill chunks, and synchronizes the stream on return. Without these checks a backgrounded iPhone could keep submitting GPU work until the whole prompt had been evaluated. Ego cancels when the scene becomes inactive, retains the generation task, and waits for its completion before beginning another job.

Other upstream sources are unchanged. Recheck this patch when updating the dependency.
