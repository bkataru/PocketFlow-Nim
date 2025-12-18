import unittest
import asyncdispatch
import json
import os
import ../src/pocketflow/[context, node, flow, llm, rag, advanced_nodes, persistence, observability]

suite "Integration Tests - Complete Flows":
  test "Simple chat flow":
    proc preparePrompt(ctx: PfContext): Future[string] {.async.} =
      let userInput = ctx["user_input"].getStr()
      ctx["prompt"] = %("User says: " & userInput)
      return "prepared"
    
    proc respond(ctx: PfContext): Future[string] {.async.} =
      let prompt = ctx["prompt"].getStr()
      ctx["response"] = %("Echo: " & prompt)
      return "responded"
    
    let flow = newFlow("chat_flow")
    flow.addNode(newNode("prepare", preparePrompt))
    flow.addNode(newNode("respond", respond))
    
    let ctx = newPfContext()
    ctx["user_input"] = %"Hello!"
    
    discard waitFor flow.run(ctx)
    
    check ctx["response"].getStr().contains("Hello!")
  
  test "Multi-step data processing pipeline":
    proc loadData(ctx: PfContext): Future[string] {.async.} =
      ctx["data"] = %[1, 2, 3, 4, 5]
      return "loaded"
    
    proc filterData(ctx: PfContext): Future[string] {.async.} =
      var filtered = newJArray()
      for item in ctx["data"]:
        if item.getInt() > 2:
          filtered.add(item)
      ctx["filtered"] = filtered
      return "filtered"
    
    proc aggregateData(ctx: PfContext): Future[string] {.async.} =
      var sum = 0
      for item in ctx["filtered"]:
        sum += item.getInt()
      ctx["sum"] = %sum
      return "aggregated"
    
    let flow = newFlow("pipeline")
    flow.addNode(newNode("load", loadData))
    flow.addNode(newNode("filter", filterData))
    flow.addNode(newNode("aggregate", aggregateData))
    
    let ctx = newPfContext()
    discard waitFor flow.run(ctx)
    
    check ctx["sum"].getInt() == 12  # 3 + 4 + 5
  
  test "Conditional flow with branching":
    proc checkValue(ctx: PfContext): Future[string] {.async.} =
      ctx["value"] = %15
      return "checked"
    
    proc condition(ctx: PfContext): bool =
      return ctx["value"].getInt() > 10
    
    proc handleLarge(ctx: PfContext): Future[string] {.async.} =
      ctx["category"] = %"large"
      return "categorized"
    
    proc handleSmall(ctx: PfContext): Future[string] {.async.} =
      ctx["category"] = %"small"
      return "categorized"
    
    let flow = newFlow("conditional_flow")
    flow.addNode(newNode("check", checkValue))
    flow.addNode(newConditionalNode(
      "categorize",
      condition,
      newNode("large", handleLarge),
      newNode("small", handleSmall)
    ))
    
    let ctx = newPfContext()
    discard waitFor flow.run(ctx)
    
    check ctx["category"].getStr() == "large"
  
  test "Loop-based accumulator flow":
    proc initLoop(ctx: PfContext): Future[string] {.async.} =
      ctx["iterations"] = %5
      ctx["sum"] = %0
      return "initialized"
    
    proc getIterations(ctx: PfContext): int =
      return ctx["iterations"].getInt()
    
    proc accumulate(ctx: PfContext): Future[string] {.async.} =
      let current = ctx["sum"].getInt()
      ctx["sum"] = %(current + 10)
      return "accumulated"
    
    let flow = newFlow("accumulator_flow")
    flow.addNode(newNode("init", initLoop))
    flow.addNode(newLoopNode("loop", getIterations, newNode("add", accumulate)))
    
    let ctx = newPfContext()
    discard waitFor flow.run(ctx)
    
    check ctx["sum"].getInt() == 50
  
  test "Parallel batch processing flow":
    proc processItem(ctx: PfContext): Future[string] {.async.} =
      let value = ctx["item"].getInt()
      await sleepAsync(10)  # Simulate processing time
      ctx["result"] = %(value * 2)
      return "processed"
    
    let flow = newParallelBatchFlow("batch_flow", maxConcurrent = 3)
    flow.addNode(newMapNode("process", "items", newNode("processor", processItem)))
    
    let ctx = newPfContext()
    ctx["items"] = %[1, 2, 3, 4, 5]
    
    import times
    let startTime = cpuTime()
    discard waitFor flow.run(ctx)
    let duration = cpuTime() - startTime
    
    check ctx.hasKey("results")
    check ctx["results"].len == 5
    # Parallel processing should be faster than sequential (5 * 10ms = 50ms)
    check duration < 0.04  # Should complete in less than 40ms with parallelism
  
  test "Flow with persistence checkpointing":
    proc step1(ctx: PfContext): Future[string] {.async.} =
      ctx["step1_done"] = %true
      return "step1"
    
    proc step2(ctx: PfContext): Future[string] {.async.} =
      ctx["step2_done"] = %true
      return "step2"
    
    let flow = newFlow("checkpoint_flow")
    flow.addNode(newNode("step1", step1))
    flow.addNode(newNode("step2", step2))
    
    let ctx = newPfContext()
    discard waitFor flow.run(ctx)
    
    # Save checkpoint
    saveState(ctx, "test_checkpoint.json")
    
    # Load and verify
    let loaded = loadState("test_checkpoint.json")
    check loaded["step1_done"].getBool() == true
    check loaded["step2_done"].getBool() == true
    
    # Cleanup
    if fileExists("test_checkpoint.json"):
      removeFile("test_checkpoint.json")
  
  test "Flow with observability":
    let observer = newObserver()
    
    proc trackedProcess(ctx: PfContext): Future[string] {.async.} =
      observer.startSpan("processing")
      await sleepAsync(10)
      observer.recordMetric("items_processed", 1.0)
      observer.finishSpan("processing")
      ctx["processed"] = %true
      return "done"
    
    let flow = newFlow("observed_flow")
    flow.addNode(newNode("process", trackedProcess))
    
    let ctx = newPfContext()
    observer.startSpan("flow_execution")
    discard waitFor flow.run(ctx)
    observer.finishSpan("flow_execution")
    
    check ctx["processed"].getBool() == true
  
  test "RAG-based flow":
    proc loadDocuments(ctx: PfContext): Future[string] {.async.} =
      ctx["documents"] = %[
        "The sky is blue.",
        "Grass is green.",
        "The sun is bright.",
        "Water is wet."
      ]
      return "loaded"
    
    proc createChunks(ctx: PfContext): Future[string] {.async.} =
      var chunks = newJArray()
      for doc in ctx["documents"]:
        let chunk = %*{
          "text": doc.getStr(),
          "embedding": createEmbeddings(doc.getStr())
        }
        chunks.add(chunk)
      ctx["chunks"] = chunks
      return "chunked"
    
    proc query(ctx: PfContext): Future[string] {.async.} =
      ctx["query"] = %"What color is the sky?"
      return "queried"
    
    let flow = newFlow("rag_flow")
    flow.addNode(newNode("load", loadDocuments))
    flow.addNode(newNode("chunk", createChunks))
    flow.addNode(newNode("query", query))
    
    let ctx = newPfContext()
    discard waitFor flow.run(ctx)
    
    check ctx.hasKey("chunks")
    check ctx["chunks"].len == 4
  
  test "Error recovery flow":
    var attemptCount = 0
    
    proc unreliableProcess(ctx: PfContext): Future[string] {.async.} =
      attemptCount += 1
      if attemptCount < 3:
        raise newNodeExecutionError("unreliable", "Failed attempt " & $attemptCount)
      ctx["success"] = %true
      return "succeeded"
    
    proc retryLoop(ctx: PfContext): int =
      return 3
    
    let flow = newFlow("retry_flow")
    flow.addNode(newLoopNode("retry", retryLoop, newNode("process", unreliableProcess)))
    
    let ctx = newPfContext()
    
    # Should eventually succeed after retries
    var succeeded = false
    try:
      discard waitFor flow.run(ctx)
      succeeded = ctx.hasKey("success") and ctx["success"].getBool()
    except NodeExecutionError:
      discard
    
    check succeeded or attemptCount == 3
  
  test "Complex multi-stage flow with all features":
    # Initialize
    proc init(ctx: PfContext): Future[string] {.async.} =
      ctx["data"] = %[10, 20, 30, 40, 50]
      ctx["threshold"] = %25
      return "initialized"
    
    # Filter based on condition
    proc condition(ctx: PfContext): bool =
      return ctx.hasKey("filtered")
    
    proc filterData(ctx: PfContext): Future[string] {.async.} =
      let threshold = ctx["threshold"].getInt()
      var filtered = newJArray()
      for item in ctx["data"]:
        if item.getInt() > threshold:
          filtered.add(item)
      ctx["filtered"] = filtered
      return "filtered"
    
    proc skipFilter(ctx: PfContext): Future[string] {.async.} =
      ctx["filtered"] = ctx["data"]
      return "skipped"
    
    # Process each item
    proc processItem(ctx: PfContext): Future[string] {.async.} =
      let value = ctx["item"].getInt()
      ctx["result"] = %(value * 2)
      return "processed"
    
    # Aggregate
    proc aggregate(ctx: PfContext): Future[string] {.async.} =
      var sum = 0
      if ctx.hasKey("results"):
        for result in ctx["results"]:
          sum += result["result"].getInt()
      ctx["total"] = %sum
      return "aggregated"
    
    let flow = newFlow("complex_flow")
    flow.addNode(newNode("init", init))
    flow.addNode(newConditionalNode(
      "filter_check",
      condition,
      newNode("skip", skipFilter),
      newNode("filter", filterData)
    ))
    flow.addNode(newMapNode("process", "filtered", newNode("processor", processItem)))
    flow.addNode(newNode("aggregate", aggregate))
    
    let ctx = newPfContext()
    discard waitFor flow.run(ctx)
    
    check ctx.hasKey("total")
    check ctx["total"].getInt() > 0
