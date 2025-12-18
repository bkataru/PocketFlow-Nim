# PocketFlow-Nim

[![CI](https://github.com/yourusername/PocketFlow-Nim/workflows/CI/badge.svg)](https://github.com/yourusername/PocketFlow-Nim/actions)
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
- 💾 **State persistence** - Save and restore flow state (planned)

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

let ctx = newPfContext()
let llm = newLlmClient(provider = OpenAI, apiKey = "your-api-key")

let node = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
    let response = await llm.generate("Tell me a fun fact!")
    return %response
)

let flow = newFlow(node)
waitFor flow.internalRun(ctx)
```

### RAG Example

```nim
import pocketflow

# Chunk document
let chunks = chunkDocument(document, newChunkingOptions())

# Generate embeddings
let llm = newLlmClient(provider = OpenAI, apiKey = apiKey)
let embeddings = await llm.embeddings(chunks.mapIt(it.text))

# Search and retrieve
let queryEmbed = (await llm.embeddings(@[query]))[0]
let topChunks = findTopK(queryEmbed, chunks, k = 3)

# Generate answer
let context = topChunks.mapIt(it.chunk.text).join("\n\n")
let answer = await llm.generate("Based on: " & context & "\n\nQ: " & query)
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
  prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
    return %42
  ,
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
    let value = prepRes.getInt()
    return %(value * 2)
  ,
  post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
    return "next_step"
  ,
  maxRetries = 3,
  waitMs = 1000
)
```

#### Flows
Flows orchestrate node execution:

```nim
# Linear flow
let flow = newFlow(node1 >> node2 >> node3)

# Branching flow
node1
  .next("success", successNode)
  .next("error", errorNode)

# Or with operators
(node1 - "success") >> successNode >> (node1 - "error") >> errorNode
```

#### Batch Processing

```nim
let batchNode = newBatchNode(
  prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
    return %*["item1", "item2", "item3"]
  ,
  execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async.} =
    # Process each item
    return %(item.getStr().toUpper())
)

# Parallel processing with concurrency limit
let parallelNode = newParallelBatchNode(
  prep = proc(...): Future[JsonNode] {.async.} = ...,
  execItem = proc(...): Future[JsonNode] {.async.} = ...,
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
# Automatic cost tracking
let response = await llm.generate("Hello")

# Get summary
echo globalCostTracker.getSummary().pretty()
# {
#   "total_input_tokens": 10,
#   "total_output_tokens": 50,
#   "total_cost_usd": 0.00015,
#   ...
# }
```

### Caching

```nim
# Automatic caching (enabled by default)
let response1 = await llm.generate("Same prompt")  # API call
let response2 = await llm.generate("Same prompt")  # Cached!

# Manual cache control
let options = LlmOptions(useCache: false)
let response = await llm.chatWithOptions(messages, options)

# Clear cache
globalCache.clear()
```

### Advanced Nodes

#### Conditional Node

```nim
let conditional = newConditionalNode(
  condition = proc(ctx: PfContext, params: JsonNode): Future[bool] {.async.} =
    return params["score"].getInt() > 80
  ,
  trueNode = highScoreNode,
  falseNode = lowScoreNode
)
```

#### Loop Node

```nim
let loop = newLoopNode(
  items = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
    return %*[1, 2, 3, 4, 5]
  ,
  body = processItemNode,
  maxIterations = 100,
  aggregateResults = true
)
```

#### Timeout Node

```nim
let timeout = newTimeoutNode(
  innerNode = slowOperationNode,
  timeoutMs = 5000  # 5 seconds
)
```

### Observability

```nim
# Structured logging
logStructured(Info, "Processing started", [("user_id", "123")])

# Metrics
recordMetric("requests_processed", 1.0, [("status", "success")])

# Tracing
withSpan("expensive_operation"):
  # Your code here
  discard await someOperation()

# Get metrics summary
echo getMetricsSummary().pretty()
```

## 📖 Examples

See the [`examples/`](examples/) directory for complete examples:

- [`simple_chat.nim`](examples/simple_chat.nim) - Basic LLM integration
- [`rag_example.nim`](examples/rag_example.nim) - Full RAG pipeline
- [`advanced_flow.nim`](examples/advanced_flow.nim) - Advanced features demo

## 🧪 Testing

```bash
# Run unit tests
nimble test

# Run live LLM tests (requires API keys)
nimble testlive

# Build examples
nimble examples
```

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
│   └── advanced_nodes.nim   # Advanced node types
├── tests/
├── examples/
└── docs/
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

- [x] Core framework
- [x] Multiple LLM providers
- [x] RAG capabilities
- [x] Advanced nodes
- [x] Observability
- [ ] WebSocket streaming
- [ ] GraphQL API
- [ ] Vector database integrations
- [ ] Multi-agent orchestration
- [ ] State persistence
- [ ] Performance benchmarks

---

**Star ⭐ this repo if you find it useful!**
