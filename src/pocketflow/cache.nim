## Caching module for PocketFlow
##
## Provides in-memory and persistent caching for LLM responses,
## embeddings, and other expensive operations.

import json, tables, times, hashes, strutils

type
  CacheEntry* = object
    value*: JsonNode
    timestamp*: Time
    ttlSeconds*: int

  Cache* = ref object
    store*: TableRef[string, CacheEntry]
    maxSize*: int
    defaultTtl*: int

proc newCache*(maxSize: int = 10000, defaultTtl: int = 3600): Cache =
  ## Creates a new cache instance
  ##
  ## Args:
  ##   maxSize: Maximum number of entries (default 10000)
  ##   defaultTtl: Default time-to-live in seconds (default 1 hour)
  result = Cache(
    store: newTable[string, CacheEntry](),
    maxSize: maxSize,
    defaultTtl: defaultTtl
  )

proc computeKey*(parts: varargs[string]): string =
  ## Computes a cache key from multiple parts
  ## Uses hash for consistent key generation
  let combined = parts.join(":")
  result = $hash(combined)

proc get*(cache: Cache, key: string): JsonNode =
  ## Gets a value from the cache
  ##
  ## Returns:
  ##   The cached value, or JNull if not found or expired
  if not cache.store.hasKey(key):
    return newJNull()

  let entry = cache.store[key]
  let age = getTime() - entry.timestamp

  if age.inSeconds > entry.ttlSeconds:
    cache.store.del(key)
    return newJNull()

  return entry.value

proc set*(cache: Cache, key: string, value: JsonNode, ttl: int = -1) =
  ## Sets a value in the cache
  ##
  ## Args:
  ##   key: The cache key
  ##   value: The value to cache
  ##   ttl: Time-to-live in seconds (-1 uses default)

  # Evict oldest if at capacity
  if cache.store.len >= cache.maxSize and not cache.store.hasKey(key):
    var oldestKey = ""
    var oldestTime = getTime()
    for k, entry in cache.store:
      if entry.timestamp < oldestTime:
        oldestTime = entry.timestamp
        oldestKey = k
    if oldestKey != "":
      cache.store.del(oldestKey)

  let actualTtl = if ttl < 0: cache.defaultTtl else: ttl
  cache.store[key] = CacheEntry(
    value: value,
    timestamp: getTime(),
    ttlSeconds: actualTtl
  )

proc has*(cache: Cache, key: string): bool =
  ## Checks if a key exists and is not expired
  let value = cache.get(key)
  return value.kind != JNull

proc clear*(cache: Cache) =
  ## Clears all cached entries
  cache.store.clear()

proc size*(cache: Cache): int =
  ## Returns the number of cached entries
  return cache.store.len

proc evictExpired*(cache: Cache): int =
  ## Removes all expired entries
  ##
  ## Returns:
  ##   Number of entries removed
  result = 0
  var toDelete: seq[string] = @[]
  let now = getTime()

  for key, entry in cache.store:
    let age = now - entry.timestamp
    if age.inSeconds > entry.ttlSeconds:
      toDelete.add(key)

  for key in toDelete:
    cache.store.del(key)
    result += 1

# Global cache instance
var globalCache* = newCache()

proc getCached*(key: string): JsonNode =
  ## Gets a value from the global cache
  return globalCache.get(key)

proc setCached*(key: string, value: JsonNode, ttl: int = -1) =
  ## Sets a value in the global cache
  globalCache.set(key, value, ttl)
