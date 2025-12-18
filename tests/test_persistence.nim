import unittest
import json
import os
import ../src/pocketflow/[context, persistence]

suite "Persistence Tests":
  setup:
    # Clean up any test files before each test
    if fileExists("test_state.json"):
      removeFile("test_state.json")
  
  teardown:
    # Clean up test files after each test
    if fileExists("test_state.json"):
      removeFile("test_state.json")
  
  test "Save context to file":
    let ctx = newPfContext()
    ctx["name"] = %"Alice"
    ctx["age"] = %30
    ctx["active"] = %true
    
    saveState(ctx, "test_state.json")
    check fileExists("test_state.json")
  
  test "Load context from file":
    let ctx = newPfContext()
    ctx["name"] = %"Bob"
    ctx["score"] = %100
    
    saveState(ctx, "test_state.json")
    
    let loaded = loadState("test_state.json")
    check loaded["name"].getStr() == "Bob"
    check loaded["score"].getInt() == 100
  
  test "Save and load complex nested data":
    let ctx = newPfContext()
    ctx["user"] = %*{
      "name": "Charlie",
      "age": 25,
      "tags": ["developer", "tester"],
      "metadata": {
        "created": "2024-01-01",
        "active": true
      }
    }
    
    saveState(ctx, "test_state.json")
    let loaded = loadState("test_state.json")
    
    check loaded["user"]["name"].getStr() == "Charlie"
    check loaded["user"]["age"].getInt() == 25
    check loaded["user"]["tags"].len == 2
    check loaded["user"]["metadata"]["active"].getBool() == true
  
  test "Load non-existent file raises error":
    var errorCaught = false
    try:
      discard loadState("non_existent.json")
    except PersistenceError:
      errorCaught = true
    
    check errorCaught
  
  test "Save overwrites existing file":
    let ctx1 = newPfContext()
    ctx1["version"] = %1
    saveState(ctx1, "test_state.json")
    
    let ctx2 = newPfContext()
    ctx2["version"] = %2
    saveState(ctx2, "test_state.json")
    
    let loaded = loadState("test_state.json")
    check loaded["version"].getInt() == 2
  
  test "Save empty context":
    let ctx = newPfContext()
    saveState(ctx, "test_state.json")
    
    let loaded = loadState("test_state.json")
    check loaded.len == 0
  
  test "Save and load array data":
    let ctx = newPfContext()
    ctx["numbers"] = %[1, 2, 3, 4, 5]
    ctx["strings"] = %["a", "b", "c"]
    
    saveState(ctx, "test_state.json")
    let loaded = loadState("test_state.json")
    
    check loaded["numbers"].len == 5
    check loaded["numbers"][0].getInt() == 1
    check loaded["strings"].len == 3
    check loaded["strings"][0].getStr() == "a"
  
  test "Checkpoint and restore":
    let ctx = newPfContext()
    ctx["step"] = %1
    
    let checkpoint = checkpoint(ctx)
    
    ctx["step"] = %2
    ctx["modified"] = %true
    
    restore(ctx, checkpoint)
    
    check ctx["step"].getInt() == 1
    check not ctx.hasKey("modified")
  
  test "Multiple checkpoints":
    let ctx = newPfContext()
    ctx["value"] = %10
    
    let cp1 = checkpoint(ctx)
    ctx["value"] = %20
    
    let cp2 = checkpoint(ctx)
    ctx["value"] = %30
    
    restore(ctx, cp2)
    check ctx["value"].getInt() == 20
    
    restore(ctx, cp1)
    check ctx["value"].getInt() == 10
  
  test "Save with special characters in values":
    let ctx = newPfContext()
    ctx["text"] = %"Hello \"World\" with 'quotes' and\nnewlines"
    ctx["path"] = %"C:\\Users\\Test"
    
    saveState(ctx, "test_state.json")
    let loaded = loadState("test_state.json")
    
    check loaded["text"].getStr() == "Hello \"World\" with 'quotes' and\nnewlines"
    check loaded["path"].getStr() == "C:\\Users\\Test"
  
  test "Checkpoint preserves original context":
    let ctx = newPfContext()
    ctx["data"] = %"original"
    
    let cp = checkpoint(ctx)
    ctx["data"] = %"modified"
    
    # Original checkpoint should still have "original"
    let restored = newPfContext()
    for key, val in cp.pairs():
      restored[key] = val
    
    check restored["data"].getStr() == "original"
    check ctx["data"].getStr() == "modified"
