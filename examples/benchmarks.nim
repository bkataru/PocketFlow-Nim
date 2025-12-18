## Performance Benchmarks
##
## Compares performance of different node types and configurations.

import asyncdispatch, json
import ../src/pocketflow

proc runBenchmarks() {.async.} =
  echo "=== PocketFlow Performance Benchmarks ===\n"
  
  let suite = newBenchmarkSuite()
  
  # Benchmark 1: Simple node execution
  let simpleNode = newNode(
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
      return %(42 * 2)
  )
  
  discard await suite.benchmarkNode("Simple Node", simpleNode, iterations = 1000)
  
  # Benchmark 2: Node with prep and post
  let complexNode = newNode(
    prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      return %*[1, 2, 3, 4, 5]
    ,
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
      var sum = 0
      for item in prepRes:
        sum += item.getInt()
      return %sum
    ,
    post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
      return "done"
  )
  
  discard await suite.benchmarkNode("Complex Node (prep+exec+post)", complexNode, iterations = 1000)
  
  # Benchmark 3: BatchNode
  let batchNode = newBatchNode(
    prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      var items = newJArray()
      for i in 0..<10:
        items.add(%i)
      return items
    ,
    execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async.} =
      return %(item.getInt() * 2)
  )
  
  discard await suite.benchmarkNode("BatchNode (10 items)", batchNode, iterations = 100)
  
  # Benchmark 4: ParallelBatchNode (unlimited concurrency)
  let parallelBatchUnlimited = newParallelBatchNode(
    prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      var items = newJArray()
      for i in 0..<10:
        items.add(%i)
      return items
    ,
    execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async.} =
      await sleepAsync(1)  # Simulate work
      return %(item.getInt() * 2)
    ,
    maxConcurrency = 0
  )
  
  discard await suite.benchmarkNode("ParallelBatch (unlimited)", parallelBatchUnlimited, iterations = 50)
  
  # Benchmark 5: ParallelBatchNode (limited concurrency = 3)
  let parallelBatchLimited = newParallelBatchNode(
    prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      var items = newJArray()
      for i in 0..<10:
        items.add(%i)
      return items
    ,
    execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async.} =
      await sleepAsync(1)  # Simulate work
      return %(item.getInt() * 2)
    ,
    maxConcurrency = 3
  )
  
  discard await suite.benchmarkNode("ParallelBatch (limit=3)", parallelBatchLimited, iterations = 50)
  
  # Benchmark 6: Flow execution
  let node1 = newNode(
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
      return %10
  )
  let node2 = newNode(
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
      return %20
  )
  let node3 = newNode(
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
      return %30
  )
  
  let linearFlow = newFlow(node1 >> node2 >> node3)
  discard await suite.benchmarkFlow("Linear Flow (3 nodes)", linearFlow, iterations = 500)
  
  # Benchmark 7: ConditionalNode
  let conditionalNode = newConditionalNode(
    condition = proc(ctx: PfContext, params: JsonNode): Future[bool] {.async.} =
      return true
    ,
    trueNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        return %"true_branch"
    ),
    falseNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        return %"false_branch"
    )
  )
  
  discard await suite.benchmarkNode("ConditionalNode", conditionalNode, iterations = 1000)
  
  # Benchmark 8: LoopNode
  let loopNode = newLoopNode(
    items = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      return %*[1, 2, 3, 4, 5]
    ,
    body = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        let item = ctx["__loop_item__"].getInt()
        ctx["__loop_result__"] = %(item * 2)
        return %(item * 2)
    )
  )
  
  discard await suite.benchmarkNode("LoopNode (5 iterations)", loopNode, iterations = 200)
  
  # Print results
  suite.printSummary()
  
  # Compare to baseline
  suite.compare("Simple Node")
  
  # Export to JSON
  echo "\nExporting results to benchmarks.json..."
  writeFile("benchmarks.json", suite.toJson().pretty())

when isMainModule:
  waitFor runBenchmarks()
