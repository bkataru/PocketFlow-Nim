# PocketFlow-Nim Cookbook

A collection of practical examples for building flows, batch jobs, and agent pipelines with PocketFlow-Nim.

---

## 1. Simple Linear Flow
```nim
import pocketflow

let ctx = newPfContext()

let n1 = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
    return newJString("hello")
)

let n2 = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
    echo prepRes.getStr
    return prepRes
)

let flow = newFlow(n1 >> n2)
waitFor flow.internalRun(ctx)
```

---

## 2. Branching Flow
```nim
import pocketflow

let ctx = newPfContext()

let n1 = newNode(
  exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
    if (now().month mod 2) == 0:
      return newJString("even")
    else:
      return newJString("odd")
  ,
  post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
    return execRes.getStr
)

let nEven = newNode(exec = ...)
let nOdd = newNode(exec = ...)

let flow = newFlow((n1 - "even") >> nEven >> (n1 - "odd") >> nOdd)
waitFor flow.internalRun(ctx)
```

---

## 3. Batch Processing
```nim
import pocketflow

let ctx = newPfContext()

let batch = newBatchNode(
  prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
    result = newJArray()
    for i in 0..4: result.add(newJInt(i))
    return result
  ,
  execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async.} =
    return newJInt(item.getInt * 2)
)

waitFor batch.internalRun(ctx)
```

---

## 4. Parallel Batch Flow
```nim
import pocketflow

let ctx = newPfContext()

let n = newNode(exec = ...)
let pflow = newParallelBatchFlow(n, maxConcurrency=4)
pflow.setPrepBatch(proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
  result = newJArray()
  for i in 0..9: result.add(%*{"val": i})
  return result
)
waitFor pflow.internalRun(ctx)
```

---

See the tests for more advanced usage!
