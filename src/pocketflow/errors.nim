## Error types for PocketFlow
##
## Provides a hierarchy of exception types for better error handling
## and more informative error messages.

type
  PocketFlowError* = object of CatchableError
    ## Base exception for all PocketFlow errors
  
  NodeExecutionError* = object of PocketFlowError
    ## Error during node execution
    nodeName*: string
    attemptNumber*: int
  
  FlowExecutionError* = object of PocketFlowError
    ## Error during flow execution
    flowName*: string
    nodeStack*: seq[string]
  
  LLMError* = object of PocketFlowError
    ## Error from LLM provider
    provider*: string
    statusCode*: int
    responseBody*: string
  
  RateLimitError* = object of LLMError
    ## Rate limit exceeded error
    retryAfterSeconds*: int
  
  ValidationError* = object of PocketFlowError
    ## Input validation error
    fieldName*: string
    invalidValue*: string
  
  TimeoutError* = object of PocketFlowError
    ## Operation timeout error
    timeoutMs*: int
  
  CacheError* = object of PocketFlowError
    ## Error in caching layer
    cacheKey*: string

proc newNodeExecutionError*(msg: string, nodeName: string = "", attemptNumber: int = 0): ref NodeExecutionError =
  ## Creates a new NodeExecutionError
  new(result)
  result.msg = msg
  result.nodeName = nodeName
  result.attemptNumber = attemptNumber

proc newLLMError*(msg: string, provider: string = "", statusCode: int = 0, responseBody: string = ""): ref LLMError =
  ## Creates a new LLMError
  new(result)
  result.msg = msg
  result.provider = provider
  result.statusCode = statusCode
  result.responseBody = responseBody

proc newRateLimitError*(msg: string, provider: string = "", retryAfterSeconds: int = 60): ref RateLimitError =
  ## Creates a new RateLimitError
  new(result)
  result.msg = msg
  result.provider = provider
  result.retryAfterSeconds = retryAfterSeconds

proc newTimeoutError*(msg: string, timeoutMs: int): ref TimeoutError =
  ## Creates a new TimeoutError
  new(result)
  result.msg = msg
  result.timeoutMs = timeoutMs

proc newPocketFlowError*(msg: string): ref PocketFlowError =
  ## Creates a new PocketFlowError
  new(result)
  result.msg = msg

proc newCacheError*(msg: string, cacheKey: string = ""): ref CacheError =
  ## Creates a new CacheError
  new(result)
  result.msg = msg
  result.cacheKey = cacheKey

proc newRAGError*(msg: string): ref PocketFlowError =
  ## Creates a new RAG-related error
  new(result)
  result.msg = msg

proc newPersistenceError*(msg: string): ref PocketFlowError =
  ## Creates a new Persistence-related error
  new(result)
  result.msg = msg
