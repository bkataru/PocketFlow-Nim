## RAG (Retrieval-Augmented Generation) Example
##
## Demonstrates document chunking, embedding, retrieval, and generation.

import asyncdispatch, json, os, strutils
import ../src/pocketflow

const SampleDocument = """
Nim is a statically typed compiled systems programming language. It combines 
successful concepts from mature languages like Python, Ada and Modula.

Nim generates native dependency-free executables. These executables are small 
and allow easy redistribution. Nim supports Windows, macOS, Linux, and many 
more platforms.

The Nim compiler and generated executables support all major platforms like 
Windows, Linux, BSD, and macOS. Nim's memory management is deterministic and 
customizable with destructors and move semantics.

Nim is efficient. Nim programs compile to optimized C, C++, or JavaScript code. 
The generated code is fast and has a small memory footprint.
"""

proc main() {.async.} =
  let apiKey = getEnv("OPENAI_API_KEY", "")
  if apiKey == "":
    echo "Please set OPENAI_API_KEY environment variable"
    return
  
  echo "=== PocketFlow RAG Example ===\n"
  
  # Create LLM client
  let llm = newLlmClient(provider = OpenAI, apiKey = apiKey)
  let ctx = newPfContext()
  
  # Step 1: Chunk the document
  echo "Step 1: Chunking document..."
  let options = newChunkingOptions(strategy = FixedSize, chunkSize = 200, chunkOverlap = 50)
  var chunks = chunkDocument(SampleDocument, options)
  echo fmt"Created {chunks.len} chunks"
  
  # Step 2: Generate embeddings for chunks
  echo "\nStep 2: Generating embeddings..."
  let chunkTexts = chunks.mapIt(it.text)
  let embeddings = await llm.embeddings(chunkTexts)
  
  for i, embedding in embeddings:
    chunks[i].embedding = embedding
  
  echo fmt"Generated {embeddings.len} embeddings"
  
  # Step 3: Create query and find relevant chunks
  echo "\nStep 3: Searching for relevant chunks..."
  let query = "How fast is Nim?"
  let queryEmbedding = (await llm.embeddings(@[query]))[0]
  
  let topChunks = findTopK(queryEmbedding, chunks, k = 2)
  
  echo fmt"\nTop {topChunks.len} chunks for query '{query}':"
  for i, (chunk, score) in topChunks:
    echo fmt"\n[{i+1}] (similarity: {score:.3f})"
    echo chunk.text.strip()
  
  # Step 4: Generate answer using retrieved context
  echo "\n\nStep 4: Generating answer..."
  let context = topChunks.mapIt(it.chunk.text).join("\n\n")
  let prompt = fmt"""
Based on the following context, answer the question.

Context:
{context}

Question: {query}

Answer:"""
  
  let answer = await llm.generate(prompt)
  echo "\nAnswer:"
  echo answer
  
  echo "\n=== Cost Summary ==="
  echo globalCostTracker.getSummary().pretty()
  
  llm.close()

when isMainModule:
  waitFor main()
