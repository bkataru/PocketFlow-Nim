# Changelog

All notable changes to PocketFlow-Nim will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-12-20

### Added
- **Comprehensive Test Suite**: 126 tests across 14 test files
  - `test_context.nim` - 11 tests for PfContext operations
  - `test_node.nim` - 11 tests for Node, BatchNode, ParallelBatchNode
  - `test_flow.nim` - 8 tests for Flow, BatchFlow, ParallelBatchFlow
  - `test_advanced_nodes.nim` - 8 tests for ConditionalNode, LoopNode, TimeoutNode, MapNode
  - `test_llm.nim` - 13 tests for LlmClient configuration
  - `test_rag.nim` - 9 tests for chunking, similarity, and retrieval
  - `test_observability.nim` - 10 tests for spans, metrics, and logging
  - `test_persistence.nim` - 9 tests for state capture, save, load, restore
  - `test_cache.nim` - 6 tests for caching operations
  - `test_tokens.nim` - 9 tests for token estimation and cost tracking
  - `test_errors.nim` - 7 tests for error types
  - `test_benchmark.nim` - 7 tests for performance measurement
  - `test_integration.nim` - 9 tests for complete workflow scenarios
  - `test_pocketflow.nim` - 9 tests for core functionality

### Fixed
- **Critical Bug**: Fixed `>>` operator chaining behavior
  - Previously `a >> b >> c` would incorrectly make `c` the successor of `a`, skipping `b`
  - Now correctly returns `nextNode` to enable proper chaining: `a -> b -> c`
- Fixed `newPfContext()` initialization causing SIGSEGV
- Fixed GC-safety issues in async procedures with `{.cast(gcsafe).}` wrappers
- Fixed import issues in various modules (strutils, sequtils, tables)
- Fixed parameter names in ChunkingOptions (`chunkOverlap` not `overlap`)
- Fixed Chunk field name (`text` not `content`)
- Fixed FlowState field name (`contextData` not `data`)
- Fixed TimeoutNode parameter name (`innerNode` not `inner`)
- Fixed MapNode API to use `__map_items__` and `__map_results__` context keys
- Fixed LoopNode API to use `__loop_item__` and `__loop_index__` context keys

### Changed
- Updated all test files to use correct API signatures with `{.async, closure, gcsafe.}` pragmas
- Improved error handling in fallback tests with `contains` for error message matching

## [0.1.0] - 2025-12-18

### Added
- Initial release of PocketFlow-Nim
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



[Unreleased]: https://github.com/bkataru/PocketFlow-Nim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bkataru/PocketFlow-Nim/releases/tag/v0.2.0
[0.1.0]: https://github.com/bkataru/PocketFlow-Nim/releases/tag/v0.1.0
