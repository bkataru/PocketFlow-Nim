import unittest, asyncdispatch, json, strutils
import ../src/pocketflow

suite "PocketFlow Tests":
  
  test "Simple Linear Flow":
    # Define nodes
    var startNode = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        return %* 10
      ,
      post = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
        ctx["currentValue"] = execRes
        return DefaultAction
    )

    var addNode = newNode(
      prep = proc (ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
        return ctx["currentValue"]
      ,
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        let val = prepRes.getInt()
        return %* (val + 5)
      ,
      post = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
        ctx["currentValue"] = execRes
        return "added"
    )

    # Connect nodes
    startNode.next(addNode)

    # Create Flow
    var flow = newFlow(startNode)
    var ctx = newPfContext()

    # Run Flow
    let action = waitFor flow.run(ctx)

    check action == "added"
    check ctx["currentValue"].getInt() == 15

  test "Branching Flow":
    # Start Node: Sets value to 10. If > 20 returns "over_20", else "default"
    var startNode = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        let multiplier = if params.hasKey("multiplier"): params["multiplier"].getInt() else: 1
        return %* (10 * multiplier)
      ,
      post = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
        let val = execRes.getInt()
        ctx["currentValue"] = execRes
        if val > 20:
          return "over_20"
        return DefaultAction
    )

    var defaultNode = newNode(
      post = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
        ctx["path"] = %* "default"
        return DefaultAction
    )

    var over20Node = newNode(
      post = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
        ctx["path"] = %* "over_20"
        return DefaultAction
    )

    # Connect
    startNode.next(DefaultAction, defaultNode)
    startNode.next("over_20", over20Node)

    var flow = newFlow(startNode)
    
    # Case 1: Multiplier 1 -> 10 -> Default
    var ctx1 = newPfContext()
    startNode.setParams(%* {"multiplier": 1})
    discard waitFor flow.run(ctx1)
    check ctx1["currentValue"].getInt() == 10
    check ctx1["path"].getStr() == "default"

    # Case 2: Multiplier 3 -> 30 -> Over 20
    var ctx2 = newPfContext()
    startNode.setParams(%* {"multiplier": 3})
    discard waitFor flow.run(ctx2)
    check ctx2["currentValue"].getInt() == 30
    check ctx2["path"].getStr() == "over_20"

  test "Batch Node":
    var batchNode = newBatchNode(
      prep = proc (ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
        return %* ["a", "b", "c"]
      ,
      execItem = proc (ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async.} =
        return %* (item.getStr() & "_processed")
      ,
      post = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
        ctx["results"] = execRes
        return "done"
    )

    var ctx = newPfContext()
    let action = waitFor batchNode.run(ctx)

    check action == "done"
    let results = ctx["results"]
    check results.len == 3
    check results[0].getStr() == "a_processed"
    check results[1].getStr() == "b_processed"
    check results[2].getStr() == "c_processed"

  test "Parallel Batch Node":
    var parallelNode = newParallelBatchNode(
      prep = proc (ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
        return %* [1, 2, 3, 4, 5]
      ,
      execItem = proc (ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async.} =
        await sleepAsync(10) # Simulate work
        return %* (item.getInt() * 2)
      ,
      post = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
        ctx["parallel_results"] = execRes
        return "done"
      ,
      maxConcurrency = 2
    )

    var ctx = newPfContext()
    let action = waitFor parallelNode.run(ctx)

    check action == "done"
    let results = ctx["parallel_results"]
    check results.len == 5
    check results[0].getInt() == 2
    check results[4].getInt() == 10

  test "Operator Overloads - >> and -":
    var n1 = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        ctx["step1"] = %* "done"
        return %* 1
    )
    
    var n2 = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        ctx["step2"] = %* "done"
        return %* 2
      ,
      post = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
        return "special"
    )
    
    var n3 = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        ctx["step3"] = %* "done"
        return %* 3
    )
    
    var n4 = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        ctx["step4"] = %* "done"
        return %* 4
    )
    
    # Test >> operator for default chaining
    discard n1 >> n2
    
    # Test - operator with >> for custom action
    discard (n2 - "special") >> n3
    discard (n2 - "default") >> n4
    
    var flow = newFlow(n1)
    var ctx = newPfContext()
    discard waitFor flow.run(ctx)
    
    check ctx.hasKey("step1")
    check ctx.hasKey("step2")
    check ctx.hasKey("step3")  # Should go to n3 via "special" action

  test "Retry with Fallback":
    var attemptCount = 0
    
    var retryNode = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        attemptCount += 1
        if attemptCount < 3:
          raise newException(Exception, "Simulated failure")
        return %* "success"
      ,
      fallback = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, err: ref Exception): Future[JsonNode] {.async.} =
        ctx["fallback_used"] = %* true
        ctx["error_msg"] = %* err.msg
        return %* "fallback_result"
      ,
      maxRetries = 2,
      waitMs = 10
    )
    
    var ctx = newPfContext()
    discard waitFor retryNode.run(ctx)
    
    check attemptCount == 2  # Should fail twice, then use fallback
    check ctx["fallback_used"].getBool() == true
    check ctx.hasKey("error_msg")

  test "curRetry Counter":
    var node = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        # Track attempts in context
        let attempts = if ctx.hasKey("attempts"): ctx["attempts"].getInt() + 1 else: 1
        ctx["attempts"] = %* attempts
        if attempts < 3:
          raise newException(Exception, "retry")
        return %* "ok"
      ,
      maxRetries = 3
    )
    
    var ctx = newPfContext()
    discard waitFor node.run(ctx)
    
    check ctx["attempts"].getInt() == 3

  test "BatchFlow":
    var itemNode = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        let val = params["value"].getInt()
        let result = val * 2
        # Store in context for verification
        if not ctx.hasKey("processed"):
          ctx["processed"] = newJArray()
        ctx["processed"].add(%* result)
        return %* result
    )
    
    var batchFlow = newBatchFlow(itemNode)
    batchFlow.setPrepBatch(proc (ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      return %* [
        {"value": 1},
        {"value": 2},
        {"value": 3}
      ]
    )
    
    var ctx = newPfContext()
    discard waitFor batchFlow.run(ctx)
    
    check ctx["processed"].len == 3
    check ctx["processed"][0].getInt() == 2
    check ctx["processed"][1].getInt() == 4
    check ctx["processed"][2].getInt() == 6

  test "ParallelBatchFlow":
    var itemNode = newNode(
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        let val = params["value"].getInt()
        await sleepAsync(10)  # Simulate async work
        return %* (val * 3)
    )
    
    var parallelBatchFlow = newParallelBatchFlow(itemNode, maxConcurrency = 2)
    parallelBatchFlow.setPrepBatch(proc (ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
      return %* [
        {"value": 1},
        {"value": 2},
        {"value": 3},
        {"value": 4}
      ]
    )
    parallelBatchFlow.setPostBatch(proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
      ctx["flow_results"] = execRes
      return "done"
    )
    
    var ctx = newPfContext()
    discard waitFor parallelBatchFlow.run(ctx)
    
    # ParallelBatchFlow returns actions (JString) not execution results
    # Verify the flow ran 4 times
    check ctx.hasKey("flow_results")
    check ctx["flow_results"].len == 4

