import unittest
import asyncdispatch
import json
import strutils
import ../src/pocketflow

suite "Integration Tests":
  test "Simple linear flow execution":
    let step1 = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["step1_done"] = %true
        return %"step1_complete"
    )
    let step2 = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["step2_done"] = %true
        return %"step2_complete"
    )
    let step3 = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["step3_done"] = %true
        return %"step3_complete"
    )

    discard step1 >> step2 >> step3
    let flow = newFlow(step1)

    let ctx = newPfContext()
    discard waitFor flow.internalRun(ctx)

    check ctx["step1_done"].getBool() == true
    check ctx["step2_done"].getBool() == true
    check ctx["step3_done"].getBool() == true

  test "Flow with data transformation":
    let producer = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["data"] = %*{"name": "test", "value": 100}
        return %"produced"
    )
    let transformer = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        let data = ctx["data"]
        let newValue = data["value"].getInt() * 2
        ctx["transformed_value"] = %newValue
        return %"transformed"
    )
    let consumer = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        let value = ctx["transformed_value"].getInt()
        ctx["final_result"] = %(value + 50)
        return %"consumed"
    )

    discard producer >> transformer >> consumer
    let flow = newFlow(producer)

    let ctx = newPfContext()
    discard waitFor flow.internalRun(ctx)

    check ctx["data"]["name"].getStr() == "test"
    check ctx["transformed_value"].getInt() == 200
    check ctx["final_result"].getInt() == 250

  test "Flow with branching":
    let router = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return ctx["route"]
      ,
      post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
        return execRes.getStr()
    )
    let handlerA = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["handled_by"] = %"A"
        return %"done"
    )
    let handlerB = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["handled_by"] = %"B"
        return %"done"
    )

    discard router - "route_a" >> handlerA
    discard router - "route_b" >> handlerB
    let flow = newFlow(router)

    # Test route A
    let ctxA = newPfContext()
    ctxA["route"] = %"route_a"
    discard waitFor flow.internalRun(ctxA)
    check ctxA["handled_by"].getStr() == "A"

    # Test route B
    let ctxB = newPfContext()
    ctxB["route"] = %"route_b"
    discard waitFor flow.internalRun(ctxB)
    check ctxB["handled_by"].getStr() == "B"

  test "Flow with retry and recovery":
    var attemptCount = 0
    let unreliableNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        {.cast(gcsafe).}:
          attemptCount += 1
          if attemptCount < 3:
            raise newException(Exception, "Temporary failure")
        ctx["success"] = %true
        return %"recovered"
      ,
      maxRetries = 5,
      waitMs = 10
    )

    let flow = newFlow(unreliableNode)
    let ctx = newPfContext()
    discard waitFor flow.internalRun(ctx)

    check attemptCount == 3
    check ctx["success"].getBool() == true

  test "Flow with fallback":
    let alwaysFailNode = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        raise newException(Exception, "Always fails")
      ,
      fallback = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, err: ref Exception): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["used_fallback"] = %true
        ctx["error_message"] = %err.msg
        return %"fallback_result"
      ,
      maxRetries = 1
    )

    let flow = newFlow(alwaysFailNode)
    let ctx = newPfContext()
    discard waitFor flow.internalRun(ctx)

    check ctx["used_fallback"].getBool() == true
    check ctx["error_message"].getStr().contains("Always fails")

  test "BatchFlow integration":
    let processor = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        let id = params["id"].getInt()
        let name = params["name"].getStr()
        ctx["last_processed"] = %*{"id": id, "name": name}
        return %("processed_" & name)
    )

    let batchFlow = newBatchFlow(processor)
    discard batchFlow.setPrepBatch(
      proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %[
          %*{"id": 1, "name": "Alice"},
          %*{"id": 2, "name": "Bob"},
          %*{"id": 3, "name": "Charlie"}
        ]
    )
    discard batchFlow.setPostBatch(
      proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
        ctx["batch_count"] = %execRes.len
        return "batch_complete"
    )

    let ctx = newPfContext()
    let action = waitFor batchFlow.internalRun(ctx)

    check action == "batch_complete"
    check ctx["batch_count"].getInt() == 3

  test "Nested flows":
    let innerStep = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        let depth = if ctx.hasKey("depth"): ctx["depth"].getInt() else: 0
        ctx["depth"] = %(depth + 1)
        ctx["inner_executed"] = %true
        return %"inner_done"
    )
    let innerFlow = newFlow(innerStep)

    let outerStart = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["outer_start"] = %true
        return %"outer_started"
    )
    let outerEnd = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["outer_end"] = %true
        return %"outer_ended"
    )

    discard outerStart >> innerFlow >> outerEnd
    let outerFlow = newFlow(outerStart)

    let ctx = newPfContext()
    discard waitFor outerFlow.internalRun(ctx)

    check ctx["outer_start"].getBool() == true
    check ctx["inner_executed"].getBool() == true
    check ctx["outer_end"].getBool() == true

  test "Complex workflow with multiple branches":
    let entryPoint = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["workflow_started"] = %true
        return %"entry"
      ,
      post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
        let taskType = ctx["task_type"].getStr()
        return taskType
    )

    let processA = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["process"] = %"A"
        return %"done"
    )

    let processB = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["process"] = %"B"
        return %"done"
    )

    discard entryPoint - "type_a" >> processA
    discard entryPoint - "type_b" >> processB

    let flow = newFlow(entryPoint)

    # Test type_a
    let ctxA = newPfContext()
    ctxA["task_type"] = %"type_a"
    discard waitFor flow.internalRun(ctxA)
    check ctxA["process"].getStr() == "A"

    # Test type_b
    let ctxB = newPfContext()
    ctxB["task_type"] = %"type_b"
    discard waitFor flow.internalRun(ctxB)
    check ctxB["process"].getStr() == "B"

  test "Context isolation between flow runs":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["result"] = %"processed"
        return %"done"
    )
    let flow = newFlow(node)

    let ctx1 = newPfContext()
    ctx1["input"] = %"first"
    discard waitFor flow.internalRun(ctx1)

    let ctx2 = newPfContext()
    ctx2["input"] = %"second"
    discard waitFor flow.internalRun(ctx2)

    # Each context should have its own data
    check ctx1["input"].getStr() == "first"
    check ctx2["input"].getStr() == "second"
    check ctx1["result"].getStr() == "processed"
    check ctx2["result"].getStr() == "processed"
