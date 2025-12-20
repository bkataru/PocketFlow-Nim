# PocketFlow-Nim Cookbook

A collection of practical examples for building flows, batch jobs, and agent pipelines with PocketFlow-Nim.

---

## 1. Simple Linear Flow

```nim
import asyncdispatch, json
import pocketflow

let step1 = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    ctx["message"] = %"Hello from step 1"
    return %"step1_done"
)

let step2 = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    let msg = ctx["message"].getStr()
    echo "Received: ", msg
    return %"step2_done"
)

# Chain nodes with >> operator
discard step1 >> step2

let flow = newFlow(step1)
let ctx = newPfContext()
waitFor flow.internalRun(ctx)
```

---

## 2. Branching Flow

```nim
import asyncdispatch, json
import pocketflow

let router = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    return ctx["route"]  # e.g., %"process_a" or %"process_b"
  ,
  post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
    return execRes.getStr()
)

let processA = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    ctx["result"] = %"Processed by A"
    return %"done"
)

let processB = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    ctx["result"] = %"Processed by B"
    return %"done"
)

# Use - operator to specify action-based branching
discard router - "process_a" >> processA
discard router - "process_b" >> processB

let flow = newFlow(router)
let ctx = newPfContext()
ctx["route"] = %"process_a"
waitFor flow.internalRun(ctx)
echo ctx["result"].getStr()  # "Processed by A"
```

---

## 3. Batch Processing

```nim
import asyncdispatch, json
import pocketflow

let batchNode = newBatchNode(
  prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    # Return array of items to process
    return %[%1, %2, %3, %4, %5]
  ,
  execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    # Process each item
    return %(item.getInt() * 2)
  ,
  post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
    ctx["results"] = execRes
    return "done"
)

let ctx = newPfContext()
waitFor batchNode.internalRun(ctx)
echo ctx["results"]  # [2, 4, 6, 8, 10]
```

---

## 4. Parallel Batch Flow

```nim
import asyncdispatch, json
import pocketflow

let processor = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    await sleepAsync(100)  # Simulate work
    return %(params["id"].getInt() * 2)
)

let parallelFlow = newParallelBatchFlow(processor, maxConcurrency = 4)

discard parallelFlow.setPrepBatch(
  proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    var items = newJArray()
    for i in 0..9:
      items.add(%*{"id": i})
    return items
)

discard parallelFlow.setPostBatch(
  proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
    ctx["parallel_results"] = execRes
    return "completed"
)

let ctx = newPfContext()
waitFor parallelFlow.internalRun(ctx)
# Processes 10 items with max 4 concurrent
```

---

## 5. Retry with Fallback

```nim
import asyncdispatch, json
import pocketflow

var attempts = 0

let unreliableNode = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    {.cast(gcsafe).}:
      attempts += 1
      if attempts < 3:
        raise newException(Exception, "Temporary failure")
    return %"success"
  ,
  fallback = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, err: ref Exception): Future[JsonNode] {.async, closure, gcsafe.} =
    ctx["used_fallback"] = %true
    return %"fallback_result"
  ,
  maxRetries = 5,
  waitMs = 100  # Wait 100ms between retries
)

let ctx = newPfContext()
waitFor unreliableNode.internalRun(ctx)
```

---

## 6. Conditional Node

```nim
import asyncdispatch, json
import pocketflow

let conditionalNode = newConditionalNode(
  condition = proc(ctx: PfContext, params: JsonNode): Future[bool] {.async, closure, gcsafe.} =
    return ctx["value"].getInt() > 10
  ,
  trueNode = newNode(
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
      ctx["branch"] = %"large"
      return %"done"
  ),
  falseNode = newNode(
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
      ctx["branch"] = %"small"
      return %"done"
  )
)

let ctx = newPfContext()
ctx["value"] = %15
waitFor conditionalNode.internalRun(ctx)
echo ctx["branch"].getStr()  # "large"
```

---

## 7. Loop Node

```nim
import asyncdispatch, json
import pocketflow

let loopNode = newLoopNode(
  items = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    return %[%"apple", %"banana", %"cherry"]
  ,
  body = newNode(
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
      let item = ctx["__loop_item__"].getStr()
      let idx = ctx["__loop_index__"].getInt()
      echo "Processing ", idx, ": ", item
      return %("processed_" & item)
  ),
  maxIterations = 100,
  aggregateResults = true
)

let ctx = newPfContext()
waitFor loopNode.internalRun(ctx)
# Results are aggregated in ctx["__loop_results__"]
```

---

## 8. Map Node

```nim
import asyncdispatch, json
import pocketflow

let mapNode = newMapNode(
  mapFunc = proc(ctx: PfContext, item: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    return %(item.getInt() * item.getInt())  # Square each number
  ,
  maxConcurrency = 3
)

let ctx = newPfContext()
ctx["__map_items__"] = %[%1, %2, %3, %4, %5]
waitFor mapNode.internalRun(ctx)
echo ctx["__map_results__"]  # [1, 4, 9, 16, 25]
```

---

## 9. Timeout Node

```nim
import asyncdispatch, json
import pocketflow

let slowNode = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    await sleepAsync(5000)  # 5 seconds
    return %"completed"
)

let timeoutNode = newTimeoutNode(
  innerNode = slowNode,
  timeoutMs = 1000  # 1 second timeout
)

let ctx = newPfContext()
try:
  waitFor timeoutNode.internalRun(ctx)
except TimeoutError:
  echo "Operation timed out!"
```

---

## 10. LLM Client

```nim
import asyncdispatch, json
import pocketflow

# Create client with cost tracking and caching
let tracker = newCostTracker()
let cache = newCache()

let llm = newLlmClient(
  provider = OpenAI,
  apiKey = getEnv("OPENAI_API_KEY"),
  model = "gpt-4",
  costTracker = tracker,
  cache = cache
)

# Use in a node
let chatNode = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    let response = await llm.chat(ctx["prompt"].getStr())
    ctx["response"] = %response
    return %"done"
)

let ctx = newPfContext()
ctx["prompt"] = %"Explain quantum computing in one sentence."
let flow = newFlow(chatNode)
waitFor flow.internalRun(ctx)

# Check costs
let summary = tracker.getSummary()
echo "Total cost: $", summary["total_cost_usd"].getFloat()
```

---

## 11. RAG Pipeline

```nim
import asyncdispatch, json
import pocketflow

# 1. Chunk documents
let document = readFile("document.txt")
let opts = newChunkingOptions(
  strategy = Sentences,
  chunkSize = 500,
  chunkOverlap = 50
)
var chunks = chunkDocument(document, opts)

# 2. Add embeddings (mock - in production use LLM)
for i in 0..<chunks.len:
  chunks[i].embedding = @[float(i) * 0.1, 0.5, 0.3]

# 3. Search
let queryEmbedding = @[0.1, 0.5, 0.3]
let topK = findTopK(queryEmbedding, chunks, k = 3)

# 4. Rerank
let reranked = rerankChunks(chunks, "search query")

echo "Top result: ", topK[0].chunk.text
```

---

## 12. State Persistence

```nim
import asyncdispatch, json
import pocketflow

# Create state store
let store = newStateStore(".pocketflow_state")

# Run flow and capture state
let node = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    ctx["processed"] = %true
    ctx["timestamp"] = %"2024-01-01"
    return %"done"
)

let flow = newFlow(node)
let ctx = newPfContext()
waitFor flow.internalRun(ctx)

# Save state
let state = captureState(ctx, "my_flow_run", %*{"version": "1.0"})
saveState(store, state)

# Later: restore state
let loadedState = loadState(store, "my_flow_run")
let restoredCtx = newPfContext()
restoreContext(restoredCtx, loadedState)

echo restoredCtx["processed"].getBool()  # true
```

---

## 13. Observability

```nim
import pocketflow

# Create span for timing
let span = newSpan("my_operation")

# Do work
doSomeWork()

# Finish span
finish(span)
echo "Duration: ", getDurationMs(span), "ms"

# Record metrics
recordMetric("requests_processed", 100.0, [("service", "api")])
recordMetric("error_count", 2.0, [("service", "api"), ("type", "timeout")])

# Structured logging
logStructured(Info, "Request completed", [("user_id", "123"), ("status", "success")])
logStructured(Error, "Request failed", [("error", "timeout")])

# Get metrics summary
let summary = getMetricsSummary()
echo summary.pretty()
```

---

## 14. Nested Flows

```nim
import asyncdispatch, json
import pocketflow

# Inner flow
let innerStep = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    ctx["inner_done"] = %true
    return %"inner_complete"
)
let innerFlow = newFlow(innerStep)

# Outer flow with inner flow as a node
let outerStart = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    ctx["outer_started"] = %true
    return %"continue"
)

let outerEnd = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
    ctx["outer_ended"] = %true
    return %"done"
)

# Chain: outer start -> inner flow -> outer end
discard outerStart >> innerFlow >> outerEnd
let outerFlow = newFlow(outerStart)

let ctx = newPfContext()
waitFor outerFlow.internalRun(ctx)

echo ctx["outer_started"].getBool()  # true
echo ctx["inner_done"].getBool()     # true
echo ctx["outer_ended"].getBool()    # true
```

---

## Tips

1. **Always use `{.async, closure, gcsafe.}` pragmas** for callback procs
2. **Use `{.cast(gcsafe).}` blocks** when accessing mutable variables inside async procs
3. **Check tests/** for more examples - there are 126 tests covering all features
4. **Use the `>>` operator** for linear chains, `-` operator for branching
5. **Context keys starting with `__`** are reserved for internal use (e.g., `__loop_item__`, `__map_items__`)

---

See the [tests/](tests/) directory for comprehensive examples of all features!