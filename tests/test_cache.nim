import unittest
import json
import times
import ../src/pocketflow/cache

suite "Cache Tests":
  test "Create cache with default size":
    let cache = newCache()
    check cache != nil
  
  test "Set and get cached value":
    let cache = newCache()
    cache.set("key1", %"value1")
    let val = cache.get("key1")
    check val.kind != JNull
    check val.getStr() == "value1"
  
  test "Get non-existent key returns JNull":
    let cache = newCache()
    let val = cache.get("missing")
    check val.kind == JNull
  
  test "Cache has method works":
    let cache = newCache()
    cache.set("key1", %"value1")
    check cache.has("key1")
    check not cache.has("missing")
  
  test "Clear cache removes all entries":
    let cache = newCache()
    cache.set("key1", %"value1")
    cache.set("key2", %"value2")
    cache.clear()
    check not cache.has("key1")
    check not cache.has("key2")
  
  test "Cache size tracking":
    let cache = newCache()
    cache.set("key1", %"value1")
    cache.set("key2", %"value2")
    check cache.size() == 2
