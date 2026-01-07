# PocketFlow-Nim

[![CI](https://github.com/bkataru/PocketFlow-Nim/workflows/CI/badge.svg)](https://github.com/bkataru/PocketFlow-Nim/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Nim Version](https://img.shields.io/badge/nim-2.0+-blue.svg)](https://nim-lang.org/)

A powerful, production-ready flow-based agent framework for Nim with advanced LLM integration, RAG capabilities, and comprehensive orchestration features.

## ✨ Features

### Core Framework
- 🔄 **Node-based workflows** - Node, BatchNode, ParallelBatchNode
- 🌊 **Flow orchestration** - Flow, BatchFlow, ParallelBatchFlow
- ⚡ **Async/await everywhere** - Built on Nim's efficient asyncdispatch
- 🔁 **Retry & fallback** - Robust error handling with exponential backoff
- 🔗 **Pythonic chaining** - Clean `>>` and `-` operators
- 📦 **Shared context** - Type-safe JSON data sharing

### LLM Integration
- 🤖 **Multiple providers** - OpenAI, Anthropic Claude, Google Gemini, Ollama
- 💰 **Cost tracking** - Automatic token counting and cost estimation
- 💾 **Smart caching** - LRU cache for responses and embeddings
- 📊 **Streaming support** - Real-time response streaming
- 🔐 **Error handling** - Custom exception types with provider-specific errors

### RAG Capabilities
- 📄 **Document chunking** - Fixed-size, sentence, paragraph, semantic strategies
- 🧮 **Embeddings** - Generate and cache vector embeddings
- 🔍 **Semantic search** - Cosine similarity and top-k retrieval
- 🎯 **Reranking** - Query-aware result reordering

### Advanced Features
- ⏰ **TimeoutNode** - Execution timeout protection
- 🔀 **ConditionalNode** - Dynamic branching logic
- 🔁 **LoopNode** - Iteration with result aggregation
- 🗺️ **MapNode** - Concurrent mapping operations
- 📈 **Observability** - Structured logging, metrics, and tracing
- 💾 **State persistence** - Save and restore flow state

## 🚀 Quick Start

### Installation

```bash
nimble install pocketflow
```

Or add to your `.nimble` file:

```nimble
requires "pocketflow >= 0.2.0"
```

### Basic Example

```nim
import asyncdispatch, json
import pocketflow

let step1 = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    ctx["message"] = %"Hello from PocketFlow!"
    return %"done"
)

let step2 = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    echo ctx["message"].getStr()
    return %"complete"
)

# Chain nodes with >> operator
discard step1 >> step2

let flow = newFlow(step1)
let ctx = newPfContext()
waitFor flow.internalRun(ctx)
```

### LLM Example

```nim
import asyncdispatch, json, os
import pocketflow

let llm = newLlmClient(
  provider = OpenAI,
  apiKey = getEnv("OPENAI_API_KEY"),
  model = "gpt-4"
)

let chatNode = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    let response = await llm.chat(ctx["prompt"].getStr())
    ctx["response"] = %response
    return %"done"
)

let flow = newFlow(chatNode)
let ctx = newPfContext()
ctx["prompt"] = %"Tell me a fun fact!"
waitFor flow.internalRun(ctx)
echo ctx["response"].getStr()
```

### RAG Example

```nim
import pocketflow

# Chunk document
let document = readFile("document.txt")
let opts = newChunkingOptions(strategy = Sentences, chunkSize = 500)
var chunks = chunkDocument(document, opts)

# Search with embeddings
let queryEmbedding = @[0.1, 0.5, 0.3]
let topChunks = findTopK(queryEmbedding, chunks, k = 3)

# Rerank results
let reranked = rerankChunks(chunks, "search query")
echo "Top result: ", topChunks[0].chunk.text
```

## 📚 Documentation

### Core Concepts

#### Nodes
Nodes are the building blocks of workflows. Each node has three phases:
- **Prep**: Prepare data (optional)
- **Exec**: Execute main logic (with retry support)
- **Post**: Process results and determine next action

```nim
let node = newNode(
  prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    return %42
  ,
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    let value = prepRes.getInt()
    return %(value * 2)
  ,
  post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
    return "next_step"
  ,
  maxRetries = 3,
  waitMs = 1000
)
```

> **Note**: Always use `{.async, closure, gcsafe.}` pragmas for callback procs.

#### Flows
Flows orchestrate node execution:

```nim
# Linear flow with >> operator
discard node1 >> node2 >> node3
let flow = newFlow(node1)

# Branching flow with - operator
discard router - "success" >> successNode
discard router - "error" >> errorNode
let branchFlow = newFlow(router)
```

#### Batch Processing

```nim
let batchNode = newBatchNode(
  prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    return %[%"item1", %"item2", %"item3"]
  ,
  execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    return %(item.getStr().toUpperAscii())
  ,
  post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
    ctx["results"] = execRes
    return "done"
)

# Parallel processing with concurrency limit
let parallelNode = newParallelBatchNode(
  prep = ...,
  execItem = ...,
  maxConcurrency = 5
)
```

### LLM Providers

#### OpenAI

```nim
let llm = newLlmClient(
  provider = OpenAI,
  apiKey = "sk-...",
  model = "gpt-4o-mini"
)
```

#### Anthropic Claude

```nim
let llm = newLlmClient(
  provider = Anthropic,
  apiKey = "sk-ant-...",
  model = "claude-3-5-sonnet-20241022"
)
```

#### Google Gemini

```nim
let llm = newLlmClient(
  provider = Google,
  apiKey = "...",
  model = "gemini-1.5-flash"
)
```

#### Ollama (Local)

```nim
let llm = newLlmClient(
  provider = Ollama,
  model = "llama3"
)
```

### Cost Tracking

```nim
let tracker = newCostTracker()
let llm = newLlmClient(
  provider = OpenAI,
  apiKey = apiKey,
  costTracker = tracker
)

# Use the client...
let response = await llm.chat("Hello")

# Get summary
let summary = tracker.getSummary()
echo "Total cost: $", summary["total_cost_usd"].getFloat()
```

### Caching

```nim
let cache = newCache()
let llm = newLlmClient(
  provider = OpenAI,
  apiKey = apiKey,
  cache = cache
)

# First call hits API
let response1 = await llm.chat("Same prompt")

# Second call returns cached result
let response2 = await llm.chat("Same prompt")

# Clear cache when needed
cache.clear()
```

### Advanced Nodes

#### Conditional Node

```nim
let conditional = newConditionalNode(
  condition = proc(ctx: PfContext, params: JsonNode): Future[bool] {.async, closure, gcsafe.} =
    return ctx["score"].getInt() > 80
  ,
  trueNode = highScoreNode,
  falseNode = lowScoreNode
)
```

#### Loop Node

```nim
let loop = newLoopNode(
  items = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    return %[%1, %2, %3, %4, %5]
  ,
  body = processItemNode,
  maxIterations = 100,
  aggregateResults = true
)
# Access current item via ctx["__loop_item__"]
# Access current index via ctx["__loop_index__"]
```

#### Timeout Node

```nim
let timeout = newTimeoutNode(
  innerNode = slowOperationNode,
  timeoutMs = 5000  # 5 seconds
)
```

#### Map Node

```nim
let mapNode = newMapNode(
  mapFunc = proc(ctx: PfContext, item: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    return %(item.getInt() * 2)
  ,
  maxConcurrency = 3
)
# Set items via ctx["__map_items__"]
# Results stored in ctx["__map_results__"]
```

### State Persistence

```nim
let store = newStateStore(".pocketflow_state")

# Capture and save state
let state = captureState(ctx, "my_flow", %*{"version": "1.0"})
saveState(store, state)

# Load and restore state
let loadedState = loadState(store, "my_flow")
let restoredCtx = newPfContext()
restoreContext(restoredCtx, loadedState)
```

### Observability

```nim
# Structured logging
logStructured(Info, "Processing started", [("user_id", "123")])

# Metrics
recordMetric("requests_processed", 1.0, [("status", "success")])

# Tracing with spans
let span = newSpan("expensive_operation")
# ... do work ...
finish(span)
echo "Duration: ", getDurationMs(span), "ms"

# Get metrics summary
echo getMetricsSummary().pretty()
```

## 📖 Examples

See the [`examples/`](examples/) directory for complete examples:

- [`simple_chat.nim`](examples/simple_chat.nim) - Basic LLM integration
- [`rag_example.nim`](examples/rag_example.nim) - Full RAG pipeline
- [`advanced_flow.nim`](examples/advanced_flow.nim) - Advanced features demo
- [`multi_provider.nim`](examples/multi_provider.nim) - Multiple LLM providers
- [`benchmarks.nim`](examples/benchmarks.nim) - Performance benchmarks

## 🧪 Testing

```bash
# Run all unit tests
nimble test

# Run live LLM tests (requires API keys)
nimble testlive

# Build examples
nimble examples
```

**Test Coverage**: 126 tests across 14 test files covering all modules.

## 🏗️ Architecture

```
PocketFlow-Nim/
├── src/pocketflow/
│   ├── context.nim          # Shared context
│   ├── node.nim             # Core node types
│   ├── flow.nim             # Flow orchestration
│   ├── llm.nim              # LLM client
│   ├── errors.nim           # Exception types
│   ├── cache.nim            # Caching layer
│   ├── tokens.nim           # Cost tracking
│   ├── observability.nim    # Logging & metrics
│   ├── rag.nim              # RAG utilities
│   ├── advanced_nodes.nim   # Advanced node types
│   ├── persistence.nim      # State persistence
│   └── benchmark.nim        # Benchmarking utilities
├── tests/                   # 126 unit tests
├── examples/                # Example applications
└── docs/                    # Documentation
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new features
4. Ensure CI passes
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by [PocketFlow](https://github.com/The-Pocket/PocketFlow) (Python)
- Built with ❤️ using [Nim](https://nim-lang.org/)

## 🗺️ Roadmap

- [x] Core framework (Node, BatchNode, ParallelBatchNode)
- [x] Flow orchestration (Flow, BatchFlow, ParallelBatchFlow)
- [x] Multiple LLM providers (OpenAI, Anthropic, Google, Ollama)
- [x] RAG capabilities (chunking, similarity, retrieval, reranking)
- [x] Advanced nodes (Conditional, Loop, Timeout, Map)
- [x] Observability (logging, metrics, tracing)
- [x] State persistence (save, load, restore)
- [x] Comprehensive test suite (126 tests)
- [ ] WebSocket streaming
- [ ] GraphQL API
- [ ] Vector database integrations
- [ ] Multi-agent orchestration

---

**Star ⭐ this repo if you find it useful!**