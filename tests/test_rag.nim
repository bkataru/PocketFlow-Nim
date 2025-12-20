import unittest
import strutils
import ../src/pocketflow/rag

suite "RAG Tests":
  test "Chunking options creation":
    let opts = newChunkingOptions(
      strategy = FixedSize,
      chunkSize = 100,
      chunkOverlap = 20
    )
    check opts.strategy == FixedSize
    check opts.chunkSize == 100
    check opts.chunkOverlap == 20

  test "Chunk by fixed size":
    let text = "This is a test. " & "More text here. " & "Even more content. " & "Final sentence."
    let chunks = chunkByFixedSize(text, chunkSize = 20, overlap = 5)
    check chunks.len > 0
    # Each chunk should have text
    for chunk in chunks:
      check chunk.text.len > 0

  test "Chunk by sentences":
    let text = "First sentence. Second sentence. Third sentence. Fourth sentence. Fifth sentence. Sixth sentence."
    let chunks = chunkBySentences(text, maxSentences = 2, overlap = 1)
    check chunks.len > 0
    for chunk in chunks:
      check chunk.text.len > 0

  test "Chunk by paragraphs":
    let text = """First paragraph here.

Second paragraph here.

Third paragraph here.

Fourth paragraph here."""
    let chunks = chunkByParagraphs(text, maxParagraphs = 2, overlap = 1)
    check chunks.len > 0

  test "Chunk document with fixed size options":
    let text = "Lorem ipsum dolor sit amet. Consectetur adipiscing elit. Sed do eiusmod tempor."
    let opts = newChunkingOptions(strategy = FixedSize, chunkSize = 30, chunkOverlap = 5)
    let chunks = chunkDocument(text, opts)
    check chunks.len > 0

  test "Cosine similarity":
    let a = @[1.0, 0.0, 0.0]
    let b = @[1.0, 0.0, 0.0]
    let similarity = cosineSimilarity(a, b)
    check similarity > 0.99  # Should be ~1.0

    let c = @[0.0, 1.0, 0.0]
    let orthogonal = cosineSimilarity(a, c)
    check orthogonal < 0.01  # Should be ~0.0

  test "Cosine similarity with different vectors":
    let a = @[1.0, 1.0, 0.0]
    let b = @[1.0, 0.0, 0.0]
    let similarity = cosineSimilarity(a, b)
    # cos(45°) ≈ 0.707
    check similarity > 0.7
    check similarity < 0.72

  test "Find top K chunks":
    var chunks: seq[Chunk] = @[]
    # Create chunks with mock embeddings
    chunks.add(Chunk(text: "Chunk A", embedding: @[1.0, 0.0, 0.0]))
    chunks.add(Chunk(text: "Chunk B", embedding: @[0.0, 1.0, 0.0]))
    chunks.add(Chunk(text: "Chunk C", embedding: @[0.9, 0.1, 0.0]))

    let query = @[1.0, 0.0, 0.0]
    let topK = findTopK(query, chunks, k = 2)

    check topK.len == 2
    # Chunk A should be first (exact match)
    check topK[0].chunk.text == "Chunk A"
    # Chunk C should be second (similar)
    check topK[1].chunk.text == "Chunk C"

  test "Rerank chunks":
    var chunks: seq[Chunk] = @[]
    chunks.add(Chunk(text: "Python programming language tutorial"))
    chunks.add(Chunk(text: "Java programming language tutorial"))
    chunks.add(Chunk(text: "Nimrod programming language tutorial"))

    # Query words must be > 3 chars to be counted
    let reranked = rerankChunks(chunks, "Nimrod language")
    check reranked.len == 3
    # The chunk with "Nimrod" should be ranked higher
    check reranked[0].text.contains("Nimrod")
