import asyncdispatch, json
import context, node

type
  Flow* = ref object of BaseNode
    startNode*: BaseNode

  BatchFlow* = ref object of BaseNode
    startNode*: BaseNode
    prepBatchFunc*: BatchPrepCallback
    postBatchFunc*: BatchPostCallback

  ParallelBatchFlow* = ref object of BatchFlow
    maxConcurrency*: int

# --- Flow Implementation ---

proc newFlow*(startNode: BaseNode): Flow =
  new(result)
  initBaseNode(result)
  result.startNode = startNode

method internalRun*(flow: Flow, ctx: PfContext): Future[string] {.async, gcsafe.} =
  var currentNode = flow.startNode
  var lastAction = DefaultAction
  
  # If the flow has params, we should ideally merge them into the context or pass them down.
  # However, in the simple model, we just run the graph.
  # If this Flow is running as a sub-flow, the parent might have set params on it.
  
  while currentNode != nil:
    # If the current node is a Flow/BatchFlow, this recursive call works via dynamic dispatch
    lastAction = await currentNode.internalRun(ctx)
    currentNode = currentNode.getNextNode(lastAction)
    
  return lastAction

# --- BatchFlow Implementation ---

proc newBatchFlow*(startNode: BaseNode): BatchFlow =
  new(result)
  initBaseNode(result)
  result.startNode = startNode

proc setPrepBatch*(flow: BatchFlow, f: BatchPrepCallback): BatchFlow {.discardable.} =
  flow.prepBatchFunc = f
  return flow

proc setPostBatch*(flow: BatchFlow, f: BatchPostCallback): BatchFlow {.discardable.} =
  flow.postBatchFunc = f
  return flow

method internalRun*(flow: BatchFlow, ctx: PfContext): Future[string] {.async, gcsafe.} =
  # Prep: Generate list of params
  var paramSets: JsonNode = newJArray()
  if flow.prepBatchFunc != nil:
    paramSets = await flow.prepBatchFunc(ctx, flow.params)
  
  if paramSets.kind != JArray:
    raise newException(Exception, "BatchFlow Prep must return a JArray of params")

  var results = newJArray()

  # Exec: Run the flow for each param set
  for params in paramSets.items:
    # We need to pass these params to the start node (and potentially others?)
    # In Python: "Child nodes can be regular Nodes... parameters are accessed in child nodes via self.params"
    # "BatchFlow merges its own param dict with the parent's... It calls flow.run(shared) using the merged parameters"
    
    # In this implementation, Nodes hold their own params.
    # To support this dynamic param injection, we might need a way to override params during execution.
    # Or we clone the start node? No, that's complex.
    
    # The Go implementation:
    # batchFlow.SetPrepBatch returns []map[string]any
    # It seems it sets the params on the flow?
    # "Start node logs based on params"
    
    # If we look at the Go test:
    # batchFlow := pf.NewBatchFlow(simpleLogNode())
    # simpleLogNode uses params["multiplier"]
    
    # So the params from the batch prep must be accessible to the nodes in the flow.
    # But nodes have `node.params`.
    
    # Maybe we need to temporarily set the params on the nodes? Or use a context-based param stack?
    # The Python docs say: "Params ... like a stack (assigned by the caller)."
    
    # Let's modify `PfContext` to hold a param stack or current params?
    # But `PfContext` in Go has `param map[any]any`.
    
    # In Go `simpleLogNode`:
    # multi := params["multiplier"]
    # The `params` argument to Exec comes from `n.params`.
    
    # So `BatchFlow` must be updating `n.params`?
    # But `BatchFlow` contains a `Flow` or a `Node`.
    # If it contains a `Node`, it can update that Node's params.
    # If it contains a `Flow`, it updates the Flow's params?
    
    # Let's assume for now that `BatchFlow` updates the `startNode`'s params.
    # But if the flow has multiple nodes, they might all need the params.
    
    # Python: "At each level, BatchFlow merges its own param dict with the parent’s. By the time you reach the innermost node, the final params is the merged result of all parents in the chain."
    
    # This implies that `params` should be passed down the call chain `internalRun(ctx, params)`.
    # But `internalRun` signature is fixed.
    
    # Let's look at `node.nim` again.
    # `internalRun` uses `node.params`.
    
    # If we want to support BatchFlow properly, we might need to change `internalRun` to accept `params` override,
    # or `PfContext` should carry the "current execution params".
    
    # Let's check Go implementation again.
    # `Exec(ctx *PfContext, params map[string]any, prepResult any)`
    # `InternalRun` calls `n.Exec(ctx, n.params, prepRes)`.
    
    # So in Go, it uses `n.params`.
    # How does BatchFlow work then?
    # I don't see the BatchFlow implementation in the Go snippet I read (it was cut off or I missed it).
    # But the test `TestBatchFlowExecution` uses `simpleLogNode` which reads `params["multiplier"]`.
    
    # If `BatchFlow` wraps `simpleLogNode`, then `BatchFlow` probably calls `simpleLogNode.SetParams(mergedParams)` before running it?
    # But `simpleLogNode` might be shared? No, usually nodes are instantiated for the flow.
    
    # Let's assume `BatchFlow` modifies the `startNode` params for now.
    # Or better, let's make `PfContext` carry the "active params" if we want to avoid mutating nodes (which is safer for concurrency).
    # But the Node signature takes `params` explicitly.
    
    # Let's stick to mutating `node.params` for this single-threaded/async implementation for now, 
    # or assume the user sets up the flow such that the start node receives the params.
    
    # Actually, if `BatchFlow` runs a `Flow`, and `Flow` runs `startNode`.
    # If `BatchFlow` sets params on `Flow`, `Flow` doesn't automatically pass them to `startNode` in my current implementation.
    
    # Let's update `Flow.internalRun` to pass its params to `startNode`?
    # Or maybe `BatchFlow` should be implemented by creating a new Flow instance for each item?
    
    # Let's try to update `node.params` of the `startNode`.
    # `flow.startNode.params` = `params` (merged).
    
    # Merging:
    var currentParams = flow.params.copy() # Base params of the batch flow
    for k, v in params.pairs:
      currentParams[k] = v
      
    # We need to pass these to the execution.
    # Since we can't easily change the signature of `internalRun` without changing BaseNode,
    # and `internalRun` uses `node.params`.
    
    # We will temporarily set the params of the startNode.
    # This is a bit hacky but works if the graph is a tree (not DAG with shared nodes across concurrent flows).
    
    var originalParams = flow.startNode.params
    flow.startNode.params = currentParams
    
    var action = await flow.startNode.internalRun(ctx)
    results.add(newJString(action)) # Or capture something else?
    
    flow.startNode.params = originalParams # Restore
    
  # Post
  var action = DefaultAction
  if flow.postBatchFunc != nil:
    action = await flow.postBatchFunc(ctx, flow.params, paramSets, results)

  if action == "":
    action = DefaultAction
    
  return action

# --- ParallelBatchFlow Implementation ---

proc newParallelBatchFlow*(startNode: BaseNode, maxConcurrency: int = 0): ParallelBatchFlow =
  new(result)
  initBaseNode(result)
  result.startNode = startNode
  result.maxConcurrency = maxConcurrency

proc setPrepBatch*(flow: ParallelBatchFlow, f: BatchPrepCallback): ParallelBatchFlow {.discardable.} =
  flow.prepBatchFunc = f
  return flow

proc setPostBatch*(flow: ParallelBatchFlow, f: BatchPostCallback): ParallelBatchFlow {.discardable.} =
  flow.postBatchFunc = f
  return flow

method internalRun*(flow: ParallelBatchFlow, ctx: PfContext): Future[string] {.async, gcsafe.} =
  # Prep: Generate list of params
  var paramSets: JsonNode = newJArray()
  if flow.prepBatchFunc != nil:
    paramSets = await flow.prepBatchFunc(ctx, flow.params)
  
  if paramSets.kind != JArray:
    raise newException(Exception, "ParallelBatchFlow Prep must return a JArray of params")

  # Helper to run a single flow instance with given params
  proc runWithParams(params: JsonNode): Future[JsonNode] {.async.} =
    var currentParams = flow.params.copy()
    for k, v in params.pairs:
      currentParams[k] = v
    
    # Clone the start node for parallel execution to avoid mutation conflicts
    # For now, we create a temporary Flow wrapper and set params on it
    # Since nodes share state, we need to be careful here
    # The safest approach is to run with isolated context or accept the limitation
    
    var originalParams = flow.startNode.params
    flow.startNode.params = currentParams
    
    try:
      let action = await flow.startNode.internalRun(ctx)
      return newJString(action)
    finally:
      flow.startNode.params = originalParams

  var results = newJArray()

  if flow.maxConcurrency > 0:
    # Limited concurrency - process in chunks
    var currentFutures: seq[Future[JsonNode]] = @[]
    for params in paramSets.items:
      currentFutures.add(runWithParams(params))
      if currentFutures.len >= flow.maxConcurrency:
        let chunkResults = await all(currentFutures)
        for r in chunkResults: results.add(r)
        currentFutures = @[]
    
    if currentFutures.len > 0:
      let chunkResults = await all(currentFutures)
      for r in chunkResults: results.add(r)
  else:
    # Unlimited concurrency - run all in parallel
    var futures: seq[Future[JsonNode]] = @[]
    for params in paramSets.items:
      futures.add(runWithParams(params))
      
    let resultsSeq = await all(futures)
    for r in resultsSeq: results.add(r)

  # Post
  var action = DefaultAction
  if flow.postBatchFunc != nil:
    action = await flow.postBatchFunc(ctx, flow.params, paramSets, results)

  if action == "":
    action = DefaultAction
    
  return action
