import unittest
import asyncdispatch
import json
import ../src/pocketflow

suite "Node Tests":
  test "Create simple node with exec callback":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %"executed"
    )
    check node != nil

  test "Run node and get result":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %42
    )
    let ctx = newPfContext()
    let result = waitFor node.internalRun(ctx)
    check result == "default"  # DefaultAction is "default"

  test "Node can access context":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["executed"] = %true
        return %"done"
    )
    let ctx = newPfContext()
    discard waitFor node.internalRun(ctx)
    check ctx["executed"].getBool() == true

  test "Node with prep callback":
    let node = newNode(
      prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %"prepared"
      ,
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %*{"prep": prepRes.getStr()}
    )
    let ctx = newPfContext()
    discard waitFor node.internalRun(ctx)

  test "Node with post callback returns custom action":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %"result"
      ,
      post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
        return "custom_action"
    )
    let ctx = newPfContext()
    let action = waitFor node.internalRun(ctx)
    check action == "custom_action"

  test "Node chaining with >> operator":
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
    check node1.getNextNode("default") == node2

  test "Node with parameters":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["received_key"] = params["key"]
        ctx["received_num"] = params["num"]
        return %"done"
    )
    discard node.setParams(%*{"key": "value", "num": 42})
    let ctx = newPfContext()
    discard waitFor node.internalRun(ctx)
    check ctx["received_key"].getStr() == "value"
    check ctx["received_num"].getInt() == 42

  test "Node retry on failure":
    var attemptCount = 0
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        {.cast(gcsafe).}:
          attemptCount += 1
          if attemptCount < 3:
            raise newException(Exception, "Simulated failure")
        return %"success"
      ,
      maxRetries = 3,
      waitMs = 10
    )
    let ctx = newPfContext()
    let action = waitFor node.internalRun(ctx)
    check action == "default"
    check attemptCount == 3

  test "Node fallback on failure":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        raise newException(Exception, "Always fails")
      ,
      fallback = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, err: ref Exception): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["fallback_used"] = %true
        return %"fallback_result"
      ,
      maxRetries = 1
    )
    let ctx = newPfContext()
    discard waitFor node.internalRun(ctx)
    check ctx["fallback_used"].getBool() == true

  test "BatchNode processes items":
    let batchNode = newBatchNode(
      prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %[%1, %2, %3]  # Returns JArray
      ,
      execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %(item.getInt() * 2)
      ,
      post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
        ctx["results"] = execRes
        return "done"
    )
    let ctx = newPfContext()
    discard waitFor batchNode.internalRun(ctx)
    check ctx["results"][0].getInt() == 2
    check ctx["results"][1].getInt() == 4
    check ctx["results"][2].getInt() == 6

  test "ParallelBatchNode processes items concurrently":
    let parallelNode = newParallelBatchNode(
      prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %[%"a", %"b", %"c"]  # Returns JArray
      ,
      execItem = proc(ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %("processed_" & item.getStr())
      ,
      post = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async, closure, gcsafe.} =
        ctx["parallel_results"] = execRes
        return "completed"
      ,
      maxConcurrency = 2
    )
    let ctx = newPfContext()
    let action = waitFor parallelNode.internalRun(ctx)
    check action == "completed"
    let results = ctx["parallel_results"]
    check results.len == 3
