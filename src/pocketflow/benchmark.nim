## Performance benchmarking utilities
##
## Provides tools to measure and compare performance of nodes and flows.

import times, asyncdispatch, json, strformat, strutils, algorithm, math
import context, node, flow

type
  BenchmarkResult* = object
    name*: string
    iterations*: int
    totalTimeMs*: float
    avgTimeMs*: float
    minTimeMs*: float
    maxTimeMs*: float
    stdDevMs*: float
    throughput*: float  # ops/sec
  
  BenchmarkSuite* = ref object
    results*: seq[BenchmarkResult]

proc newBenchmarkSuite*(): BenchmarkSuite =
  result = BenchmarkSuite(results: @[])

proc benchmark*(
  suite: BenchmarkSuite,
  name: string,
  iterations: int,
  fn: proc(): Future[void] {.gcsafe.}
): Future[BenchmarkResult] {.async, gcsafe.} =
  ## Benchmarks an async function
  var times: seq[float] = @[]
  
  echo fmt"Running benchmark: {name} ({iterations} iterations)..."
  
  let startTotal = cpuTime()
  
  for i in 0..<iterations:
    let start = cpuTime()
    await fn()
    let duration = (cpuTime() - start) * 1000.0  # Convert to ms
    times.add(duration)
  
  let totalTime = (cpuTime() - startTotal) * 1000.0
  
  # Calculate statistics
  times.sort()
  let minTime = times[0]
  let maxTime = times[^1]
  
  var sumTime = 0.0
  for t in times:
    sumTime += t
  let avgTime = sumTime / float(times.len)
  
  # Standard deviation
  var variance = 0.0
  for t in times:
    let diff = t - avgTime
    variance += diff * diff
  variance /= float(times.len)
  let stdDev = sqrt(variance)
  
  let throughput = float(iterations) / (totalTime / 1000.0)
  
  result = BenchmarkResult(
    name: name,
    iterations: iterations,
    totalTimeMs: totalTime,
    avgTimeMs: avgTime,
    minTimeMs: minTime,
    maxTimeMs: maxTime,
    stdDevMs: stdDev,
    throughput: throughput
  )
  
  suite.results.add(result)
  
  echo fmt"  Completed: avg={avgTime:.2f}ms, min={minTime:.2f}ms, max={maxTime:.2f}ms, throughput={throughput:.0f} ops/sec"

proc benchmarkNode*(
  suite: BenchmarkSuite,
  name: string,
  node: BaseNode,
  iterations: int = 100
): Future[BenchmarkResult] {.async, gcsafe.} =
  ## Benchmarks a node execution
  let ctx = newPfContext()
  
  return await suite.benchmark(name, iterations, proc(): Future[void] {.async, gcsafe.} =
    discard await node.internalRun(ctx)
  )

proc benchmarkFlow*(
  suite: BenchmarkSuite,
  name: string,
  flow: Flow,
  iterations: int = 100
): Future[BenchmarkResult] {.async, gcsafe.} =
  ## Benchmarks a flow execution
  return await suite.benchmark(name, iterations, proc(): Future[void] {.async, gcsafe.} =
    let ctx = newPfContext()
    discard await flow.internalRun(ctx)
  )

proc printSummary*(suite: BenchmarkSuite) =
  ## Prints a formatted summary of all benchmarks
  echo "\n" & "=" .repeat(80)
  echo "BENCHMARK SUMMARY"
  echo "=" .repeat(80)
  
  let nameWidth = 30
  echo "Benchmark".alignLeft(nameWidth) & " " &
       "Iterations".align(10) & " " &
       "Avg (ms)".align(12) & " " &
       "Min (ms)".align(12) & " " &
       "Max (ms)".align(12) & " " &
       "Ops/sec".align(12)
  echo "-" .repeat(80)
  
  for result in suite.results:
    echo result.name.alignLeft(nameWidth) & " " &
         ($result.iterations).align(10) & " " &
         formatFloat(result.avgTimeMs, ffDecimal, 2).align(12) & " " &
         formatFloat(result.minTimeMs, ffDecimal, 2).align(12) & " " &
         formatFloat(result.maxTimeMs, ffDecimal, 2).align(12) & " " &
         formatFloat(result.throughput, ffDecimal, 0).align(12)
  
  echo "=" .repeat(80)

proc toJson*(suite: BenchmarkSuite): JsonNode =
  ## Converts benchmark results to JSON
  result = newJArray()
  for res in suite.results:
    result.add(%*{
      "name": res.name,
      "iterations": res.iterations,
      "total_time_ms": res.totalTimeMs,
      "avg_time_ms": res.avgTimeMs,
      "min_time_ms": res.minTimeMs,
      "max_time_ms": res.maxTimeMs,
      "std_dev_ms": res.stdDevMs,
      "throughput_ops_sec": res.throughput
    })

proc compare*(suite: BenchmarkSuite, baseline: string) =
  ## Compares all benchmarks to a baseline
  var baselineResult: BenchmarkResult
  var found = false
  
  for result in suite.results:
    if result.name == baseline:
      baselineResult = result
      found = true
      break
  
  if not found:
    echo fmt"Baseline '{baseline}' not found"
    return
  
  echo "\n" & "=" .repeat(80)
  echo fmt"COMPARISON TO BASELINE: {baseline}"
  echo "=" .repeat(80)
  
  for result in suite.results:
    if result.name == baseline:
      continue
    
    let ratio = result.avgTimeMs / baselineResult.avgTimeMs
    let percentDiff = (ratio - 1.0) * 100.0
    
    let symbol = if percentDiff < 0: "✓" else: "✗"
    let sign = if percentDiff >= 0: "+" else: ""
    
    echo fmt"{symbol} {result.name}: {sign}{percentDiff:.1f}% ({ratio:.2f}x)"
  
  echo "=" .repeat(80)
