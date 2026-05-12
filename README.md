# mlx-server

OpenAI-compatible HTTP server for [mlx-swift-lm](https://github.com/ekryski/mlx-swift-lm) on Apple Silicon.

## Status

**Phase 0: scaffolding only.** No model loading, no inference yet. The repository exists so that the design conversation can proceed against real code. See the [roadmap](#roadmap) for what is planned.

## Why this exists

[mlx-swift-lm](https://github.com/ekryski/mlx-swift-lm) is a high-performance LLM inference library for Apple Silicon, with state-of-the-art speculative decoding, prefix KV-cache, and hybrid-architecture state replay landing in its [Tier 1 roadmap](https://github.com/ekryski/mlx-swift-lm/blob/alpha/specs/IMPLEMENTATION-PLAN.md). It is, by design, a Swift library, not a server. `mlx-server` is the missing HTTP layer.

The end goal is to be a drop-in replacement for `llama-server` in [LLMKube](https://llmkube.com)'s Apple Silicon path, with the perf characteristics of mlx-swift-lm.

## Goals

- OpenAI-compatible API surface: `/v1/chat/completions`, `/v1/completions`, `/v1/models`, `/v1/embeddings`
- Streaming via Server-Sent Events
- Tool calling and structured outputs
- Vision-language model support (Qwen-VL, Gemma 4 VL, etc.)
- Multi-slot concurrency with longest-prefix KV cache reuse
- Single static binary distribution via Homebrew + GitHub releases

## Non-goals

- Cross-platform support. Apple Silicon (arm64 macOS) only. If you need x86_64 or Linux, look at [llama.cpp](https://github.com/ggerganov/llama.cpp).
- vLLM compatibility. For that path see [vllm-swift](https://github.com/TheTom/vllm-swift) (Python API + Swift compute) or [vllm-metal](https://github.com/vllm-project/vllm-metal).
- Heavy abstractions over mlx-swift-lm. This is a thin HTTP wrapper, not a framework.

## Prior art

[TheTom's MLXServer](https://github.com/ekryski/mlx-swift-lm/tree/ek/tom-eric-moe-tuning/Sources/MLXServer) (abandoned in favor of vllm-swift) was the proof-of-concept that an MLX-swift HTTP server is feasible. Several design decisions here, particularly around the slot manager and longest-prefix KV cache, are informed by his approach. The decision to rebuild rather than fork is mainly because his original used hand-rolled socket code; this repo uses [Hummingbird](https://github.com/hummingbird-project/hummingbird) for the HTTP layer.

## Build

Requires:
- macOS 14 (Sonoma) or later, Apple Silicon
- Swift 6.0 or later (Xcode 16+)

```bash
swift build
.build/debug/mlx-server --help
```

## Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| 0 | Scaffolding, CI, `/health` endpoint, dependency wiring | In progress |
| 1 | `/v1/chat/completions` (streaming + non-streaming), `/v1/models`, single-slot model loading | Pending mlx-swift-lm Tier 1 release tag |
| 2 | Multi-slot `SlotManager`, longest-prefix prompt cache, Prometheus `/metrics`, structured logging, graceful shutdown | |
| 3 | Tool calling, thinking-model support, vision-language models, speculative decoding knobs, `/v1/embeddings` | |
| 4 | LLMKube `runtime: mlx-server` integration | |

## License

Apache 2.0. See [LICENSE](LICENSE).
