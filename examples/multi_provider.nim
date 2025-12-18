## Multi-Provider Comparison Example
##
## Demonstrates using multiple LLM providers and comparing their responses.

import asyncdispatch, json, os, times, strformat
import ../src/pocketflow

proc compareLLMs() {.async.} =
  echo "=== Multi-Provider LLM Comparison ===\n"
  
  let openaiKey = getEnv("OPENAI_API_KEY", "")
  let anthropicKey = getEnv("ANTHROPIC_API_KEY", "")
  let googleKey = getEnv("GOOGLE_API_KEY", "")
  
  # Create clients for different providers
  var clients: seq[tuple[name: string, client: LlmClient]] = @[]
  
  if openaiKey != "":
    clients.add(("OpenAI GPT-4o-mini", newLlmClient(OpenAI, apiKey = openaiKey, model = "gpt-4o-mini")))
  
  if anthropicKey != "":
    clients.add(("Claude 3.5 Sonnet", newLlmClient(Anthropic, apiKey = anthropicKey)))
  
  if googleKey != "":
    clients.add(("Gemini 1.5 Flash", newLlmClient(Google, apiKey = googleKey)))
  
  # Always available locally
  clients.add(("Ollama Llama3", newLlmClient(Ollama, model = "llama3")))
  
  if clients.len == 0:
    echo "No API keys found. Set OPENAI_API_KEY, ANTHROPIC_API_KEY, or GOOGLE_API_KEY"
    return
  
  let prompt = "In exactly 2 sentences, explain what makes the Nim programming language unique."
  
  echo fmt"Prompt: {prompt}\n"
  echo "=" .repeat(80)
  echo ""
  
  # Query all providers in parallel
  var futures: seq[Future[tuple[name: string, response: string, duration: float]]] = @[]
  
  for (name, client) in clients:
    futures.add(
      (proc(): Future[tuple[name: string, response: string, duration: float]] {.async.} =
        let start = cpuTime()
        try:
          let response = await client.generate(prompt, temperature = 0.7)
          let duration = (cpuTime() - start) * 1000  # Convert to ms
          return (name: name, response: response, duration: duration)
        except Exception as e:
          return (name: name, response: fmt"Error: {e.msg}", duration: 0.0)
      )()
    )
  
  # Wait for all responses
  let results = await all(futures)
  
  # Display results
  for i, result in results:
    echo fmt"[{i + 1}] {result.name}"
    echo fmt"    Duration: {result.duration:.0f}ms"
    echo ""
    # Word wrap the response
    var words = result.response.split()
    var line = "    "
    for word in words:
      if line.len + word.len + 1 > 80:
        echo line
        line = "    " & word
      else:
        if line.len > 4:
          line &= " "
        line &= word
    if line.len > 4:
      echo line
    echo ""
    echo "-" .repeat(80)
    echo ""
  
  # Show cost comparison
  echo "\n=== Cost Comparison ==="
  echo globalCostTracker.getSummary().pretty()
  
  # Cleanup
  for (_, client) in clients:
    client.close()

when isMainModule:
  waitFor compareLLMs()
