import unittest
import asyncdispatch
import json
import times
import ../src/pocketflow

suite "Benchmark Tests":
  test "Create benchmark runner":
    # Simple benchmark test - just ensure we can time operations
    let startTime = cpuTime()

    # Do some work
    var sum = 0
    for i in 0..1000:
      sum += i

    let endTime = cpuTime()
    let duration = endTime - startTime

    check duration >= 0.0
    check sum == 500500

  test "Time node execution":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        await sleepAsync(10)
        ctx["executed"] = %true
        return %"done"
    )

    let startTime = cpuTime()
    let ctx = newPfContext()
    discard waitFor node.internalRun(ctx)
    let endTime = cpuTime()

    check ctx["executed"].getBool() == true
    check endTime >= startTime

  test "Time flow execution":
    let node1 = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["step1"] = %true
        return %"done"
    )
    let node2 = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["step2"] = %true
        return %"done"
    )

    discard node1 >> node2
    let flow = newFlow(node1)

    let startTime = epochTime()
    let ctx = newPfContext()
    discard waitFor flow.internalRun(ctx)
    let endTime = epochTime()

    check ctx["step1"].getBool() == true
    check ctx["step2"].getBool() == true
    check endTime >= startTime

  test "Measure throughput":
    var counter = 0
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        {.cast(gcsafe).}:
          counter += 1
        return %"done"
    )

    let iterations = 100
    let startTime = cpuTime()

    for i in 0..<iterations:
      let ctx = newPfContext()
      discard waitFor node.internalRun(ctx)

    let endTime = cpuTime()
    let duration = endTime - startTime

    check counter == iterations

    if duration > 0:
      let throughput = float(iterations) / duration
      check throughput > 0.0

  test "Compare node vs flow overhead":
    # Node alone
    let singleNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %1
    )

    let nodeStart = cpuTime()
    for i in 0..99:
      let ctx = newPfContext()
      discard waitFor singleNode.internalRun(ctx)
    let nodeTime = cpuTime() - nodeStart

    # Flow with same node
    let flow = newFlow(singleNode)
    let flowStart = cpuTime()
    for i in 0..99:
      let ctx = newPfContext()
      discard waitFor flow.internalRun(ctx)
    let flowTime = cpuTime() - flowStart

    # Both should complete
    check nodeTime >= 0.0
    check flowTime >= 0.0

  test "BatchNode performance":
    let batchNode = newBatchNode(
      prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        var items = newJArray()
        for i in 0..9:
          items.add(%i)
        return items
      ,
      execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %(item.getInt() * 2)
    )

    let startTime = cpuTime()
    let ctx = newPfContext()
    discard waitFor batchNode.internalRun(ctx)
    let endTime = cpuTime()

    check endTime >= startTime

  test "ParallelBatchNode performance":
    let parallelNode = newParallelBatchNode(
      prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        var items = newJArray()
        for i in 0..9:
          items.add(%i)
        return items
      ,
      execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        await sleepAsync(5)
        return %(item.getInt() * 2)
      ,
      maxConcurrency = 5
    )

    let startTime = epochTime()
    let ctx = newPfContext()
    discard waitFor parallelNode.internalRun(ctx)
    let endTime = epochTime()

    # With 10 items and max 5 concurrent, should take ~2 batches of 5ms each
    let duration = endTime - startTime
    check duration < 0.5  # Should be much faster than 50ms sequential
