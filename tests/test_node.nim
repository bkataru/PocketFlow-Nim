import unittest
import asyncdispatch
import json
import ../src/pocketflow

suite "Node Tests":
  test "Create simple node with exec callback":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        return %"executed"
    )
    check node != nil
  
  test "Run node and get result":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        return %42
    )
    let ctx = newPfContext()
    let result = waitFor node.internalRun(ctx)
    check result == "ok"
  
  test "Node can access context":
    let node = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        ctx["executed"] = %true
        return %"done"
    )
    let ctx = newPfContext()
    discard waitFor node.internalRun(ctx)
    check ctx["executed"].getBool() == true
  
  test "Node with prep callback":
    let node = newNode(
      prep = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
        return %"prepared"
      ,
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        check prepRes.getStr() == "prepared"
        return %"executed"
    )
    let ctx = newPfContext()
    discard waitFor node.internalRun(ctx)
