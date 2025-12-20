import unittest
import json
import times
import ../src/pocketflow/observability

suite "Observability Tests":
  test "Create span":
    let span = newSpan("test_operation")
    check span.name == "test_operation"
    # startTime should be set (non-zero)
    check span.startTime != Time()

  test "Finish span sets end time":
    let span = newSpan("test_span")
    # Do some work
    var sum = 0
    for i in 0..1000:
      sum += i
    finish(span)
    # endTime should be >= startTime
    check span.endTime >= span.startTime

  test "Get span duration":
    let span = newSpan("duration_test")
    # Small delay
    for i in 0..100000:
      discard i * 2
    finish(span)
    let duration = getDurationMs(span)
    check duration >= 0.0

  test "Record metric":
    # Record some metrics
    recordMetric("request_count", 1.0)
    recordMetric("request_count", 1.0)
    recordMetric("response_time_ms", 150.5)
    recordMetric("response_time_ms", 200.0)
    recordMetric("error_count", 0.0, [("service", "api")])

    # No exception means success
    check true

  test "Get metrics summary":
    # Record some metrics first
    recordMetric("test_metric", 10.0)
    recordMetric("test_metric", 20.0)
    recordMetric("test_metric", 30.0)

    let summary = getMetricsSummary()
    check summary.kind == JObject

  test "Log structured message":
    logStructured(Info, "Test message", [("key", "value")])
    logStructured(Debug, "Debug message")
    logStructured(Error, "Error occurred", [("error_code", "500")])

    # No exception means success
    check true

  test "Log levels":
    logStructured(Debug, "Debug level message")
    logStructured(Info, "Info level message")
    logStructured(Warn, "Warning level message")
    logStructured(Error, "Error level message")

    check true

  test "Span name is preserved":
    let span = newSpan("custom_operation_name")
    check span.name == "custom_operation_name"
    finish(span)

  test "Multiple spans can be created":
    let span1 = newSpan("operation_1")
    let span2 = newSpan("operation_2")
    let span3 = newSpan("operation_3")

    check span1.name == "operation_1"
    check span2.name == "operation_2"
    check span3.name == "operation_3"

    finish(span1)
    finish(span2)
    finish(span3)

  test "Metric with tags":
    recordMetric("http_requests", 100.0, [("method", "GET"), ("path", "/api")])
    recordMetric("http_requests", 50.0, [("method", "POST"), ("path", "/api")])

    check true
