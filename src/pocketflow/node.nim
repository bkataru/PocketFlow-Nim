## Node module for PocketFlow
## 
## Provides the core node types for building execution graphs.
## Nodes can be chained together to create complex workflows with
## retry logic, fallback handling, and parallel execution.

import asyncdispatch, json, tables, strformat, logging
import context

const DefaultAction* = "default"
  ## The default action returned when post callbacks return an empty string

type
  # Callback types
  PrepCallback* = proc (ctx: PfContext, params: JsonNode): Future[JsonNode] {.gcsafe.}
  ExecCallback* = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.gcsafe.}
  PostCallback* = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.gcsafe.}
  FallbackCallback* = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, err: ref Exception): Future[JsonNode] {.gcsafe.}

  # Batch specific callbacks
  BatchPrepCallback* = proc (ctx: PfContext, params: JsonNode): Future[JsonNode] {.gcsafe.} # Should return JArray
  BatchExecItemCallback* = proc (ctx: PfContext, params: JsonNode, item: JsonNode): Future[JsonNode] {.gcsafe.}
  BatchPostCallback* = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.gcsafe.}
  BatchItemFallbackCallback* = proc (ctx: PfContext, params: JsonNode, item: JsonNode, err: ref Exception): Future[JsonNode] {.gcsafe.}

  BaseNode* = ref object of RootObj
    params*: JsonNode
    successors*: TableRef[string, BaseNode]

  Node* = ref object of BaseNode
    maxRetries*: int
    waitMs*: int
    curRetry*: int  # Current retry attempt (0-indexed)
    prepFunc*: PrepCallback
    execFunc*: ExecCallback
    postFunc*: PostCallback
    fallbackFunc*: FallbackCallback

  BatchNode* = ref object of BaseNode
    maxRetries*: int
    waitMs*: int
    curRetry*: int  # Current retry attempt for current item (0-indexed)
    prepFunc*: BatchPrepCallback
    execItemFunc*: BatchExecItemCallback
    postFunc*: BatchPostCallback
    itemFallbackFunc*: BatchItemFallbackCallback

  ParallelBatchNode* = ref object of BatchNode
    maxConcurrency*: int

# Helper to create a new BaseNode part
proc initBaseNode*(node: BaseNode) =
  node.params = newJObject()
  node.successors = newTable[string, BaseNode]()

proc setParams*(node: BaseNode, params: JsonNode): BaseNode {.discardable.} =
  node.params = params
  return node

proc addSuccessor*(node: BaseNode, action: string, nextNode: BaseNode): BaseNode {.discardable.} =
  node.successors[action] = nextNode
  return node

proc next*(node: BaseNode, nextNode: BaseNode): BaseNode {.discardable.} =
  return node.addSuccessor(DefaultAction, nextNode)

proc next*(node: BaseNode, action: string, nextNode: BaseNode): BaseNode {.discardable.} =
  return node.addSuccessor(action, nextNode)

# --- Operator Overloads for Pythonic Chaining ---

# `>>` operator: nodeA >> nodeB  is equivalent to nodeA.next(nodeB)
proc `>>`*(node: BaseNode, nextNode: BaseNode): BaseNode {.discardable.} =
  return node.next(nextNode)

# `-` operator: node - "action"  creates an ActionLink for chaining
type ActionLink* = object
  node*: BaseNode
  action*: string

proc `-`*(node: BaseNode, action: string): ActionLink =
  return ActionLink(node: node, action: action)

# `>>` with ActionLink: (nodeA - "custom") >> nodeB
proc `>>`*(link: ActionLink, nextNode: BaseNode): BaseNode {.discardable.} =
  discard link.node.addSuccessor(link.action, nextNode)
  return link.node

proc getNextNode*(node: BaseNode, action: string): BaseNode =
  if node.successors.hasKey(action):
    return node.successors[action]
  if node.successors.hasKey(DefaultAction):
    return node.successors[DefaultAction]
  return nil

# --- Node Implementation ---

proc newNode*(
  prep: PrepCallback = nil,
  exec: ExecCallback = nil,
  post: PostCallback = nil,
  fallback: FallbackCallback = nil,
  maxRetries: int = 1,
  waitMs: int = 0
): Node =
  new(result)
  initBaseNode(result)
  result.prepFunc = prep
  result.execFunc = exec
  result.postFunc = post
  result.fallbackFunc = fallback
  result.maxRetries = maxRetries
  result.waitMs = waitMs

method internalRun*(node: BaseNode, ctx: PfContext): Future[string] {.base, async, gcsafe.} =
  ## Base implementation - should be overridden by derived types
  return "internalRun not implemented for BaseNode"

method internalRun*(node: Node, ctx: PfContext): Future[string] {.async, gcsafe.} =
  # Prep
  var prepRes: JsonNode = newJNull()
  if node.prepFunc != nil:
    prepRes = await node.prepFunc(ctx, node.params)

  # Exec with Retry
  var execRes: JsonNode = newJNull()
  var lastErr: ref Exception = nil
  var success = false

  for i in 0 ..< node.maxRetries:
    node.curRetry = i  # Set current retry counter
    try:
      if node.execFunc != nil:
        execRes = await node.execFunc(ctx, node.params, prepRes)
      success = true
      break
    except Exception as e:
      lastErr = e
      if i < node.maxRetries - 1:
        warn(fmt"Node exec failed (attempt {i + 1}/{node.maxRetries}): {e.msg}. Retrying...")
        if node.waitMs > 0:
          await sleepAsync(node.waitMs)

  if not success:
    if node.fallbackFunc != nil:
      try:
        execRes = await node.fallbackFunc(ctx, node.params, prepRes, lastErr)
      except Exception as e:
        raise newException(Exception, fmt"ExecFallback failed: {e.msg}", e)
    else:
      raise newException(Exception, fmt"Exec failed after {node.maxRetries} retries: {lastErr.msg}", lastErr)

  # Post
  var action = DefaultAction
  if node.postFunc != nil:
    action = await node.postFunc(ctx, node.params, prepRes, execRes)
  
  if action == "":
    action = DefaultAction
    
  return action

# --- BatchNode Implementation ---

proc newBatchNode*(
  prep: BatchPrepCallback = nil,
  execItem: BatchExecItemCallback = nil,
  post: BatchPostCallback = nil,
  itemFallback: BatchItemFallbackCallback = nil,
  maxRetries: int = 1,
  waitMs: int = 0
): BatchNode =
  new(result)
  initBaseNode(result)
  result.prepFunc = prep
  result.execItemFunc = execItem
  result.postFunc = post
  result.itemFallbackFunc = itemFallback
  result.maxRetries = maxRetries
  result.waitMs = waitMs

method internalRun*(node: BatchNode, ctx: PfContext): Future[string] {.async, gcsafe.} =
  # Prep
  var prepRes: JsonNode = newJArray()
  if node.prepFunc != nil:
    prepRes = await node.prepFunc(ctx, node.params)
  
  if prepRes.kind != JArray:
    raise newException(Exception, "BatchNode Prep must return a JArray")

  # Exec Items
  var execResults = newJArray()
  
  for item in prepRes.items:
    var itemRes: JsonNode = newJNull()
    var lastErr: ref Exception = nil
    var success = false

    for i in 0 ..< node.maxRetries:
      node.curRetry = i  # Set current retry counter for this item
      try:
        if node.execItemFunc != nil:
          itemRes = await node.execItemFunc(ctx, node.params, item)
        else:
          itemRes = item # Default pass-through
        success = true
        break
      except Exception as e:
        lastErr = e
        if i < node.maxRetries - 1:
          warn(fmt"BatchNode item exec failed (attempt {i + 1}/{node.maxRetries}): {e.msg}. Retrying...")
          if node.waitMs > 0:
            await sleepAsync(node.waitMs)
    
    if not success:
      if node.itemFallbackFunc != nil:
        try:
          itemRes = await node.itemFallbackFunc(ctx, node.params, item, lastErr)
        except Exception as e:
           raise newException(Exception, fmt"Batch item fallback failed: {e.msg}", e)
      else:
         raise newException(Exception, fmt"Batch item exec failed after {node.maxRetries} retries: {lastErr.msg}", lastErr)
    
    execResults.add(itemRes)

  # Post
  var action = DefaultAction
  if node.postFunc != nil:
    action = await node.postFunc(ctx, node.params, prepRes, execResults)

  if action == "":
    action = DefaultAction

  return action

method run*(node: BaseNode, ctx: PfContext): Future[string] {.base, async.} =
  return await node.internalRun(ctx)

# --- ParallelBatchNode Implementation ---

proc newParallelBatchNode*(
  prep: BatchPrepCallback = nil,
  execItem: BatchExecItemCallback = nil,
  post: BatchPostCallback = nil,
  itemFallback: BatchItemFallbackCallback = nil,
  maxRetries: int = 1,
  waitMs: int = 0,
  maxConcurrency: int = 0
): ParallelBatchNode =
  new(result)
  initBaseNode(result)
  result.prepFunc = prep
  result.execItemFunc = execItem
  result.postFunc = post
  result.itemFallbackFunc = itemFallback
  result.maxRetries = maxRetries
  result.waitMs = waitMs
  result.maxConcurrency = maxConcurrency

method internalRun*(node: ParallelBatchNode, ctx: PfContext): Future[string] {.async, gcsafe.} =
  # Prep
  var prepRes: JsonNode = newJArray()
  if node.prepFunc != nil:
    prepRes = await node.prepFunc(ctx, node.params)
  
  if prepRes.kind != JArray:
    raise newException(Exception, "ParallelBatchNode Prep must return a JArray")

  # Helper proc for processing single item
  proc processItem(item: JsonNode): Future[JsonNode] {.async.} =
    var itemRes: JsonNode = newJNull()
    var lastErr: ref Exception = nil
    var success = false

    for i in 0 ..< node.maxRetries:
      try:
        if node.execItemFunc != nil:
          itemRes = await node.execItemFunc(ctx, node.params, item)
        else:
          itemRes = item
        success = true
        break
      except Exception as e:
        lastErr = e
        if i < node.maxRetries - 1:
          warn(fmt"ParallelBatchNode item exec failed (attempt {i + 1}/{node.maxRetries}): {e.msg}. Retrying...")
          if node.waitMs > 0:
            await sleepAsync(node.waitMs)
    
    if not success:
      if node.itemFallbackFunc != nil:
        try:
          itemRes = await node.itemFallbackFunc(ctx, node.params, item, lastErr)
        except Exception as e:
           raise newException(Exception, fmt"Batch item fallback failed: {e.msg}", e)
      else:
         raise newException(Exception, fmt"Batch item exec failed after {node.maxRetries} retries: {lastErr.msg}", lastErr)
    return itemRes

  var execResults = newJArray()

  if node.maxConcurrency > 0:
    # Limited concurrency
    var currentFutures: seq[Future[JsonNode]] = @[]
    for item in prepRes.items:
      currentFutures.add(processItem(item))
      if currentFutures.len >= node.maxConcurrency:
        let chunkResults = await all(currentFutures)
        for r in chunkResults: execResults.add(r)
        currentFutures = @[]
    
    if currentFutures.len > 0:
      let chunkResults = await all(currentFutures)
      for r in chunkResults: execResults.add(r)
  else:
    # Unlimited concurrency
    var futures: seq[Future[JsonNode]] = @[]
    for item in prepRes.items:
      futures.add(processItem(item))
      
    let execResultsSeq = await all(futures)
    for r in execResultsSeq: execResults.add(r)

  # Post
  var action = DefaultAction
  if node.postFunc != nil:
    action = await node.postFunc(ctx, node.params, prepRes, execResults)

  if action == "":
    action = DefaultAction

  return action

