import unittest
import asyncdispatch
import json
import ../src/pocketflow

suite "Flow Tests":
  test "Create simple flow with start node":
    let startNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %"executed"
    )
    let flow = newFlow(startNode)
    check flow != nil

  test "Run flow with single node":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["output"] = %"processed"
        return %"done"
    )
    let flow = newFlow(node)
    let ctx = newPfContext()
    discard waitFor flow.internalRun(ctx)
    check ctx["output"].getStr() == "processed"

  test "Run flow with multiple chained nodes":
    let node1 = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["step1"] = %"complete"
        return %"next"
    )
    let node2 = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["step2"] = %"complete"
        return %"next"
    )
    let node3 = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["step3"] = %"complete"
        return %"done"
    )

    discard node1 >> node2 >> node3
    let flow = newFlow(node1)

    let ctx = newPfContext()
    discard waitFor flow.internalRun(ctx)

    check ctx["step1"].getStr() == "complete"
    check ctx["step2"].getStr() == "complete"
    check ctx["step3"].getStr() == "complete"

  test "Flow passes data between nodes via context":
    let producer = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["data"] = %42
        return %"produced"
    )
    let consumer = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        let data = ctx["data"].getInt()
        ctx["doubled"] = %(data * 2)
        return %"consumed"
    )

    discard producer >> consumer
    let flow = newFlow(producer)

    let ctx = newPfContext()
    discard waitFor flow.internalRun(ctx)

    check ctx["data"].getInt() == 42
    check ctx["doubled"].getInt() == 84

  test "Flow with branching based on post action":
    let decider = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return ctx["choice"]
      ,
      post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
        if execRes.getStr() == "A":
          return "branch_a"
        else:
          return "branch_b"
    )
    let branchA = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["result"] = %"took_a"
        return %"done"
    )
    let branchB = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["result"] = %"took_b"
        return %"done"
    )

    discard decider - "branch_a" >> branchA
    discard decider - "branch_b" >> branchB
    let flow = newFlow(decider)

    # Test branch A
    let ctxA = newPfContext()
    ctxA["choice"] = %"A"
    discard waitFor flow.internalRun(ctxA)
    check ctxA["result"].getStr() == "took_a"

    # Test branch B
    let ctxB = newPfContext()
    ctxB["choice"] = %"B"
    discard waitFor flow.internalRun(ctxB)
    check ctxB["result"].getStr() == "took_b"

  test "BatchFlow processes batch of params":
    # BatchFlow runs the startNode for each param set and collects actions (not exec results)
    # The node should store computed values in context
    var computedValues: seq[int] = @[]
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        let value = params["value"].getInt()
        let doubled = value * 2
        # Store in context for verification
        {.cast(gcsafe).}:
          computedValues.add(doubled)
        return %(doubled)
    )
    let batchFlow = newBatchFlow(node)
    discard batchFlow.setPrepBatch(
      proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %[%*{"value": 1}, %*{"value": 2}, %*{"value": 3}]
    )
    discard batchFlow.setPostBatch(
      proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
        # execRes contains the actions returned by each batch item run
        ctx["batch_count"] = %execRes.len
        return "done"
    )

    let ctx = newPfContext()
    let action = waitFor batchFlow.internalRun(ctx)

    check action == "done"
    check ctx["batch_count"].getInt() == 3
    # Verify the computed values were processed
    check computedValues.len == 3
    check computedValues[0] == 2
    check computedValues[1] == 4
    check computedValues[2] == 6

  test "ParallelBatchFlow processes items concurrently":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        await sleepAsync(10)
        return params["id"]
    )
    let parallelFlow = newParallelBatchFlow(node, maxConcurrency = 3)
    discard parallelFlow.setPrepBatch(
      proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        var items = newJArray()
        for i in 0..5:
          items.add(%*{"id": i})
        return items
    )
    discard parallelFlow.setPostBatch(
      proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
        ctx["parallel_results"] = execRes
        return "completed"
    )

    let ctx = newPfContext()
    let action = waitFor parallelFlow.internalRun(ctx)
    check action == "completed"
    check ctx["parallel_results"].len == 6

  test "Flow as subflow in another flow":
    let innerNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["inner"] = %"ran"
        return %"inner_done"
    )
    let innerFlow = newFlow(innerNode)

    let outerNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["outer"] = %"ran"
        return %"outer_done"
    )

    discard outerNode >> innerFlow
    let outerFlow = newFlow(outerNode)

    let ctx = newPfContext()
    discard waitFor outerFlow.internalRun(ctx)

    check ctx["outer"].getStr() == "ran"
    check ctx["inner"].getStr() == "ran"
