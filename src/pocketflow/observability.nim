## Observability module for PocketFlow
##
## Provides structured logging, metrics, and tracing capabilities.

import times, json, tables, strformat

type
  LogLevel* = enum
    ## Log severity levels
    Debug, Info, Warn, Error, Fatal
  
  Metric* = object
    ## A metric measurement
    name*: string
    value*: float
    tags*: TableRef[string, string]
    timestamp*: Time
  
  Span* = ref object
    ## A tracing span for measuring operation duration
    name*: string
    startTime*: Time
    endTime*: Time
    tags*: TableRef[string, string]
    metrics*: seq[Metric]
    children*: seq[Span]
  
  Observer* = ref object
    ## Main observability handler
    metrics*: seq[Metric]
    spans*: seq[Span]
    currentSpan*: Span

var globalObserver* = Observer(
  metrics: @[],
  spans: @[],
  currentSpan: nil
)

proc newSpan*(name: string): Span =
  ## Creates a new tracing span
  result = Span(
    name: name,
    startTime: getTime(),
    tags: newTable[string, string](),
    metrics: @[],
    children: @[]
  )

proc finish*(span: Span) =
  ## Finishes a span and records its duration
  span.endTime = getTime()
  globalObserver.spans.add(span)

proc recordMetric*(name: string, value: float, tags: openArray[(string, string)] = []) =
  ## Records a metric measurement
  var tagTable = newTable[string, string]()
  for (k, v) in tags:
    tagTable[k] = v
  
  let metric = Metric(
    name: name,
    value: value,
    tags: tagTable,
    timestamp: getTime()
  )
  globalObserver.metrics.add(metric)

proc logStructured*(level: LogLevel, message: string, fields: openArray[(string, string)] = []) =
  ## Logs a structured message with additional fields
  var fieldStr = ""
  for (k, v) in fields:
    fieldStr &= fmt" {k}={v}"
  
  let levelStr = $level
  echo fmt"[{levelStr}] {message}{fieldStr}"

proc getMetricsSummary*(): JsonNode =
  ## Returns a JSON summary of all recorded metrics
  result = newJObject()
  var byName = newTable[string, seq[float]]()
  
  for metric in globalObserver.metrics:
    if not byName.hasKey(metric.name):
      byName[metric.name] = @[]
    byName[metric.name].add(metric.value)
  
  for name, values in byName:
    var sum = 0.0
    for v in values:
      sum += v
    let avg = sum / float(values.len)
    result[name] = %*{
      "count": values.len,
      "average": avg,
      "sum": sum
    }

proc getDurationMs*(span: Span): float =
  ## Gets the duration of a span in milliseconds
  if span.endTime == Time():
    return 0.0
  let duration = span.endTime - span.startTime
  return float(duration.inMilliseconds)

template withSpan*(name: string, body: untyped) =
  ## Template for automatic span management
  let span = newSpan(name)
  try:
    body
  finally:
    {.cast(gcsafe).}:
      span.finish()
