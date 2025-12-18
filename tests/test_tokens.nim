import unittest
import json
import ../src/pocketflow/tokens

suite "Token Tests":
  test "Estimate tokens in simple text":
    let count = estimateTokens("Hello world")
    check count > 0
    check count < 10
  
  test "Estimate tokens in empty string":
    let count = estimateTokens("")
    check count >= 0
  
  test "Estimate tokens in longer text":
    let text = "This is a longer sentence with multiple words."
    let count = estimateTokens(text)
    check count > 5
  
  test "Create cost tracker":
    let tracker = newCostTracker()
    check tracker != nil
  
  test "Track usage for GPT-3.5":
    let tracker = newCostTracker()
    tracker.trackUsage("gpt-3.5-turbo", 1000, 500)
    let summary = tracker.getSummary()
    check summary.hasKey("total_cost_usd")
    check summary["total_cost_usd"].getFloat() > 0.0
  
  test "Track usage for GPT-4":
    let tracker = newCostTracker()
    tracker.trackUsage("gpt-4", 1000, 500)
    let summary = tracker.getSummary()
    check summary["total_cost_usd"].getFloat() > 0.0
  
  test "Track multiple requests":
    let tracker = newCostTracker()
    tracker.trackUsage("gpt-3.5-turbo", 1000, 500)
    tracker.trackUsage("gpt-3.5-turbo", 2000, 1000)
    let summary = tracker.getSummary()
    check summary.hasKey("total_input_tokens")
    check summary["total_input_tokens"].getInt() == 3000
  
  test "Reset tracker":
    let tracker = newCostTracker()
    tracker.trackUsage("gpt-3.5-turbo", 1000, 500)
    tracker.reset()
    let summary = tracker.getSummary()
    check summary["total_cost_usd"].getFloat() == 0.0
  
  test "Token estimation is consistent":
    let text = "The quick brown fox"
    let count1 = estimateTokens(text)
    let count2 = estimateTokens(text)
    check count1 == count2
