## Simple LLM Chat Example
##
## Demonstrates basic usage of PocketFlow with an LLM provider.

import asyncdispatch, json, os
import ../src/pocketflow

proc main() {.async.} =
  # Get API key from environment
  let apiKey = getEnv("OPENAI_API_KEY", "")
  if apiKey == "":
    echo "Please set OPENAI_API_KEY environment variable"
    return
  
  # Create LLM client
  let llm = newLlmClient(
    provider = OpenAI,
    apiKey = apiKey,
    model = "gpt-4o-mini"
  )
  
  # Create context
  let ctx = newPfContext()
  
  # Create a simple chat node
  let chatNode = newNode(
    exec = proc(ctx: PfContext, params: JsonNode, prepRes: JsonNode): Future[JsonNode] {.async.} =
      echo "Asking LLM..."
      let response = await llm.generate("Tell me an interesting fact about the Nim programming language")
      echo "\nLLM Response:"
      echo response
      return %response
  )
  
  # Run the flow
  let flow = newFlow(chatNode)
  discard await flow.internalRun(ctx)
  
  # Show cost tracking
  echo "\n=== Cost Summary ==="
  echo globalCostTracker.getSummary().pretty()
  
  llm.close()

when isMainModule:
  waitFor main()
