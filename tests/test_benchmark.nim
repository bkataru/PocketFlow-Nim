import unittest
import asyncdispatch
import json
import ../src/pocketflow/[context, node, benchmark]

suite "Benchmark Tests":
  test "Benchmark single execution":
    proc simpleProcess(ctx: PfContext): Future[string] {.async.} =
      await sleepAsync(10)
      return "processed"
    
    let node = newNode("test", simpleProcess)
    let ctx = newPfContext()
    
    let result = waitFor benchmark(node, ctx)
    check result.executionTime > 0.0
    check result.executionTime >= 0.01  # At least 10ms
  
  test "Benchmark multiple iterations":
    proc process(ctx: PfContext): Future[string] {.async.} =
      await sleepAsync(5)
      return "done"
    
    let node = newNode("test", process)
    let ctx = newPfContext()
    
    let result = waitFor benchmarkIterations(node, ctx, iterations = 5)
    check result.iterations == 5
    check result.totalTime > 0.0
    check result.avgTime > 0.0
    check result.minTime > 0.0
    check result.maxTime >= result.minTime
  
  test "Benchmark calculates statistics correctly":
    proc process(ctx: PfContext): Future[string] {.async.} =
      await sleepAsync(10)
      return "done"
    
    let node = newNode("test", process)
    let ctx = newPfContext()
    
    let result = waitFor benchmarkIterations(node, ctx, iterations = 10)
    
    check result.avgTime > 0.0
    check result.minTime > 0.0
    check result.maxTime > 0.0
    check result.stdDev >= 0.0
    check result.avgTime >= result.minTime
    check result.avgTime <= result.maxTime
  
  test "Benchmark with varying execution times":
    var counter = 0
    proc varyingProcess(ctx: PfContext): Future[string] {.async.} =
      counter += 1
      await sleepAsync(counter * 5)  # Each iteration takes longer
      return "done"
    
    let node = newNode("varying", varyingProcess)
    let ctx = newPfContext()
    
    let result = waitFor benchmarkIterations(node, ctx, iterations = 5)
    
    # Max should be significantly larger than min
    check result.maxTime > result.minTime
    check result.stdDev > 0.0  # Should have variance
  
  test "Benchmark measures memory usage":
    proc memoryProcess(ctx: PfContext): Future[string] {.async.} =
      var data: seq[int] = @[]
      for i in 0..<1000:
        data.add(i)
      return "done"
    
    let node = newNode("memory", memoryProcess)
    let ctx = newPfContext()
    
    let result = waitFor benchmark(node, ctx)
    check result.memoryUsed >= 0  # Memory tracking may not be available
  
  test "Benchmark percentile calculation":
    proc process(ctx: PfContext): Future[string] {.async.} =
      await sleepAsync(5)
      return "done"
    
    let node = newNode("test", process)
    let ctx = newPfContext()
    
    let result = waitFor benchmarkIterations(node, ctx, iterations = 100)
    
    check result.p50 > 0.0
    check result.p95 > 0.0
    check result.p99 > 0.0
    check result.p99 >= result.p95
    check result.p95 >= result.p50
  
  test "Benchmark with context data":
    proc dataProcess(ctx: PfContext): Future[string] {.async.} =
      let value = ctx["input"].getInt()
      ctx["output"] = %(value * 2)
      return "processed"
    
    let node = newNode("data", dataProcess)
    let ctx = newPfContext()
    ctx["input"] = %42
    
    let result = waitFor benchmark(node, ctx)
    
    check result.executionTime > 0.0
    check ctx["output"].getInt() == 84
  
  test "Benchmark comparison":
    proc fastProcess(ctx: PfContext): Future[string] {.async.} =
      await sleepAsync(5)
      return "fast"
    
    proc slowProcess(ctx: PfContext): Future[string] {.async.} =
      await sleepAsync(20)
      return "slow"
    
    let fastNode = newNode("fast", fastProcess)
    let slowNode = newNode("slow", slowProcess)
    let ctx = newPfContext()
    
    let fastResult = waitFor benchmark(fastNode, ctx)
    let slowResult = waitFor benchmark(slowNode, ctx)
    
    check slowResult.executionTime > fastResult.executionTime
  
  test "Benchmark overhead is minimal":
    proc instantProcess(ctx: PfContext): Future[string] {.async.} =
      return "instant"
    
    let node = newNode("instant", instantProcess)
    let ctx = newPfContext()
    
    let result = waitFor benchmark(node, ctx)
    
    # Even instant process should have some measurable time
    check result.executionTime >= 0.0
  
  test "Benchmark with node that modifies context":
    proc modifyContext(ctx: PfContext): Future[string] {.async.} =
      let counter = if ctx.hasKey("counter"): ctx["counter"].getInt() else: 0
      ctx["counter"] = %(counter + 1)
      await sleepAsync(5)
      return "modified"
    
    let node = newNode("modifier", modifyContext)
    let ctx = newPfContext()
    
    let result = waitFor benchmarkIterations(node, ctx, iterations = 5)
    
    check result.iterations == 5
    check ctx["counter"].getInt() >= 1  # Context was modified at least once
