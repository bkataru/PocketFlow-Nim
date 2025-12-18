## PocketFlow Test Suite
## 
## Main test runner for all PocketFlow tests
## Run with: nim c -r tests/all_tests.nim

import unittest

# Import all test suites
import test_errors
import test_context
import test_cache
import test_tokens
import test_node
import test_flow
import test_observability
import test_advanced_nodes
import test_persistence
import test_benchmark
import test_rag
import test_llm
import test_integration

echo "\n==================================="
echo "PocketFlow Test Suite"
echo "==================================="
echo "Running all tests...\n"

# All tests are automatically run when imported
# The unittest module handles test execution

echo "\n==================================="
echo "All Tests Complete!"
echo "===================================\n"
