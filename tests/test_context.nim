import unittest
import tables
import json
import ../src/pocketflow/context

suite "Context Tests":
  test "Create new context":
    let ctx = newPfContext()
    check ctx != nil
  
  test "Set and get string value":
    let ctx = newPfContext()
    ctx["name"] = %"Alice"
    check ctx["name"].getStr() == "Alice"
  
  test "Set and get integer value":
    let ctx = newPfContext()
    ctx["age"] = %42
    check ctx["age"].getInt() == 42
  
  test "Set and get float value":
    let ctx = newPfContext()
    ctx["score"] = %3.14
    check ctx["score"].getFloat() == 3.14
  
  test "Set and get boolean value":
    let ctx = newPfContext()
    ctx["active"] = %true
    check ctx["active"].getBool() == true
  
  test "Check if key exists":
    let ctx = newPfContext()
    ctx["test"] = %"value"
    check ctx.hasKey("test")
    check not ctx.hasKey("missing")
  
  test "Get all keys":
    let ctx = newPfContext()
    ctx["key1"] = %"value1"
    ctx["key2"] = %"value2"
    var keyCount = 0
    for key in ctx.store.keys():
      keyCount.inc()
    check keyCount == 2
  
  test "Set and get nested JSON":
    let ctx = newPfContext()
    let nested = %*{"inner": "value", "number": 123}
    ctx["nested"] = nested
    check ctx["nested"]["inner"].getStr() == "value"
    check ctx["nested"]["number"].getInt() == 123
  
  test "Update existing value":
    let ctx = newPfContext()
    ctx["counter"] = %1
    check ctx["counter"].getInt() == 1
    ctx["counter"] = %2
    check ctx["counter"].getInt() == 2
  
  test "Store array in context":
    let ctx = newPfContext()
    ctx["items"] = %[1, 2, 3, 4, 5]
    check ctx["items"].len == 5
    check ctx["items"][0].getInt() == 1
  
  test "Clone context":
    let ctx = newPfContext()
    ctx["original"] = %"value"
    let cloned = newPfContext()
    for key, val in ctx.store.pairs():
      cloned[key] = val
    check cloned["original"].getStr() == "value"
    ctx["original"] = %"changed"
    check cloned["original"].getStr() == "value"
