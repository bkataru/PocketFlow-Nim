## RAG (Retrieval-Augmented Generation) utilities
##
## Provides document chunking, embedding, and retrieval capabilities.

import strutils, sequtils, algorithm, math, json

type
  Chunk* = object
    ## A document chunk with metadata
    text*: string
    metadata*: JsonNode
    embedding*: seq[float]
    index*: int
  
  ChunkingStrategy* = enum
    ## Strategy for splitting documents into chunks
    FixedSize,        # Fixed character count
    Sentences,        # By sentences
    Paragraphs,       # By paragraphs
    Semantic          # By semantic similarity (requires embeddings)
  
  ChunkingOptions* = object
    ## Options for document chunking
    strategy*: ChunkingStrategy
    chunkSize*: int
    chunkOverlap*: int
    preserveStructure*: bool

proc newChunkingOptions*(
  strategy: ChunkingStrategy = FixedSize,
  chunkSize: int = 1000,
  chunkOverlap: int = 200
): ChunkingOptions =
  ## Creates default chunking options
  result = ChunkingOptions(
    strategy: strategy,
    chunkSize: chunkSize,
    chunkOverlap: chunkOverlap,
    preserveStructure: true
  )

proc chunkByFixedSize*(text: string, chunkSize: int, overlap: int): seq[Chunk] =
  ## Chunks text into fixed-size pieces with overlap
  result = @[]
  var idx = 0
  var chunkIdx = 0
  
  while idx < text.len:
    let endIdx = min(idx + chunkSize, text.len)
    let chunkText = text[idx..<endIdx]
    
    result.add(Chunk(
      text: chunkText,
      metadata: %*{"start": idx, "end": endIdx},
      embedding: @[],
      index: chunkIdx
    ))
    
    idx += chunkSize - overlap
    chunkIdx += 1

proc chunkBySentences*(text: string, maxSentences: int = 5, overlap: int = 1): seq[Chunk] =
  ## Chunks text by sentences
  result = @[]
  
  # Simple sentence splitter (can be enhanced with regex)
  var sentences: seq[string] = @[]
  var current = ""
  
  for ch in text:
    current.add(ch)
    if ch in {'.', '!', '?'}:
      sentences.add(current.strip())
      current = ""
  
  if current.len > 0:
    sentences.add(current.strip())
  
  var idx = 0
  var chunkIdx = 0
  
  while idx < sentences.len:
    let endIdx = min(idx + maxSentences, sentences.len)
    let chunkText = sentences[idx..<endIdx].join(" ")
    
    result.add(Chunk(
      text: chunkText,
      metadata: %*{"sentence_start": idx, "sentence_end": endIdx},
      embedding: @[],
      index: chunkIdx
    ))
    
    idx += maxSentences - overlap
    chunkIdx += 1

proc chunkByParagraphs*(text: string, maxParagraphs: int = 3, overlap: int = 1): seq[Chunk] =
  ## Chunks text by paragraphs
  result = @[]
  let paragraphs = text.split("\n\n").filterIt(it.strip().len > 0)
  
  var idx = 0
  var chunkIdx = 0
  
  while idx < paragraphs.len:
    let endIdx = min(idx + maxParagraphs, paragraphs.len)
    let chunkText = paragraphs[idx..<endIdx].join("\n\n")
    
    result.add(Chunk(
      text: chunkText,
      metadata: %*{"paragraph_start": idx, "paragraph_end": endIdx},
      embedding: @[],
      index: chunkIdx
    ))
    
    idx += maxParagraphs - overlap
    chunkIdx += 1

proc chunkDocument*(text: string, options: ChunkingOptions): seq[Chunk] =
  ## Chunks a document according to the specified strategy
  case options.strategy
  of FixedSize:
    result = chunkByFixedSize(text, options.chunkSize, options.chunkOverlap)
  of Sentences:
    result = chunkBySentences(text, options.chunkSize div 100, options.chunkOverlap)
  of Paragraphs:
    result = chunkByParagraphs(text, options.chunkSize div 500, options.chunkOverlap)
  of Semantic:
    # For now, fallback to fixed size (semantic chunking requires embeddings)
    result = chunkByFixedSize(text, options.chunkSize, options.chunkOverlap)

proc cosineSimilarity*(a, b: seq[float]): float =
  ## Computes cosine similarity between two vectors
  if a.len != b.len or a.len == 0:
    return 0.0
  
  var dotProduct = 0.0
  var normA = 0.0
  var normB = 0.0
  
  for i in 0..<a.len:
    dotProduct += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  
  if normA == 0.0 or normB == 0.0:
    return 0.0
  
  return dotProduct / (sqrt(normA) * sqrt(normB))

proc findTopK*(query: seq[float], chunks: seq[Chunk], k: int = 5): seq[tuple[chunk: Chunk, score: float]] =
  ## Finds the top-k most similar chunks to a query embedding
  var scored: seq[tuple[chunk: Chunk, score: float]] = @[]
  
  for chunk in chunks:
    if chunk.embedding.len > 0:
      let score = cosineSimilarity(query, chunk.embedding)
      scored.add((chunk: chunk, score: score))
  
  # Sort by score descending
  scored.sort(proc(a, b: tuple[chunk: Chunk, score: float]): int =
    if a.score > b.score: -1
    elif a.score < b.score: 1
    else: 0
  )
  
  return scored[0..<min(k, scored.len)]

proc rerankChunks*(chunks: seq[Chunk], query: string): seq[Chunk] =
  ## Reranks chunks based on query relevance (simple keyword-based)
  var scored: seq[tuple[chunk: Chunk, score: int]] = @[]
  let queryWords = query.toLower().split().filterIt(it.len > 3)
  
  for chunk in chunks:
    var score = 0
    let chunkLower = chunk.text.toLower()
    
    for word in queryWords:
      score += chunkLower.count(word)
    
    scored.add((chunk: chunk, score: score))
  
  scored.sort(proc(a, b: tuple[chunk: Chunk, score: int]): int =
    b.score - a.score
  )
  
  return scored.mapIt(it.chunk)
