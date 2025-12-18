## Live LLM Integration Tests
## 
## These tests run against a real Ollama instance.
## To run: nim c -r tests/test_llm_live.nim
## 
## Prerequisites:
## - Ollama must be running (http://localhost:11434)
## - At least one model must be available (e.g., granite4:tiny-h)

import unittest, asyncdispatch, json, strutils
import ../src/pocketflow

const TEST_MODEL = "granite4:tiny-h"  # Small, fast model for testing

suite "LLM Client - Live Ollama Tests":
  
  test "Initialize Ollama Client":
    let client = newLlmClient(
      provider = Ollama,
      model = TEST_MODEL
    )
    
    check client.provider == Ollama
    check client.baseUrl == "http://localhost:11434/v1"
    check client.model == TEST_MODEL
    check client.apiKey == ""
    
    client.close()

  test "Simple Generation":
    let client = newLlmClient(
      provider = Ollama,
      model = TEST_MODEL
    )
    defer: client.close()
    
    let response = waitFor client.generate("Say 'Hello' and nothing else.", temperature = 0.1)
    
    check response.len > 0
    check response.toLowerAscii().contains("hello")
    echo "  ✓ Response: ", response

  test "Chat with Messages":
    let client = newLlmClient(
      provider = Ollama,
      model = TEST_MODEL
    )
    defer: client.close()
    
    let messages = %*[
      {"role": "system", "content": "You are a helpful assistant. Be brief."},
      {"role": "user", "content": "What is 2+2? Answer with just the number."}
    ]
    
    let response = waitFor client.chat(messages, temperature = 0.1)
    
    check response.len > 0
    check response.contains("4")
    echo "  ✓ Response: ", response

  test "Multiple Turns Conversation":
    let client = newLlmClient(
      provider = Ollama,
      model = TEST_MODEL
    )
    defer: client.close()
    
    # First turn
    var messages = %*[
      {"role": "user", "content": "My name is Alice. Remember that."}
    ]
    var response = waitFor client.chat(messages)
    check response.len > 0
    echo "  ✓ Turn 1: ", response
    
    # Second turn - test memory
    messages.add(%*{"role": "assistant", "content": response})
    messages.add(%*{"role": "user", "content": "What is my name?"})
    response = waitFor client.chat(messages)
    check response.len > 0
    check response.toLowerAscii().contains("alice")
    echo "  ✓ Turn 2: ", response

  test "Temperature Control":
    let client = newLlmClient(
      provider = Ollama,
      model = TEST_MODEL
    )
    defer: client.close()
    
    # Low temperature (more deterministic)
    let response1 = waitFor client.generate("Count from 1 to 3.", temperature = 0.0)
    let response2 = waitFor client.generate("Count from 1 to 3.", temperature = 0.0)
    
    check response1.len > 0
    check response2.len > 0
    echo "  ✓ Low temp (0.0) Response 1: ", response1
    echo "  ✓ Low temp (0.0) Response 2: ", response2
    # Note: Responses may still vary slightly even at temp=0 due to sampling

  test "Error Handling - Invalid Model":
    let client = newLlmClient(
      provider = Ollama,
      model = "nonexistent-model-xyz123"
    )
    defer: client.close()
    
    var errorCaught = false
    try:
      discard waitFor client.generate("Hello")
    except Exception as e:
      errorCaught = true
      check e.msg.contains("failed") or e.msg.contains("error")
      echo "  ✓ Expected error: ", e.msg
    
    check errorCaught

  test "Custom BaseURL":
    # Test that we can set a custom base URL
    let client = newLlmClient(
      provider = Ollama,
      baseUrl = "http://localhost:11434/v1",
      model = TEST_MODEL
    )
    defer: client.close()
    
    check client.baseUrl == "http://localhost:11434/v1"
    
    let response = waitFor client.generate("Hi", temperature = 0.1)
    check response.len > 0
    echo "  ✓ Response with custom URL: ", response

  test "Integration with Node":
    # Test using LLM client within a PocketFlow node
    # Store the client in context to avoid closure capture issues
    var ctx = newPfContext()
    let client = newLlmClient(provider = Ollama, model = TEST_MODEL)
    defer: client.close()
    
    # Store client reference in params instead of closure capture
    var llmNode = newNode(
      prep = proc (ctx: PfContext, params: JsonNode): Future[JsonNode] {.async.} =
        # Just pass through the prompt
        return params
      ,
      exec = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
        # Use a fresh client for this execution to avoid GC-safety issues
        let execClient = newLlmClient(provider = Ollama, model = TEST_MODEL)
        defer: execClient.close()
        
        let prompt = prepRes["prompt"].getStr()
        let response = await execClient.generate(prompt, temperature = 0.1)
        return %* response
      ,
      post = proc (ctx: PfContext, params: JsonNode, prepRes: JsonNode, execRes: JsonNode): Future[string] {.async.} =
        ctx["llm_response"] = execRes
        return DefaultAction
    )
    
    llmNode.setParams(%* {"prompt": "Say 'test passed'"})
    discard waitFor llmNode.run(ctx)
    
    check ctx.hasKey("llm_response")
    check ctx["llm_response"].getStr().len > 0
    echo "  ✓ Node integration response: ", ctx["llm_response"].getStr()
