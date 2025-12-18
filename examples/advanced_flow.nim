## Advanced Flow Example
##
## Demonstrates conditional nodes, loops, batch processing, and error handling.

import asyncdispatch, json, strformat
import ../src/pocketflow

proc main() {.async.} =
  echo "=== PocketFlow Advanced Features Demo ===\n"
  
  let ctx = newPfContext()
  
  # Example 1: Conditional Node
  echo "Example 1: Conditional Branching"
  echo "--------------------------------"
  
  let conditionNode = newConditionalNode(
    condition = proc(ctx: PfContext, params: JsonNode): Future[bool] {.async.} =
      let value = params.getOrDefault("value").getInt(0)
      return value > 10
    ,
    trueNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        echo "Value is greater than 10!"
        return %"high"
    ),
    falseNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        echo "Value is 10 or less!"
        return %"low"
    )
  )
  
  conditionNode.setParams(%*{"value": 15})
  discard await conditionNode.internalRun(ctx)
  
  # Example 2: Loop Node
  echo "\n\nExample 2: Loop Node"
  echo "--------------------"
  
  let loopNode = newLoopNode(
    items = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      return %*[1, 2, 3, 4, 5]
    ,
    body = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        let item = ctx["__loop_item__"].getInt()
        let index = ctx["__loop_index__"].getInt()
        echo fmt"Processing item {index + 1}: {item} -> {item * 2}"
        ctx["__loop_result__"] = %(item * 2)
        return %(item * 2)
    ),
    maxIterations = 100,
    aggregateResults = true
  )
  
  discard await loopNode.internalRun(ctx)
  echo "\nAggregated results:"
  echo ctx["__loop_results__"].pretty()
  
  # Example 3: Batch Processing with Retry
  echo "\n\nExample 3: Batch Processing with Retry"
  echo "---------------------------------------"
  
  var attemptCount = 0
  let batchNode = newBatchNode(
    prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      return %*["apple", "banana", "cherry", "date"]
    ,
    execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async.} =
      attemptCount += 1
      let fruit = item.getStr()
      
      # Simulate occasional failure
      if attemptCount == 2:
        echo fmt"Processing {fruit}... FAILED (will retry)"
        raise newException(Exception, "Simulated failure")
      
      echo fmt"Processing {fruit}... SUCCESS"
      return %(fruit.toUpper())
    ,
    maxRetries = 3,
    waitMs = 100
  )
  
  discard await batchNode.internalRun(ctx)
  
  # Example 4: Parallel Batch with Concurrency Limit
  echo "\n\nExample 4: Parallel Batch Processing"
  echo "-------------------------------------"
  
  let parallelNode = newParallelBatchNode(
    prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      return %*[1, 2, 3, 4, 5, 6, 7, 8]
    ,
    execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async.} =
      let value = item.getInt()
      await sleepAsync(100)  # Simulate work
      echo fmt"Processed {value} in parallel"
      return %(value * value)
    ,
    maxConcurrency = 3
  )
  
  discard await parallelNode.internalRun(ctx)
  
  # Example 5: Error Handling with Fallback
  echo "\n\nExample 5: Error Handling with Fallback"
  echo "----------------------------------------"
  
  let nodeWithFallback = newNode(
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
      echo "Attempting risky operation..."
      raise newException(Exception, "Something went wrong!")
    ,
    fallback = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, err: ref Exception): Future[JsonNode] {.async.} =
      echo fmt"Fallback triggered! Error was: {err.msg}"
      return %"fallback_result"
    ,
    maxRetries = 2
  )
  
  discard await nodeWithFallback.internalRun(ctx)
  
  echo "\n\n=== Demo Complete ==

="

when isMainModule:
  waitFor main()
