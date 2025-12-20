## Advanced node types for PocketFlow
##
## Provides conditional, loop, timeout, and other specialized node types.

import asyncdispatch, json
import context, node, errors

type
  ConditionalNode* = ref object of BaseNode
    ## Node that branches based on a condition
    conditionFunc*: proc(ctx: PfContext, params: JsonNode): Future[bool] {.gcsafe.}
    trueNode*: BaseNode
    falseNode*: BaseNode

  LoopNode* = ref object of BaseNode
    ## Node that loops over items
    itemsFunc*: proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.gcsafe.}  # Returns JArray
    bodyNode*: BaseNode
    maxIterations*: int
    aggregateResults*: bool

  TimeoutNode* = ref object of BaseNode
    ## Wraps a node with timeout protection
    innerNode*: BaseNode
    timeoutMs*: int

  MapNode* = ref object of BaseNode
    ## Maps a function over a collection
    mapFunc*: proc(ctx: PfContext, item: JsonNode): Future[JsonNode] {.gcsafe.}
    maxConcurrency*: int

proc newConditionalNode*(
  condition: proc(ctx: PfContext, params: JsonNode): Future[bool] {.gcsafe.},
  trueNode: BaseNode,
  falseNode: BaseNode = nil
): ConditionalNode =
  ## Creates a conditional node that branches based on a condition
  new(result)
  initBaseNode(result)
  result.conditionFunc = condition
  result.trueNode = trueNode
  result.falseNode = falseNode

method internalRun*(node: ConditionalNode, ctx: PfContext): Future[string] {.async, gcsafe.} =
  let conditionResult = await node.conditionFunc(ctx, node.params)

  let nextNode = if conditionResult: node.trueNode else: node.falseNode

  if nextNode != nil:
    return await nextNode.internalRun(ctx)
  else:
    return DefaultAction

proc newLoopNode*(
  items: proc(ctx: PfContext, params: JsonNode): Future[JsonNode] {.gcsafe.},
  body: BaseNode,
  maxIterations: int = 100,
  aggregateResults: bool = true
): LoopNode =
  ## Creates a loop node that iterates over items
  new(result)
  initBaseNode(result)
  result.itemsFunc = items
  result.bodyNode = body
  result.maxIterations = maxIterations
  result.aggregateResults = aggregateResults

method internalRun*(node: LoopNode, ctx: PfContext): Future[string] {.async, gcsafe.} =
  let items = await node.itemsFunc(ctx, node.params)

  if items.kind != JArray:
    raise newException(ValidationError, "Loop items must be a JArray")

  var results = newJArray()
  var iterations = 0

  for item in items:
    if iterations >= node.maxIterations:
      break

    # Set current item in context
    ctx["__loop_item__"] = item
    ctx["__loop_index__"] = %iterations

    # Run body node
    let action = await node.bodyNode.internalRun(ctx)

    if node.aggregateResults:
      # Collect results from context or use action
      if ctx.hasKey("__loop_result__"):
        results.add(ctx["__loop_result__"])
      else:
        results.add(%action)

    iterations += 1

  # Store aggregated results
  if node.aggregateResults:
    ctx["__loop_results__"] = results

  ctx["__loop_iterations__"] = %iterations
  return DefaultAction

proc newTimeoutNode*(innerNode: BaseNode, timeoutMs: int): TimeoutNode =
  ## Creates a timeout node that wraps another node
  new(result)
  initBaseNode(result)
  result.innerNode = innerNode
  result.timeoutMs = timeoutMs

method internalRun*(node: TimeoutNode, ctx: PfContext): Future[string] {.async, gcsafe.} =
  let timeoutFuture = sleepAsync(node.timeoutMs)
  let executionFuture = node.innerNode.internalRun(ctx)

  # Race between execution and timeout
  await executionFuture or timeoutFuture

  if executionFuture.finished:
    return await executionFuture
  else:
    raise newTimeoutError(
      "Node execution exceeded timeout",
      node.timeoutMs
    )

proc newMapNode*(
  mapFunc: proc(ctx: PfContext, item: JsonNode): Future[JsonNode] {.gcsafe.},
  maxConcurrency: int = 0
): MapNode =
  ## Creates a map node that applies a function to each item
  new(result)
  initBaseNode(result)
  result.mapFunc = mapFunc
  result.maxConcurrency = maxConcurrency

method internalRun*(node: MapNode, ctx: PfContext): Future[string] {.async, gcsafe.} =
  # Expect items in context under "__map_items__" key
  if not ctx.hasKey("__map_items__"):
    raise newException(ValidationError, "MapNode requires __map_items__ in context")

  let items = ctx["__map_items__"]

  if items.kind != JArray:
    raise newException(ValidationError, "MapNode items must be a JArray")

  var results = newJArray()

  if node.maxConcurrency > 0:
    # Limited concurrency
    var currentFutures: seq[Future[JsonNode]] = @[]

    for item in items:
      currentFutures.add(node.mapFunc(ctx, item))

      if currentFutures.len >= node.maxConcurrency:
        let chunkResults = await all(currentFutures)
        for r in chunkResults:
          results.add(r)
        currentFutures = @[]

    if currentFutures.len > 0:
      let chunkResults = await all(currentFutures)
      for r in chunkResults:
        results.add(r)
  else:
    # Sequential or unlimited concurrency
    for item in items:
      let result = await node.mapFunc(ctx, item)
      results.add(result)

  ctx["__map_results__"] = results
  return DefaultAction
