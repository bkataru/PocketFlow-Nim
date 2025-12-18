import unittest
import asyncdispatch
import json
import ../src/pocketflow/[context, rag]

suite "RAG Tests":
  test "Create embeddings from text":
    let text = "This is a test document"
    let embeddings = createEmbeddings(text, model = "test")
    check embeddings.len > 0
  
  test "Fixed chunking strategy":
    let text = "This is a long document. " & "It has multiple sentences. ".repeat(10)
    let chunks = chunkText(text, strategy = ChunkingStrategy.Fixed, chunkSize = 50)
    
    check chunks.len > 0
    for chunk in chunks:
      check chunk.text.len <= 50
  
  test "Sentence chunking strategy":
    let text = "First sentence. Second sentence. Third sentence. Fourth sentence."
    let chunks = chunkText(text, strategy = ChunkingStrategy.Sentence, chunkSize = 2)
    
    check chunks.len > 0
    # Each chunk should contain approximately 2 sentences
  
  test "Paragraph chunking strategy":
    let text = """Paragraph one.
    
Paragraph two.

Paragraph three."""
    let chunks = chunkText(text, strategy = ChunkingStrategy.Paragraph)
    
    check chunks.len >= 3
  
  test "Semantic chunking strategy":
    let text = """Introduction to the topic.
    
The main body contains important information about the subject.
This is related to the previous point.

Conclusion wraps up the discussion."""
    
    let chunks = chunkText(text, strategy = ChunkingStrategy.Semantic)
    check chunks.len > 0
  
  test "Retrieve similar chunks":
    let documents = @[
      "The quick brown fox jumps over the lazy dog",
      "A fast auburn fox leaps above a sleepy canine",
      "Machine learning is a subset of artificial intelligence",
      "Deep learning uses neural networks with multiple layers"
    ]
    
    var chunks: seq[Chunk] = @[]
    for i, doc in documents:
      let embedding = createEmbeddings(doc)
      chunks.add(Chunk(
        text: doc,
        embedding: embedding,
        metadata: %*{"index": i}
      ))
    
    let query = "fox jumping over dog"
    let queryEmbedding = createEmbeddings(query)
    
    let results = retrieveSimilar(queryEmbedding, chunks, topK = 2)
    
    check results.len == 2
    # First two documents should be more similar to query
    check results[0].text.contains("fox") or results[0].text.contains("dog")
  
  test "Cosine similarity calculation":
    let vec1 = @[1.0, 0.0, 0.0]
    let vec2 = @[1.0, 0.0, 0.0]
    let sim = cosineSimilarity(vec1, vec2)
    check sim > 0.99  # Should be very similar (nearly 1.0)
  
  test "Cosine similarity of orthogonal vectors":
    let vec1 = @[1.0, 0.0, 0.0]
    let vec2 = @[0.0, 1.0, 0.0]
    let sim = cosineSimilarity(vec1, vec2)
    check sim < 0.01  # Should be nearly 0
  
  test "Empty text returns empty embeddings":
    let embeddings = createEmbeddings("")
    check embeddings.len == 0 or embeddings.allIt(it == 0.0)
  
  test "Chunk metadata is preserved":
    let chunk = Chunk(
      text: "Test text",
      embedding: @[0.1, 0.2, 0.3],
      metadata: %*{"source": "document.txt", "page": 5}
    )
    
    check chunk.metadata["source"].getStr() == "document.txt"
    check chunk.metadata["page"].getInt() == 5
  
  test "Retrieve with no chunks returns empty":
    let queryEmbedding = @[1.0, 2.0, 3.0]
    let chunks: seq[Chunk] = @[]
    let results = retrieveSimilar(queryEmbedding, chunks, topK = 5)
    check results.len == 0
  
  test "Retrieve more than available returns all":
    var chunks: seq[Chunk] = @[]
    for i in 0..<3:
      chunks.add(Chunk(
        text: "Document " & $i,
        embedding: @[float(i), 0.0, 0.0],
        metadata: %*{"index": i}
      ))
    
    let queryEmbedding = @[1.0, 0.0, 0.0]
    let results = retrieveSimilar(queryEmbedding, chunks, topK = 10)
    check results.len == 3  # Only 3 chunks available
  
  test "Different chunking sizes produce different results":
    let text = "Word ".repeat(100)
    
    let chunks1 = chunkText(text, strategy = ChunkingStrategy.Fixed, chunkSize = 50)
    let chunks2 = chunkText(text, strategy = ChunkingStrategy.Fixed, chunkSize = 100)
    
    # Smaller chunks should produce more chunks
    check chunks1.len > chunks2.len
  
  test "Overlapping chunks":
    let text = "This is sentence one. This is sentence two. This is sentence three."
    let chunks = chunkText(text, strategy = ChunkingStrategy.Sentence, overlap = 10)
    
    check chunks.len > 0
    # Overlapping chunks should share some content
  
  test "Chunk with custom metadata":
    let text = "Test document"
    var chunks = chunkText(text, strategy = ChunkingStrategy.Fixed, chunkSize = 100)
    
    for i, chunk in chunks.mpairs:
      chunk.metadata = %*{
        "chunk_id": i,
        "source": "test.txt",
        "timestamp": "2024-01-01"
      }
    
    check chunks[0].metadata["chunk_id"].getInt() == 0
    check chunks[0].metadata["source"].getStr() == "test.txt"
