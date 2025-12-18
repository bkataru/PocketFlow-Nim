## LLM client module for PocketFlow
##
## Provides unified interface for multiple LLM providers with streaming,
## caching, token tracking, and error handling.

import asyncdispatch, httpclient, json, strformat, strutils, sequtils
import errors, cache, tokens, observability

type
  LlmProvider* = enum
    ## Supported LLM providers
    OpenAI, Ollama, Anthropic, Google, Custom

  StreamCallback* = proc(chunk: string): Future[void] {.gcsafe.}
    ## Callback for streaming responses
  
  LlmOptions* = object
    ## Configuration options for LLM requests
    temperature*: float
    maxTokens*: int
    topP*: float
    stream*: bool
    streamCallback*: StreamCallback
    useCache*: bool
    timeout*: int  # milliseconds

  LlmClient* = ref object
    ## Client for interacting with LLM providers
    provider*: LlmProvider
    baseUrl*: string
    apiKey*: string
    model*: string
    httpClient: AsyncHttpClient
    costTracker*: CostTracker
    cache*: Cache

proc newLlmClient*(
  provider: LlmProvider = OpenAI,
  baseUrl: string = "",
  apiKey: string = "",
  model: string = "",
  costTracker: CostTracker = nil,
  cache: Cache = nil
): LlmClient =
  ## Creates a new LLM client
  ## 
  ## Args:
  ##   provider: The LLM provider to use
  ##   baseUrl: Custom base URL (uses defaults if empty)
  ##   apiKey: API key for authentication
  ##   model: Model name (uses defaults if empty)
  ##   costTracker: Optional custom cost tracker
  ##   cache: Optional custom cache
  new(result)
  result.provider = provider
  result.apiKey = apiKey
  result.httpClient = newAsyncHttpClient()
  result.costTracker = if costTracker != nil: costTracker else: globalCostTracker
  result.cache = if cache != nil: cache else: globalCache
  
  # Set defaults based on provider
  case provider
  of OpenAI:
    result.baseUrl = if baseUrl == "": "https://api.openai.com/v1" else: baseUrl
    result.model = if model == "": "gpt-4o-mini" else: model
  of Ollama:
    result.baseUrl = if baseUrl == "": "http://localhost:11434/v1" else: baseUrl
    result.model = if model == "": "llama3" else: model
  of Anthropic:
    result.baseUrl = if baseUrl == "": "https://api.anthropic.com/v1" else: baseUrl
    result.model = if model == "": "claude-3-5-sonnet-20241022" else: model
  of Google:
    result.baseUrl = if baseUrl == "": "https://generativelanguage.googleapis.com/v1beta" else: baseUrl
    result.model = if model == "": "gemini-1.5-flash" else: model
  of Custom:
    result.baseUrl = baseUrl
    result.model = model

# Forward declarations
proc chatWithOptions*(client: LlmClient, messages: JsonNode, options: LlmOptions): Future[string] {.async, gcsafe.}
proc chatOpenAIStyle(client: LlmClient, messages: JsonNode, options: LlmOptions): Future[string] {.async, gcsafe.}
proc chatAnthropic(client: LlmClient, messages: JsonNode, options: LlmOptions): Future[string] {.async, gcsafe.}
proc chatGoogle(client: LlmClient, messages: JsonNode, options: LlmOptions): Future[string] {.async, gcsafe.}

proc chat*(client: LlmClient, messages: JsonNode, temperature: float = 0.7): Future[string] {.async, gcsafe.} =
  ## Sends a chat completion request (non-streaming)
  ## 
  ## Args:
  ##   messages: JArray of message objects with "role" and "content"
  ##   temperature: Sampling temperature (0.0-2.0)
  ## 
  ## Returns:
  ##   The assistant's response text
  let options = LlmOptions(
    temperature: temperature,
    maxTokens: 0,
    topP: 1.0,
    stream: false,
    useCache: true,
    timeout: 30000
  )
  return await client.chatWithOptions(messages, options)

proc chatWithOptions*(client: LlmClient, messages: JsonNode, options: LlmOptions): Future[string] {.async, gcsafe.} =
  ## Sends a chat completion request with full options
  ## Supports caching and token tracking
  
  # Check cache first
  if options.useCache:
    let cacheKey = computeKey(client.model, $messages, $options.temperature)
    let cached = client.cache.get(cacheKey)
    if cached.kind != JNull:
      logStructured(Debug, "Cache hit for LLM request", [("model", client.model)])
      return cached.getStr()
  
  # Make request based on provider
  let response = case client.provider
    of OpenAI, Ollama, Custom:
      await client.chatOpenAIStyle(messages, options)
    of Anthropic:
      await client.chatAnthropic(messages, options)
    of Google:
      await client.chatGoogle(messages, options)
  
  # Cache the response
  if options.useCache:
    let cacheKey = computeKey(client.model, $messages, $options.temperature)
    client.cache.set(cacheKey, %response)
  
  return response

proc chatOpenAIStyle(client: LlmClient, messages: JsonNode, options: LlmOptions): Future[string] {.async, gcsafe.} =
  ## OpenAI-compatible chat endpoint (OpenAI, Ollama, Custom)
  let url = fmt"{client.baseUrl}/chat/completions"
  
  var body = %*{
    "model": client.model,
    "messages": messages,
    "temperature": options.temperature
  }
  
  if options.maxTokens > 0:
    body["max_tokens"] = %options.maxTokens
  if options.stream:
    body["stream"] = %true
  
  if client.apiKey != "":
    client.httpClient.headers = newHttpHeaders({ 
      "Authorization": fmt"Bearer {client.apiKey}", 
      "Content-Type": "application/json" 
    })
  else:
    client.httpClient.headers = newHttpHeaders({ "Content-Type": "application/json" })

  withSpan(fmt"llm_request_{client.provider}"):
    let response = await client.httpClient.post(url, body = $body)
    let respBody = await response.body
    
    if response.code.is4xx or response.code.is5xx:
      if response.code.int == 429:
        raise newRateLimitError(
          fmt"Rate limit exceeded: {respBody}",
          $client.provider,
          60
        )
      raise newLLMError(
        fmt"LLM Request failed: {response.status}",
        $client.provider,
        response.code.int,
        respBody
      )

    let jsonResp = parseJson(respBody)
    let content = jsonResp["choices"][0]["message"]["content"].getStr()
    
    # Track usage if available
    if jsonResp.hasKey("usage"):
      let usage = jsonResp["usage"]
      if usage.hasKey("prompt_tokens") and usage.hasKey("completion_tokens"):
        let inputTokens = usage["prompt_tokens"].getInt()
        let outputTokens = usage["completion_tokens"].getInt()
        client.costTracker.trackUsage(client.model, inputTokens, outputTokens)
        {.cast(gcsafe).}:
          recordMetric("llm_input_tokens", float(inputTokens), [("model", client.model)])
          recordMetric("llm_output_tokens", float(outputTokens), [("model", client.model)])
    
    return content

proc chatAnthropic(client: LlmClient, messages: JsonNode, options: LlmOptions): Future[string] {.async, gcsafe.} =
  ## Anthropic-specific chat endpoint
  let url = fmt"{client.baseUrl}/messages"
  
  # Convert messages format
  var anthropicMessages = newJArray()
  for msg in messages:
    if msg["role"].getStr() != "system":
      anthropicMessages.add(msg)
  
  var body = %*{
    "model": client.model,
    "messages": anthropicMessages,
    "max_tokens": if options.maxTokens > 0: options.maxTokens else: 4096
  }
  
  # Add system message if present
  for msg in messages:
    if msg["role"].getStr() == "system":
      body["system"] = msg["content"]
      break
  
  client.httpClient.headers = newHttpHeaders({
    "x-api-key": client.apiKey,
    "anthropic-version": "2023-06-01",
    "Content-Type": "application/json"
  })
  
  withSpan("llm_request_anthropic"):
    let response = await client.httpClient.post(url, body = $body)
    let respBody = await response.body
    
    if response.code.is4xx or response.code.is5xx:
      if response.code.int == 429:
        raise newRateLimitError(
          fmt"Rate limit exceeded: {respBody}",
          "Anthropic",
          60
        )
      raise newLLMError(
        fmt"Anthropic Request failed: {response.status}",
        "Anthropic",
        response.code.int,
        respBody
      )
    
    let jsonResp = parseJson(respBody)
    let content = jsonResp["content"][0]["text"].getStr()
    
    # Track usage
    if jsonResp.hasKey("usage"):
      let usage = jsonResp["usage"]
      let inputTokens = usage["input_tokens"].getInt()
      let outputTokens = usage["output_tokens"].getInt()
      client.costTracker.trackUsage(client.model, inputTokens, outputTokens)
    
    return content

proc chatGoogle(client: LlmClient, messages: JsonNode, options: LlmOptions): Future[string] {.async, gcsafe.} =
  ## Google Gemini chat endpoint
  let url = fmt"{client.baseUrl}/models/{client.model}:generateContent?key={client.apiKey}"
  
  # Convert messages to Gemini format
  var contents = newJArray()
  for msg in messages:
    let role = if msg["role"].getStr() == "assistant": "model" else: "user"
    contents.add(%*{
      "role": role,
      "parts": [{"text": msg["content"].getStr()}]
    })
  
  var body = %*{
    "contents": contents,
    "generationConfig": {
      "temperature": options.temperature
    }
  }
  
  if options.maxTokens > 0:
    body["generationConfig"]["maxOutputTokens"] = %options.maxTokens
  
  client.httpClient.headers = newHttpHeaders({
    "Content-Type": "application/json"
  })
  
  withSpan("llm_request_google"):
    let response = await client.httpClient.post(url, body = $body)
    let respBody = await response.body
    
    if response.code.is4xx or response.code.is5xx:
      if response.code.int == 429:
        raise newRateLimitError(
          fmt"Rate limit exceeded: {respBody}",
          "Google",
          60
        )
      raise newLLMError(
        fmt"Google Request failed: {response.status}",
        "Google",
        response.code.int,
        respBody
      )
    
    let jsonResp = parseJson(respBody)
    let content = jsonResp["candidates"][0]["content"]["parts"][0]["text"].getStr()
    
    # Track estimated usage (Google doesn't always provide exact counts)
    if jsonResp.hasKey("usageMetadata"):
      let usage = jsonResp["usageMetadata"]
      let inputTokens = usage.getOrDefault("promptTokenCount").getInt(0)
      let outputTokens = usage.getOrDefault("candidatesTokenCount").getInt(0)
      client.costTracker.trackUsage(client.model, inputTokens, outputTokens)
    
    return content

proc generate*(client: LlmClient, prompt: string, temperature: float = 0.7): Future[string] {.async, gcsafe.} =
  ## Helper for simple single-turn generation
  ## 
  ## Args:
  ##   prompt: The user prompt
  ##   temperature: Sampling temperature
  ## 
  ## Returns:
  ##   The generated response
  let messages = %*[{
    "role": "user",
    "content": prompt
  }]
  return await client.chat(messages, temperature)

proc embeddings*(client: LlmClient, texts: seq[string], model: string = ""): Future[seq[seq[float]]] {.async, gcsafe.} =
  ## Generates embeddings for text inputs
  ## 
  ## Args:
  ##   texts: Sequence of texts to embed
  ##   model: Embedding model (uses defaults if empty)
  ## 
  ## Returns:
  ##   Sequence of embedding vectors
  let embeddingModel = if model != "": model else:
    case client.provider
    of OpenAI: "text-embedding-3-small"
    of Custom, Ollama: "nomic-embed-text"
    else: ""
  
  if embeddingModel == "":
    raise newLLMError("Embeddings not supported for provider", $client.provider)
  
  # Check cache
  var results: seq[seq[float]] = @[]
  var uncachedTexts: seq[tuple[idx: int, text: string]] = @[]
  
  for i, text in texts:
    let cacheKey = computeKey("embedding", embeddingModel, text)
    let cached = client.cache.get(cacheKey)
    if cached.kind != JNull:
      var vec: seq[float] = @[]
      for val in cached:
        vec.add(val.getFloat())
      results.add(vec)
    else:
      results.add(@[])  # Placeholder
      uncachedTexts.add((idx: i, text: text))
  
  if uncachedTexts.len == 0:
    return results
  
  # Make API request for uncached texts
  let url = fmt"{client.baseUrl}/embeddings"
  let body = %*{
    "model": embeddingModel,
    "input": uncachedTexts.mapIt(it.text)
  }
  
  if client.apiKey != "":
    client.httpClient.headers = newHttpHeaders({
      "Authorization": fmt"Bearer {client.apiKey}",
      "Content-Type": "application/json"
    })
  else:
    client.httpClient.headers = newHttpHeaders({"Content-Type": "application/json"})
  
  let response = await client.httpClient.post(url, body = $body)
  let respBody = await response.body
  
  if response.code.is4xx or response.code.is5xx:
    raise newLLMError(
      fmt"Embedding request failed: {response.status}",
      $client.provider,
      response.code.int,
      respBody
    )
  
  let jsonResp = parseJson(respBody)
  
  # Process embeddings
  for i, item in uncachedTexts:
    let embedding = jsonResp["data"][i]["embedding"]
    var vec: seq[float] = @[]
    for val in embedding:
      vec.add(val.getFloat())
    
    results[item.idx] = vec
    
    # Cache the embedding
    let cacheKey = computeKey("embedding", embeddingModel, item.text)
    client.cache.set(cacheKey, %vec, ttl = 86400)  # Cache for 24 hours
  
  # Track usage
  if jsonResp.hasKey("usage"):
    let totalTokens = jsonResp["usage"]["total_tokens"].getInt()
    client.costTracker.trackUsage(embeddingModel, totalTokens, 0)
  
  return results

proc close*(client: LlmClient) =
  ## Closes the HTTP client and releases resources
  client.httpClient.close()
