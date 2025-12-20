# Package

version       = "0.2.0"
author        = "PocketFlow Contributors"
description   = "A minimalist flow-based agent framework with LLM integration, RAG capabilities, and advanced orchestration"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task test, "Run all tests":
  exec "nim c -r tests/all_tests.nim"

task test_unit, "Run unit tests only":
  echo "Running unit tests..."
  exec "nim c -r tests/test_context.nim"
  exec "nim c -r tests/test_errors.nim"
  exec "nim c -r tests/test_cache.nim"
  exec "nim c -r tests/test_tokens.nim"
  exec "nim c -r tests/test_node.nim"
  exec "nim c -r tests/test_flow.nim"
  exec "nim c -r tests/test_observability.nim"
  exec "nim c -r tests/test_advanced_nodes.nim"
  exec "nim c -r tests/test_persistence.nim"
  exec "nim c -r tests/test_benchmark.nim"
  exec "nim c -r tests/test_rag.nim"

task test_integration, "Run integration tests":
  exec "nim c -r tests/test_integration.nim"

task testlive, "Run live LLM tests (requires API keys)":
  exec "nim c -r tests/test_llm.nim"

task test_old, "Run old test suite":
  exec "nim c -r tests/test_pocketflow.nim"
  exec "nim c -r tests/test_llm_live.nim"

task docs, "Generate documentation":
  mkDir("docs")
  exec "nim doc --outdir:docs src/pocketflow.nim"
  exec "nim doc --outdir:docs src/pocketflow/context.nim"
  exec "nim doc --outdir:docs src/pocketflow/node.nim"
  exec "nim doc --outdir:docs src/pocketflow/flow.nim"
  exec "nim doc --outdir:docs src/pocketflow/llm.nim"
  exec "nim doc --outdir:docs src/pocketflow/errors.nim"
  exec "nim doc --outdir:docs src/pocketflow/cache.nim"
  exec "nim doc --outdir:docs src/pocketflow/tokens.nim"
  exec "nim doc --outdir:docs src/pocketflow/observability.nim"
  exec "nim doc --outdir:docs src/pocketflow/rag.nim"
  exec "nim doc --outdir:docs src/pocketflow/advanced_nodes.nim"
  exec "nim doc --outdir:docs src/pocketflow/persistence.nim"
  exec "nim doc --outdir:docs src/pocketflow/benchmark.nim"
  echo "Documentation generated in docs/"

task examples, "Build all examples":
  exec "nim c examples/simple_chat.nim"
  exec "nim c examples/rag_example.nim"
  exec "nim c examples/advanced_flow.nim"
  exec "nim c examples/multi_provider.nim"
  exec "nim c examples/benchmarks.nim"

task clean, "Clean build artifacts":
  exec "rm -rf nimcache/"
  exec "rm -rf docs/"
  exec "rm -f tests/test_pocketflow"
  exec "rm -f tests/test_llm_live"
  exec "rm -f examples/simple_chat"
  exec "rm -f examples/rag_example"
  exec "rm -f examples/advanced_flow"
