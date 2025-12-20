import unittest
import asyncdispatch
import json
import ../src/pocketflow

suite "Advanced Nodes Tests":
  test "ConditionalNode with true condition":
    let conditionNode = newConditionalNode(
      condition = proc(ctx: PfContext, params: JsonNode): Future[bool] {.async, closure, gcsafe.} =
        return ctx["value"].getInt() > 10
      ,
      trueNode = newNode(
        exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
          ctx["result"] = %"took_true_branch"
          return %"done"
      ),
      falseNode = newNode(
        exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
          ctx["result"] = %"took_false_branch"
          return %"done"
      )
    )

    let ctx = newPfContext()
    ctx["value"] = %20  # > 10, so true branch
    discard waitFor conditionNode.internalRun(ctx)
    check ctx["result"].getStr() == "took_true_branch"

  test "ConditionalNode with false condition":
    let conditionNode = newConditionalNode(
      condition = proc(ctx: PfContext, params: JsonNode): Future[bool] {.async, closure, gcsafe.} =
        return ctx["value"].getInt() > 10
      ,
      trueNode = newNode(
        exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
          ctx["result"] = %"took_true_branch"
          return %"done"
      ),
      falseNode = newNode(
        exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
          ctx["result"] = %"took_false_branch"
          return %"done"
      )
    )

    let ctx = newPfContext()
    ctx["value"] = %5  # < 10, so false branch
    discard waitFor conditionNode.internalRun(ctx)
    check ctx["result"].getStr() == "took_false_branch"

  test "ConditionalNode with nil falseNode":
    let conditionNode = newConditionalNode(
      condition = proc(ctx: PfContext, params: JsonNode): Future[bool] {.async, closure, gcsafe.} =
        return false
      ,
      trueNode = newNode(
        exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
          ctx["executed"] = %true
          return %"done"
      ),
      falseNode = nil
    )

    let ctx = newPfContext()
    discard waitFor conditionNode.internalRun(ctx)
    # Should not have executed the true branch
    check ctx["executed"].kind == JNull

  test "LoopNode iterates over items":
    let loopNode = newLoopNode(
      items = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %[%1, %2, %3]
      ,
      body = newNode(
        exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
          # Current item is in __loop_item__
          let item = ctx["__loop_item__"]
          let current = if ctx.hasKey("sum"): ctx["sum"].getInt() else: 0
          ctx["sum"] = %(current + item.getInt())
          return %"continue"
      ),
      maxIterations = 10
    )

    let ctx = newPfContext()
    discard waitFor loopNode.internalRun(ctx)
    check ctx["sum"].getInt() == 6  # 1 + 2 + 3

  test "LoopNode respects maxIterations":
    var counter = 0
    let loopNode = newLoopNode(
      items = proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        # Return many items
        var arr = newJArray()
        for i in 0..99:
          arr.add(%i)
        return arr
      ,
      body = newNode(
        exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
          {.cast(gcsafe).}:
            counter += 1
          return %"continue"
      ),
      maxIterations = 5
    )

    let ctx = newPfContext()
    discard waitFor loopNode.internalRun(ctx)
    check counter == 5  # Should stop at maxIterations

  test "TimeoutNode completes within timeout":
    let timeoutNode = newTimeoutNode(
      innerNode = newNode(
        exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
          await sleepAsync(10)  # Short delay
          ctx["completed"] = %true
          return %"done"
      ),
      timeoutMs = 1000  # Long timeout
    )

    let ctx = newPfContext()
    discard waitFor timeoutNode.internalRun(ctx)
    check ctx["completed"].getBool() == true

  test "MapNode applies function to each item":
    let mapNode = newMapNode(
      mapFunc = proc(ctx: PfContext, item: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        return %(item.getInt() * 2)
      ,
      maxConcurrency = 0
    )

    # MapNode expects items in __map_items__ key
    let ctx = newPfContext()
    ctx["__map_items__"] = %[%1, %2, %3, %4, %5]

    discard waitFor mapNode.internalRun(ctx)

    let results = ctx["__map_results__"]
    check results.len == 5
    check results[0].getInt() == 2
    check results[1].getInt() == 4
    check results[2].getInt() == 6
    check results[3].getInt() == 8
    check results[4].getInt() == 10

  test "ConditionalNode can be chained":
    let trueNext = newNode(
      exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
        ctx["chained"] = %"yes"
        return %"end"
    )

    let conditionNode = newConditionalNode(
      condition = proc(ctx: PfContext, params: JsonNode): Future[bool] {.async, closure, gcsafe.} =
        return true
      ,
      trueNode = newNode(
        exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async, closure, gcsafe.} =
          ctx["condition_done"] = %true
          return %"done"
      )
    )

    discard conditionNode >> trueNext
    let flow = newFlow(conditionNode)

    let ctx = newPfContext()
    discard waitFor flow.internalRun(ctx)
    check ctx["condition_done"].getBool() == true
    check ctx["chained"].getStr() == "yes"
