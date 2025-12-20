"""Build vector index from scores using Haystack."""

from haystack import Document
from haystack.components.embedders import SentenceTransformersDocumentEmbedder
from haystack_integrations.document_stores.chroma import ChromaDocumentStore

from .. import config, db


def make_searchable_text(score: dict) -> str:
    """Convert score metadata to searchable text.

    This text gets embedded into vectors. Format it to match
    how users will search.
    """
    parts = [score.get("title", "")]

    if score.get("composer"):
        parts.append(f"by {score['composer']}")

    if score.get("instruments"):
        parts.append(f"for {score['instruments']}")

    if score.get("voicing"):
        parts.append(f"{score['voicing']} voicing")

    if score.get("genres"):
        # Genres are stored as "Genre1-Genre2-Genre3"
        parts.append(score["genres"].replace("-", ", "))

    if score.get("description"):
        # Truncate long descriptions
        parts.append(score["description"][:200])

    return ". ".join(filter(None, parts))


def build_index(limit: int = 100):
    """Build vector index from scores.

    Args:
        limit: Number of scores to index (use -1 for all)
    """
    # Fetch scores
    print(f"Fetching scores (limit={limit})...")
    if limit == -1:
        scores = db.get_all_scores()
    else:
        scores = db.get_scores(limit=limit)
    print(f"Got {len(scores)} scores")

    # Create Haystack documents
    documents = []
    for score in scores:
        text = make_searchable_text(score)
        doc = Document(
            content=text,
            meta={
                "score_id": score["id"],
                "title": score.get("title"),
                "composer": score.get("composer"),
            }
        )
        documents.append(doc)

    print(f"Created {len(documents)} documents")

    # Initialize ChromaDB
    config.CHROMA_PATH.mkdir(parents=True, exist_ok=True)
    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    # Initialize embedder
    print(f"Loading embedding model: {config.EMBEDDING_MODEL}")
    embedder = SentenceTransformersDocumentEmbedder(model=config.EMBEDDING_MODEL)
    embedder.warm_up()

    # Embed documents
    print("Embedding documents (this may take a while)...")
    result = embedder.run(documents)
    embedded_docs = result["documents"]

    # Store in ChromaDB
    print("Storing in ChromaDB...")
    document_store.write_documents(embedded_docs)

    print(f"Done! Indexed {len(embedded_docs)} documents")
    print(f"Vector DB saved to: {config.CHROMA_PATH}")


def main():
    """CLI entry point."""
    import sys
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    build_index(limit=limit)


if __name__ == "__main__":
    main()
