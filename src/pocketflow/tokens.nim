## Token counting and cost tracking for LLM operations
##
## Provides utilities to estimate token usage and associated costs
## for different LLM providers.

import tables, json

type
  TokenCounter* = object
    ## Counts tokens for different model families
  
  CostTracker* = ref object
    ## Tracks cumulative costs for LLM operations
    totalInputTokens*: int
    totalOutputTokens*: int
    totalCost*: float
    costByModel*: TableRef[string, float]
    tokensByModel*: TableRef[string, tuple[input: int, output: int]]

const ModelPricing = {
  # OpenAI pricing (per 1M tokens)
  "gpt-4": (input: 30.0, output: 60.0),
  "gpt-4-turbo": (input: 10.0, output: 30.0),
  "gpt-3.5-turbo": (input: 0.5, output: 1.5),
  "gpt-4o": (input: 2.5, output: 10.0),
  "gpt-4o-mini": (input: 0.15, output: 0.6),
  
  # Anthropic pricing (per 1M tokens)
  "claude-3-opus": (input: 15.0, output: 75.0),
  "claude-3-sonnet": (input: 3.0, output: 15.0),
  "claude-3-haiku": (input: 0.25, output: 1.25),
  "claude-3-5-sonnet": (input: 3.0, output: 15.0),
  
  # Google pricing (per 1M tokens)  "gemini-1.5-pro": (input: 1.25, output: 5.0),
  "gemini-1.5-flash": (input: 0.075, output: 0.3),
}.toTable

proc newCostTracker*(): CostTracker =
  ## Creates a new cost tracker
  result = CostTracker(
    totalInputTokens: 0,
    totalOutputTokens: 0,
    totalCost: 0.0,
    costByModel: newTable[string, float](),
    tokensByModel: newTable[string, tuple[input: int, output: int]]()
  )

proc estimateTokens*(text: string): int =
  ## Estimates token count for text (rough approximation)
  ## Uses ~4 characters per token as a rule of thumb
  result = max(1, text.len div 4)

proc trackUsage*(tracker: CostTracker, model: string, inputTokens: int, outputTokens: int) =
  ## Records token usage and calculates cost
  tracker.totalInputTokens += inputTokens
  tracker.totalOutputTokens += outputTokens
  
  if not tracker.tokensByModel.hasKey(model):
    tracker.tokensByModel[model] = (input: 0, output: 0)
  
  var current = tracker.tokensByModel[model]
  current.input += inputTokens
  current.output += outputTokens
  tracker.tokensByModel[model] = current
  
  # Calculate cost
  if ModelPricing.hasKey(model):
    let pricing = ModelPricing[model]
    let cost = (float(inputTokens) * pricing.input / 1_000_000.0) +
               (float(outputTokens) * pricing.output / 1_000_000.0)
    
    tracker.totalCost += cost
    if not tracker.costByModel.hasKey(model):
      tracker.costByModel[model] = 0.0
    tracker.costByModel[model] += cost

proc getSummary*(tracker: CostTracker): JsonNode =
  ## Returns a JSON summary of costs and usage
  result = %*{
    "total_input_tokens": tracker.totalInputTokens,
    "total_output_tokens": tracker.totalOutputTokens,
    "total_cost_usd": tracker.totalCost,
    "by_model": newJObject()
  }
  
  for model, tokens in tracker.tokensByModel:
    result["by_model"][model] = %*{
      "input_tokens": tokens.input,
      "output_tokens": tokens.output,
      "cost_usd": tracker.costByModel.getOrDefault(model, 0.0)
    }

proc reset*(tracker: CostTracker) =
  ## Resets all tracked costs and tokens
  tracker.totalInputTokens = 0
  tracker.totalOutputTokens = 0
  tracker.totalCost = 0.0
  tracker.costByModel.clear()
  tracker.tokensByModel.clear()

# Global cost tracker
var globalCostTracker* = newCostTracker()
