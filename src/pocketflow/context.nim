## Context module for PocketFlow
## 
## Provides a shared context for passing data between nodes in a flow.
## The context stores JSON data in a key-value table.

import json, tables

type
  PfContext* = ref object
    ## Shared context for flow execution.
    ## Stores arbitrary JSON data that can be accessed by any node in the flow.
    store*: TableRef[string, JsonNode]

proc newPfContext*(): PfContext =
  ## Creates a new PocketFlow context.
  ## 
  ## Returns:
  ##   A new PfContext instance with an empty data table.
  new(result)
  result.store = newTable[string, JsonNode]()

proc `[]`*(ctx: PfContext, key: string): JsonNode =
  ## Gets a value from the context by key.
  ## 
  ## Args:
  ##   key: The key to look up
  ## 
  ## Returns:
  ##   The JSON value associated with the key, or JNull if key doesn't exist
  if ctx.store.hasKey(key):
    return ctx.store[key]
  return newJNull()

proc `[]=`*(ctx: PfContext, key: string, value: JsonNode) =
  ## Sets a value in the context.
  ## 
  ## Args:
  ##   key: The key to set
  ##   value: The JSON value to store
  ctx.store[key] = value

proc hasKey*(ctx: PfContext, key: string): bool =
  ## Checks if a key exists in the context.
  ## 
  ## Args:
  ##   key: The key to check
  ## 
  ## Returns:
  ##   True if the key exists, false otherwise
  return ctx.store.hasKey(key)
