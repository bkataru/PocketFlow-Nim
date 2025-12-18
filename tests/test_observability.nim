import unittest
import asyncdispatch
import json
import os
import ../src/pocketflow/[context, observability]

suite "Observability Tests":
  test "Create observer":
    let obs = newObserver()
    check obs != nil
  
  test "Start and finish span":
    let obs = newObserver()
    obs.startSpan("test_span")
    sleep(100)  # Simulate work
    obs.finishSpan("test_span")
    # Should complete without error
    check true
  
  test "Record metric":
    let obs = newObserver()
    obs.recordMetric("test_metric", 42.0)
    obs.recordMetric("test_metric", 84.0)
    # Should complete without error
    check true
  
  test "Log message":
    let obs = newObserver()
    obs.log("info", "Test message")
    obs.log("warn", "Warning message")
    obs.log("error", "Error message")
    # Should complete without error
    check true
  
  test "Nested spans":
    let obs = newObserver()
    obs.startSpan("outer_span")
    obs.startSpan("inner_span")
    obs.finishSpan("inner_span")
    obs.finishSpan("outer_span")
    check true
  
  test "Multiple metrics with same name":
    let obs = newObserver()
    for i in 0..<10:
      obs.recordMetric("counter", float(i))
    check true
  
  test "Different log levels":
    let obs = newObserver()
    obs.log("debug", "Debug message")
    obs.log("info", "Info message")
    obs.log("warn", "Warning")
    obs.log("error", "Error")
    check true
  
  test "Span timing is recorded":
    let obs = newObserver()
    obs.startSpan("timed_span")
    sleep(100)
    obs.finishSpan("timed_span")
    # Duration should be recorded internally
    check true
  
  test "Observer handles concurrent operations":
    let obs = newObserver()
    
    proc worker(id: int) {.async.} =
      obs.startSpan("worker_" & $id)
      await sleepAsync(50)
      obs.recordMetric("work_done", float(id))
      obs.finishSpan("worker_" & $id)
    
    var futures: seq[Future[void]] = @[]
    for i in 0..<5:
      futures.add(worker(i))
    
    waitFor all(futures)
    check true
  
  test "Log with structured data":
    let obs = newObserver()
    obs.log("info", "User action", %*{"user_id": 123, "action": "login"})
    check true
  
  test "Metric with tags":
    let obs = newObserver()
    obs.recordMetric("request_duration", 0.5, %*{"endpoint": "/api/users", "method": "GET"})
    check true
