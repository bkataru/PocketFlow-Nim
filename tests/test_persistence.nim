import unittest
import json
import os
import times
import ../src/pocketflow/persistence
import ../src/pocketflow/context

suite "Persistence Tests":
  setup:
    # Clean up any existing test state files
    let testDir = ".pocketflow_test_state"
    if dirExists(testDir):
      removeDir(testDir)

  teardown:
    # Clean up after tests
    let testDir = ".pocketflow_test_state"
    if dirExists(testDir):
      removeDir(testDir)

  test "Create state store":
    let store = newStateStore(".pocketflow_test_state")
    check store != nil
    check dirExists(".pocketflow_test_state")

  test "Capture state from context":
    let ctx = newPfContext()
    ctx["key1"] = %"value1"
    ctx["key2"] = %42
    ctx["nested"] = %*{"a": 1, "b": 2}

    let state = captureState(ctx, "test_flow_1")
    check state.flowId == "test_flow_1"
    check state.contextData["key1"].getStr() == "value1"
    check state.contextData["key2"].getInt() == 42
    check state.contextData["nested"]["a"].getInt() == 1

  test "Save and load state":
    let store = newStateStore(".pocketflow_test_state")

    # Create context with data
    let ctx = newPfContext()
    ctx["message"] = %"Hello"
    ctx["count"] = %100

    # Capture and save state
    let state = captureState(ctx, "persistence_test")
    saveState(store, state)

    # Load state back
    let loadedState = loadState(store, "persistence_test")
    check loadedState.flowId == "persistence_test"
    check loadedState.contextData["message"].getStr() == "Hello"
    check loadedState.contextData["count"].getInt() == 100

  test "Restore context from state":
    let store = newStateStore(".pocketflow_test_state")

    # Create and save original context
    let originalCtx = newPfContext()
    originalCtx["restored_key"] = %"restored_value"
    originalCtx["restored_num"] = %999

    let state = captureState(originalCtx, "restore_test")
    saveState(store, state)

    # Load state and restore to new context
    let loadedState = loadState(store, "restore_test")
    let newCtx = newPfContext()
    restoreContext(newCtx, loadedState)

    check newCtx["restored_key"].getStr() == "restored_value"
    check newCtx["restored_num"].getInt() == 999

  test "Delete state":
    let store = newStateStore(".pocketflow_test_state")

    # Create and save state
    let ctx = newPfContext()
    ctx["temp"] = %"temporary"
    let state = captureState(ctx, "delete_test")
    saveState(store, state)

    # Verify it exists
    let loaded = loadState(store, "delete_test")
    check loaded.flowId == "delete_test"

    # Delete it
    deleteState(store, "delete_test")

    # Verify it's gone (should raise exception or return empty)
    try:
      discard loadState(store, "delete_test")
      check false  # Should not reach here
    except:
      check true  # Expected exception

  test "List states":
    let store = newStateStore(".pocketflow_test_state")

    # Create multiple states
    for i in 1..3:
      let ctx = newPfContext()
      ctx["index"] = %i
      let state = captureState(ctx, "list_test_" & $i)
      saveState(store, state)

    let states = listStates(store)
    check states.len == 3

  test "State with metadata":
    let ctx = newPfContext()
    ctx["data"] = %"test"

    let metadata = %*{"version": "1.0", "author": "test"}
    let state = captureState(ctx, "metadata_test", metadata)

    check state.metadata["version"].getStr() == "1.0"
    check state.metadata["author"].getStr() == "test"

  test "State timestamp is recorded":
    let ctx = newPfContext()
    ctx["timestamp_test"] = %true

    let beforeCapture = getTime()
    let state = captureState(ctx, "timestamp_flow")
    let afterCapture = getTime()

    check state.timestamp >= beforeCapture
    check state.timestamp <= afterCapture

  test "Multiple saves overwrite previous state":
    let store = newStateStore(".pocketflow_test_state")

    # Save first version
    let ctx1 = newPfContext()
    ctx1["version"] = %"v1"
    let state1 = captureState(ctx1, "overwrite_test")
    saveState(store, state1)

    # Save second version with same flowId
    let ctx2 = newPfContext()
    ctx2["version"] = %"v2"
    let state2 = captureState(ctx2, "overwrite_test")
    saveState(store, state2)

    # Load should return v2
    let loaded = loadState(store, "overwrite_test")
    check loaded.contextData["version"].getStr() == "v2"
