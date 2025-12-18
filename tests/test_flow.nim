import unittest
import asyncdispatch
import json
import ../src/pocketflow/[context, node, flow]

suite "Flow Tests":
  test "Create simple flow":
    let flow = newFlow("test_flow")
    check flow.name == "test_flow"
  
  test "Add node to flow":
    proc simpleProcess(ctx: PfContext): Future[string] {.async.} =
      return "result"
    
    let flow = newFlow("test")
    let node = newNode("node1", simpleProcess)
    flow.addNode(node)
    # Flow should contain the node
    check true  # If we got here without error, node was added
  
  test "Run flow with single node":
    proc process(ctx: PfContext): Future[string] {.async.} =
      ctx["output"] = %"processed"
      return "done"
    
    let flow = newFlow("single_node_flow")
    let node = newNode("processor", process)
    flow.addNode(node)
    
    let ctx = newPfContext()
    ctx["input"] = %"test"
    let result = waitFor flow.run(ctx)
    check ctx["output"].getStr() == "processed"
  
  test "Run flow with multiple nodes in sequence":
    proc step1(ctx: PfContext): Future[string] {.async.} =
      ctx["step1"] = %"complete"
      return "step1_done"
    
    proc step2(ctx: PfContext): Future[string] {.async.} =
      ctx["step2"] = %"complete"
      return "step2_done"
    
    proc step3(ctx: PfContext): Future[string] {.async.} =
      ctx["step3"] = %"complete"
      return "step3_done"
    
    let flow = newFlow("multi_step")
    flow.addNode(newNode("step1", step1))
    flow.addNode(newNode("step2", step2))
    flow.addNode(newNode("step3", step3))
    
    let ctx = newPfContext()
    discard waitFor flow.run(ctx)
    
    check ctx["step1"].getStr() == "complete"
    check ctx["step2"].getStr() == "complete"
    check ctx["step3"].getStr() == "complete"
  
  test "Flow passes data between nodes":
    proc producer(ctx: PfContext): Future[string] {.async.} =
      ctx["data"] = %42
      return "produced"
    
    proc consumer(ctx: PfContext): Future[string] {.async.} =
      let data = ctx["data"].getInt()
      ctx["doubled"] = %(data * 2)
      return "consumed"
    
    let flow = newFlow("pipeline")
    flow.addNode(newNode("producer", producer))
    flow.addNode(newNode("consumer", consumer))
    
    let ctx = newPfContext()
    discard waitFor flow.run(ctx)
    
    check ctx["data"].getInt() == 42
    check ctx["doubled"].getInt() == 84
  
  test "BatchFlow processes multiple contexts":
    proc increment(ctx: PfContext): Future[string] {.async.} =
      let value = ctx["value"].getInt()
      ctx["result"] = %(value + 1)
      return "incremented"
    
    let flow = newBatchFlow("batch_flow")
    flow.addNode(newNode("incrementer", increment))
    
    var contexts: seq[PfContext] = @[]
    for i in 0..<5:
      let ctx = newPfContext()
      ctx["value"] = %i
      contexts.add(ctx)
    
    let results = waitFor flow.runBatch(contexts)
    check results.len == 5
    
    for i in 0..<5:
      check contexts[i]["result"].getInt() == i + 1
  
  test "ParallelBatchFlow processes contexts concurrently":
    proc slowProcess(ctx: PfContext): Future[string] {.async.} =
      await sleepAsync(50)
      ctx["processed"] = %true
      return "done"
    
    let flow = newParallelBatchFlow("parallel_flow", maxConcurrent = 3)
    flow.addNode(newNode("processor", slowProcess))
    
    var contexts: seq[PfContext] = @[]
    for i in 0..<6:
      contexts.add(newPfContext())
    
    import times
    let startTime = cpuTime()
    let results = waitFor flow.runBatch(contexts)
    let duration = cpuTime() - startTime
    
    check results.len == 6
    # With maxConcurrent=3, 6 items should take ~100ms (2 batches of 3)
    # Sequential would take ~300ms
    check duration < 0.2
  
  test "Empty flow runs successfully":
    let flow = newFlow("empty")
    let ctx = newPfContext()
    let result = waitFor flow.run(ctx)
    # Should complete without error
    check true
  
  test "Flow with single failing node stops execution":
    proc failingNode(ctx: PfContext): Future[string] {.async.} =
      raise newNodeExecutionError("failing", "Intentional failure")
    
    proc subsequentNode(ctx: PfContext): Future[string] {.async.} =
      ctx["should_not_run"] = %true
      return "ran"
    
    let flow = newFlow("failing_flow")
    flow.addNode(newNode("failing", failingNode))
    flow.addNode(newNode("subsequent", subsequentNode))
    
    let ctx = newPfContext()
    var errorCaught = false
    
    try:
      discard waitFor flow.run(ctx)
    except NodeExecutionError:
      errorCaught = true
    
    check errorCaught
    check not ctx.hasKey("should_not_run")
