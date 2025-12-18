import unittest
import asyncdispatch
import json
import os
import ../src/pocketflow/[context, llm, cache, tokens]

# Note: These tests require API keys to be set in environment variables
# For CI/CD, mock implementations should be used

suite "LLM Tests":
  test "Create LLM client":
    if getEnv("OPENAI_API_KEY") != "":
      let client = newLLMClient("openai", apiKey = getEnv("OPENAI_API_KEY"))
      check client != nil
  
  test "Chat completion structure":
    # Test with mock/offline mode
    let client = newLLMClient("openai", apiKey = "test_key")
    check client != nil
    check client.provider == "openai"
  
  test "Different providers can be created":
    let openai = newLLMClient("openai", apiKey = "test")
    let anthropic = newLLMClient("anthropic", apiKey = "test")
    let google = newLLMClient("google", apiKey = "test")
    let ollama = newLLMClient("ollama")
    
    check openai.provider == "openai"
    check anthropic.provider == "anthropic"
    check google.provider == "google"
    check ollama.provider == "ollama"
  
  test "Cache configuration":
    let client = newLLMClient("openai", apiKey = "test", enableCache = true)
    check client.cache != nil
  
  test "Token tracking is initialized":
    let client = newLLMClient("openai", apiKey = "test")
    check client.inputTokens >= 0
    check client.outputTokens >= 0
  
  test "Get token usage":
    let client = newLLMClient("openai", apiKey = "test")
    let usage = client.getTokenUsage()
    check usage["input_tokens"].getInt() >= 0
    check usage["output_tokens"].getInt() >= 0
  
  test "Calculate cost":
    let client = newLLMClient("openai", apiKey = "test", model = "gpt-3.5-turbo")
    client.inputTokens = 1000
    client.outputTokens = 500
    let cost = client.getCost()
    check cost >= 0.0
  
  test "Reset token counts":
    let client = newLLMClient("openai", apiKey = "test")
    client.inputTokens = 1000
    client.outputTokens = 500
    client.resetTokens()
    check client.inputTokens == 0
    check client.outputTokens == 0
  
  test "Streaming mode configuration":
    let client = newLLMClient("openai", apiKey = "test", stream = true)
    check client.stream == true
  
  test "Model parameter is set":
    let client = newLLMClient("openai", apiKey = "test", model = "gpt-4")
    check client.model == "gpt-4"
  
  test "Temperature parameter is set":
    let client = newLLMClient("openai", apiKey = "test", temperature = 0.7)
    check client.temperature == 0.7
  
  test "Max tokens parameter is set":
    let client = newLLMClient("openai", apiKey = "test", maxTokens = 2000)
    check client.maxTokens == 2000
  
  test "Multiple clients can coexist":
    let client1 = newLLMClient("openai", apiKey = "test1", model = "gpt-3.5-turbo")
    let client2 = newLLMClient("anthropic", apiKey = "test2", model = "claude-3-opus-20240229")
    
    check client1.provider != client2.provider
    check client1.model != client2.model
  
  test "Client supports system prompts":
    let client = newLLMClient("openai", apiKey = "test")
    check client.systemPrompt == ""
    
    client.systemPrompt = "You are a helpful assistant"
    check client.systemPrompt == "You are a helpful assistant"

# Integration test with actual API (skipped in CI unless API key is present)
suite "LLM Integration Tests (requires API key)":
  test "OpenAI chat completion":
    let apiKey = getEnv("OPENAI_API_KEY")
    if apiKey == "":
      skip()
    else:
      let client = newLLMClient("openai", apiKey = apiKey, model = "gpt-3.5-turbo")
      let response = waitFor client.chat("Say 'Hello, World!' and nothing else")
      
      check response != ""
      check response.contains("Hello")
      check client.inputTokens > 0
      check client.outputTokens > 0
  
  test "Anthropic chat completion":
    let apiKey = getEnv("ANTHROPIC_API_KEY")
    if apiKey == "":
      skip()
    else:
      let client = newLLMClient("anthropic", apiKey = apiKey, model = "claude-3-opus-20240229")
      let response = waitFor client.chat("Say 'Hello' and nothing else")
      
      check response != ""
      check client.inputTokens > 0
  
  test "Google chat completion":
    let apiKey = getEnv("GOOGLE_API_KEY")
    if apiKey == "":
      skip()
    else:
      let client = newLLMClient("google", apiKey = apiKey, model = "gemini-pro")
      let response = waitFor client.chat("Say 'Hello' and nothing else")
      
      check response != ""
  
  test "Ollama chat completion":
    # Ollama requires local server running
    if not fileExists("/usr/local/bin/ollama") and not fileExists("C:\\Program Files\\Ollama\\ollama.exe"):
      skip()
    else:
      let client = newLLMClient("ollama", model = "llama2")
      try:
        let response = waitFor client.chat("Say 'Hello' and nothing else")
        check response != ""
      except LLMError:
        skip()  # Ollama server not running
  
  test "Chat with caching":
    let apiKey = getEnv("OPENAI_API_KEY")
    if apiKey == "":
      skip()
    else:
      let client = newLLMClient("openai", apiKey = apiKey, enableCache = true)
      
      let response1 = waitFor client.chat("What is 2+2?")
      let tokens1 = client.inputTokens + client.outputTokens
      
      client.resetTokens()
      let response2 = waitFor client.chat("What is 2+2?")
      let tokens2 = client.inputTokens + client.outputTokens
      
      check response1 == response2  # Cached response should be identical
      check tokens2 == 0  # Should use cache, no API call
  
  test "Streaming response":
    let apiKey = getEnv("OPENAI_API_KEY")
    if apiKey == "":
      skip()
    else:
      let client = newLLMClient("openai", apiKey = apiKey, stream = true)
      var chunks: seq[string] = @[]
      
      proc handleChunk(chunk: string) =
        chunks.add(chunk)
      
      waitFor client.chatStream("Count from 1 to 5", handleChunk)
      
      check chunks.len > 0
      check chunks.join("").len > 0
