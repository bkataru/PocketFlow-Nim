import unittest
import asyncdispatch
import json
import os
import ../src/pocketflow/llm
import ../src/pocketflow/cache
import ../src/pocketflow/tokens

suite "LLM Tests":
  test "Create LLM client with default OpenAI":
    let client = newLlmClient()
    check client != nil
    check client.provider == OpenAI

  test "Create LLM client with explicit provider":
    let client = newLlmClient(provider = Ollama)
    check client != nil
    check client.provider == Ollama

  test "Create LLM client with Anthropic":
    let client = newLlmClient(provider = Anthropic)
    check client != nil
    check client.provider == Anthropic

  test "Create LLM client with Google":
    let client = newLlmClient(provider = Google)
    check client != nil
    check client.provider == Google

  test "Create LLM client with custom base URL":
    let client = newLlmClient(
      provider = Custom,
      baseUrl = "http://localhost:8080/v1"
    )
    check client != nil
    check client.baseUrl == "http://localhost:8080/v1"

  test "Create LLM client with API key":
    let client = newLlmClient(
      provider = OpenAI,
      apiKey = "test-api-key-12345"
    )
    check client != nil
    check client.apiKey == "test-api-key-12345"

  test "Create LLM client with model":
    let client = newLlmClient(
      provider = OpenAI,
      model = "gpt-4"
    )
    check client != nil
    check client.model == "gpt-4"

  test "Create LLM client with cost tracker":
    let tracker = newCostTracker()
    let client = newLlmClient(
      provider = OpenAI,
      costTracker = tracker
    )
    check client != nil
    check client.costTracker != nil

  test "Create LLM client with cache":
    let responseCache = newCache()
    let client = newLlmClient(
      provider = OpenAI,
      cache = responseCache
    )
    check client != nil
    check client.cache != nil

  test "LlmOptions default values":
    var opts: LlmOptions
    check opts.temperature == 0.0
    check opts.maxTokens == 0
    check opts.topP == 0.0
    check opts.stream == false
    check opts.useCache == false
    check opts.timeout == 0

  test "LlmOptions with custom values":
    let opts = LlmOptions(
      temperature: 0.7,
      maxTokens: 1000,
      topP: 0.95,
      stream: false,
      useCache: true,
      timeout: 30000
    )
    check opts.temperature == 0.7
    check opts.maxTokens == 1000
    check opts.topP == 0.95
    check opts.useCache == true
    check opts.timeout == 30000

  test "All providers are supported":
    # Test that all provider enum values can be used
    check $OpenAI == "OpenAI"
    check $Ollama == "Ollama"
    check $Anthropic == "Anthropic"
    check $Google == "Google"
    check $Custom == "Custom"

  test "Full client configuration":
    let tracker = newCostTracker()
    let responseCache = newCache()

    let client = newLlmClient(
      provider = OpenAI,
      baseUrl = "https://api.openai.com/v1",
      apiKey = "sk-test-key",
      model = "gpt-4-turbo",
      costTracker = tracker,
      cache = responseCache
    )

    check client != nil
    check client.provider == OpenAI
    check client.baseUrl == "https://api.openai.com/v1"
    check client.apiKey == "sk-test-key"
    check client.model == "gpt-4-turbo"
    check client.costTracker == tracker
    check client.cache == responseCache
