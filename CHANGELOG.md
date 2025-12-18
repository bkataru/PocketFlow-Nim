# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive NimDoc API documentation for all modules
- Streaming support for LLM responses
- Multiple LLM provider support (OpenAI, Ollama, Anthropic, Google Gemini)
- Observability layer with structured logging and metrics
- Caching layer for LLM responses and embeddings
- RAG capabilities: document chunking, embeddings, vector retrieval
- Advanced node types: ConditionalNode, LoopNode, TimeoutNode
- Token counting and cost tracking
- State persistence and recovery
- Enhanced error handling with custom exception types
- Performance benchmarks
- Examples directory with real-world use cases
- GitHub Actions CI/CD pipeline

### Changed
- Improved async/await patterns throughout
- Enhanced retry logic with exponential backoff
- Better type safety with stricter compile-time checks

### Fixed
- Memory management in concurrent batch operations
- Edge cases in flow branching logic

## [0.1.0] - 2025-12-18

### Added
- Initial release
- Core Node, BatchNode, ParallelBatchNode implementations
- Flow, BatchFlow, ParallelBatchFlow support
- Basic LLM integration (OpenAI, Ollama)
- Retry and fallback mechanisms
- Pythonic operator overloading (`>>`, `-`)
- Comprehensive test suite
- Basic documentation (README, COOKBOOK)

[Unreleased]: https://github.com/yourusername/PocketFlow-Nim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourusername/PocketFlow-Nim/releases/tag/v0.1.0
