import unittest
import asyncdispatch
import json
import ../src/pocketflow/[context, node, advanced_nodes]

suite "Advanced Nodes Tests":
  test "ConditionalNode executes true branch":
    proc condition(ctx: PfContext): bool =
      return ctx["value"].getInt() > 10
    
    proc trueBranch(ctx: PfContext): Future[string] {.async.} =
      ctx["result"] = %"true_executed"
      return "true"
    
    proc falseBranch(ctx: PfContext): Future[string] {.async.} =
      ctx["result"] = %"false_executed"
      return "false"
    
    let node = newConditionalNode(
      "conditional",
      condition,
      newNode("true", trueBranch),
      newNode("false", falseBranch)
    )
    
    let ctx = newPfContext()
    ctx["value"] = %15
    let result = waitFor node.run(ctx)
    check ctx["result"].getStr() == "true_executed"
  
  test "ConditionalNode executes false branch":
    proc condition(ctx: PfContext): bool =
      return ctx["value"].getInt() > 10
    
    proc trueBranch(ctx: PfContext): Future[string] {.async.} =
      ctx["result"] = %"true_executed"
      return "true"
    
    proc falseBranch(ctx: PfContext): Future[string] {.async.} =
      ctx["result"] = %"false_executed"
      return "false"
    
    let node = newConditionalNode(
      "conditional",
      condition,
      newNode("true", trueBranch),
      newNode("false", falseBranch)
    )
    
    let ctx = newPfContext()
    ctx["value"] = %5
    let result = waitFor node.run(ctx)
    check ctx["result"].getStr() == "false_executed"
  
  test "LoopNode iterates correct number of times":
    proc getIterations(ctx: PfContext): int =
      return ctx["iterations"].getInt()
    
    proc loopBody(ctx: PfContext): Future[string] {.async.} =
      let current = if ctx.hasKey("counter"): ctx["counter"].getInt() else: 0
      ctx["counter"] = %(current + 1)
      return "looped"
    
    let node = newLoopNode("loop", getIterations, newNode("body", loopBody))
    
    let ctx = newPfContext()
    ctx["iterations"] = %5
    let result = waitFor node.run(ctx)
    check ctx["counter"].getInt() == 5
  
  test "LoopNode with zero iterations":
    proc getIterations(ctx: PfContext): int =
      return 0
    
    proc loopBody(ctx: PfContext): Future[string] {.async.} =
      ctx["executed"] = %true
      return "looped"
    
    let node = newLoopNode("loop", getIterations, newNode("body", loopBody))
    
    let ctx = newPfContext()
    let result = waitFor node.run(ctx)
    check not ctx.hasKey("executed")
  
  test "TimeoutNode completes within timeout":
    proc quickProcess(ctx: PfContext): Future[string] {.async.} =
      await sleepAsync(50)
      ctx["completed"] = %true
      return "done"
    
    let node = newTimeoutNode("timeout", newNode("quick", quickProcess), timeout = 200)
    
    let ctx = newPfContext()
    let result = waitFor node.run(ctx)
    check ctx["completed"].getBool() == true
  
  test "TimeoutNode raises error on timeout":
    proc slowProcess(ctx: PfContext): Future[string] {.async.} =
      await sleepAsync(500)
      ctx["completed"] = %true
      return "done"
    
    let node = newTimeoutNode("timeout", newNode("slow", slowProcess), timeout = 100)
    
    let ctx = newPfContext()
    var timedOut = false
    
    try:
      discard waitFor node.run(ctx)
    except NodeExecutionError:
      timedOut = true
    
    check timedOut
    check not ctx.hasKey("completed")
  
  test "MapNode processes array of items":
    proc doubleValue(ctx: PfContext): Future[string] {.async.} =
      let value = ctx["item"].getInt()
      ctx["result"] = %(value * 2)
      return "doubled"
    
    let node = newMapNode("map", "items", newNode("doubler", doubleValue))
    
    let ctx = newPfContext()
    ctx["items"] = %[1, 2, 3, 4, 5]
    let result = waitFor node.run(ctx)
    
    check ctx.hasKey("results")
    let results = ctx["results"]
    check results.len == 5
    check results[0]["result"].getInt() == 2
    check results[1]["result"].getInt() == 4
    check results[2]["result"].getInt() == 6
  
  test "MapNode with empty array":
    proc process(ctx: PfContext): Future[string] {.async.} =
      return "processed"
    
    let node = newMapNode("map", "items", newNode("processor", process))
    
    let ctx = newPfContext()
    ctx["items"] = newJArray()
    let result = waitFor node.run(ctx)
    
    check ctx.hasKey("results")
    check ctx["results"].len == 0
  
  test "LoopNode accumulates values":
    proc getIterations(ctx: PfContext): int =
      return 3
    
    proc accumulate(ctx: PfContext): Future[string] {.async.} =
      let current = if ctx.hasKey("sum"): ctx["sum"].getInt() else: 0
      ctx["sum"] = %(current + 10)
      return "accumulated"
    
    let node = newLoopNode("loop", getIterations, newNode("accumulator", accumulate))
    
    let ctx = newPfContext()
    let result = waitFor node.run(ctx)
    check ctx["sum"].getInt() == 30
  
  test "Nested conditional in loop":
    proc getIterations(ctx: PfContext): int =
      return 5
    
    proc condition(ctx: PfContext): bool =
      let i = if ctx.hasKey("iteration"): ctx["iteration"].getInt() else: 0
      return i mod 2 == 0
    
    proc evenProc(ctx: PfContext): Future[string] {.async.} =
      let count = if ctx.hasKey("even_count"): ctx["even_count"].getInt() else: 0
      ctx["even_count"] = %(count + 1)
      return "even"
    
    proc oddProc(ctx: PfContext): Future[string] {.async.} =
      let count = if ctx.hasKey("odd_count"): ctx["odd_count"].getInt() else: 0
      ctx["odd_count"] = %(count + 1)
      return "odd"
    
    proc loopBody(ctx: PfContext): Future[string] {.async.} =
      let i = if ctx.hasKey("iteration"): ctx["iteration"].getInt() else: 0
      ctx["iteration"] = %(i + 1)
      
      let conditional = newConditionalNode(
        "check_even",
        condition,
        newNode("even", evenProc),
        newNode("odd", oddProc)
      )
      return await conditional.run(ctx)
    
    let node = newLoopNode("loop", getIterations, newNode("body", loopBody))
    
    let ctx = newPfContext()
    let result = waitFor node.run(ctx)
    
    # Should have 3 even (0, 2, 4) and 2 odd (1, 3)
    check ctx["even_count"].getInt() == 3
    check ctx["odd_count"].getInt() == 2
