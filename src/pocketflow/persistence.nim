## State persistence module for PocketFlow
##
## Provides serialization and recovery of flow state for checkpointing
## and resumption of long-running workflows.

import json, os, times, strformat, strutils, tables
import context

type
  FlowState* = object
    ## Serializable state of a flow execution
    flowId*: string
    timestamp*: Time
    contextData*: JsonNode
    currentNodeIndex*: int
    completedNodes*: seq[string]
    metadata*: JsonNode
  
  StateStore* = ref object
    ## Storage backend for flow states
    storageDir*: string

proc newStateStore*(storageDir: string = ".pocketflow_state"): StateStore =
  ## Creates a new state store
  result = StateStore(storageDir: storageDir)
  if not dirExists(storageDir):
    createDir(storageDir)

proc captureState*(ctx: PfContext, flowId: string, metadata: JsonNode = newJObject()): FlowState =
  ## Captures the current state of a flow
  # Convert the TableRef to a JObject
  var contextJson = newJObject()
  for key, val in tables.pairs(ctx.store):
    contextJson[key] = val
  
  result = FlowState(
    flowId: flowId,
    timestamp: getTime(),
    contextData: contextJson,
    currentNodeIndex: 0,
    completedNodes: @[],
    metadata: metadata
  )

proc saveState*(store: StateStore, state: FlowState) =
  ## Saves a flow state to disk
  let filename = fmt"{state.flowId}_{state.timestamp.toUnix()}.json"
  let filepath = store.storageDir / filename
  
  let stateJson = %*{
    "flowId": state.flowId,
    "timestamp": $state.timestamp,
    "contextData": state.contextData,
    "currentNodeIndex": state.currentNodeIndex,
    "completedNodes": state.completedNodes,
    "metadata": state.metadata
  }
  
  writeFile(filepath, stateJson.pretty())

proc loadState*(store: StateStore, flowId: string): FlowState =
  ## Loads the most recent state for a flow
  var latestFile = ""
  var latestTime = Time()
  
  for file in walkFiles(store.storageDir / fmt"{flowId}_*.json"):
    let parts = file.splitFile()
    let timeStr = parts.name.split("_")[^1]
    try:
      let time = fromUnix(parseInt(timeStr))
      if time > latestTime:
        latestTime = time
        latestFile = file
    except:
      continue
  
  if latestFile == "":
    raise newException(IOError, fmt"No state found for flow: {flowId}")
  
  let content = readFile(latestFile)
  let json = parseJson(content)
  
  result = FlowState(
    flowId: json["flowId"].getStr(),
    timestamp: parseTime(json["timestamp"].getStr(), "yyyy-MM-dd'T'HH:mm:sszzz", utc()),
    contextData: json["contextData"],
    currentNodeIndex: json["currentNodeIndex"].getInt(),
    completedNodes: @[],
    metadata: json.getOrDefault("metadata")
  )
  
  for node in json["completedNodes"]:
    result.completedNodes.add(node.getStr())

proc restoreContext*(ctx: PfContext, state: FlowState) =
  ## Restores context from saved state
  for key, value in state.contextData:
    ctx[key] = value

proc deleteState*(store: StateStore, flowId: string) =
  ## Deletes all saved states for a flow
  for file in walkFiles(store.storageDir / fmt"{flowId}_*.json"):
    removeFile(file)

proc listStates*(store: StateStore): seq[tuple[flowId: string, timestamp: Time]] =
  ## Lists all saved flow states
  result = @[]
  for file in walkFiles(store.storageDir / "*.json"):
    let parts = file.splitFile()
    let nameParts = parts.name.split("_")
    if nameParts.len >= 2:
      let flowId = nameParts[0..^2].join("_")
      try:
        let timestamp = fromUnix(parseInt(nameParts[^1]))
        result.add((flowId: flowId, timestamp: timestamp))
      except:
        continue

# Global state store
var globalStateStore* = newStateStore()
