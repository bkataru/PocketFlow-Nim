import unittest
import strutils
import ../src/pocketflow/errors

suite "PocketFlow Error Tests":
  test "PocketFlowError creation":
    let err = newPocketFlowError("Test error")
    check err.msg == "Test error"
  
  test "NodeExecutionError creation":
    let err = newNodeExecutionError("Execution failed", "Test node")
    check err.msg.contains("Execution failed")
    check err.nodeName == "Test node"
  
  test "LLMError creation":
    let err = newLLMError("API error", "openai")
    check err.msg.contains("API error")
    check err.provider == "openai"
  
  test "CacheError creation":
    let err = newCacheError("Cache miss")
    check err.msg == "Cache miss"
  
  test "RAGError creation":
    let err = newRAGError("Embedding failed")
    check err.msg == "Embedding failed"
  
  test "PersistenceError creation":
    let err = newPersistenceError("Save failed")
    check err.msg == "Save failed"
  
  test "Error messages are descriptive":
    let nodeErr = newNodeExecutionError("Division by zero", "TestNode")
    check nodeErr.msg != ""
    check nodeErr.msg.len > 0
    check nodeErr.nodeName == "TestNode"
