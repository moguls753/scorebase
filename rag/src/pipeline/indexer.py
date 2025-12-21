"""Build vector index from scores using Haystack."""

from haystack import Document
from haystack.components.embedders import SentenceTransformersDocumentEmbedder
from haystack_integrations.document_stores.chroma import ChromaDocumentStore

from .. import config, db


def make_searchable_text(score: dict) -> str:
    """Convert score metadata to searchable text.

    Include all relevant fields - the embedding model handles semantic matching.
    """
    parts = []

    # Title and composer
    if score.get("title"):
        parts.append(score["title"])
    if score.get("composer") and score["composer"] != "NA":
        parts.append(f"by {score['composer']}")

    # Instrumentation
    if score.get("instruments"):
        parts.append(f"for {score['instruments']}")
    if score.get("voicing"):
        parts.append(f"{score['voicing']} voicing")
    if score.get("is_vocal"):
        parts.append("vocal")
    if score.get("is_instrumental"):
        parts.append("instrumental")
    if score.get("has_accompaniment"):
        parts.append("with accompaniment")

    # Key and time
    if score.get("key_signature"):
        parts.append(f"in {score['key_signature']}")
    if score.get("time_signature"):
        parts.append(f"{score['time_signature']} time")

    # Tempo
    if score.get("tempo_marking"):
        parts.append(score["tempo_marking"])
    if score.get("tempo_bpm"):
        parts.append(f"{score['tempo_bpm']} bpm")

    # Duration
    if score.get("duration_seconds"):
        mins = int(score["duration_seconds"] // 60)
        if mins > 0:
            parts.append(f"{mins} minutes")

    # Difficulty - map numeric to words
    complexity = score.get("complexity")
    if complexity is not None:
        labels = {0: "beginner", 1: "easy", 2: "intermediate", 3: "advanced"}
        if complexity in labels:
            parts.append(labels[complexity])

    melodic = score.get("melodic_complexity")
    if melodic is not None:
        if melodic < 0.3:
            parts.append("simple")
        elif melodic > 0.7:
            parts.append("complex")

    # Texture
    if score.get("texture_type"):
        parts.append(score["texture_type"])
    if score.get("num_parts"):
        parts.append(f"{score['num_parts']} parts")

    # Range (useful for vocal matching)
    if score.get("lowest_pitch") and score.get("highest_pitch"):
        parts.append(f"range {score['lowest_pitch']} to {score['highest_pitch']}")

    # Expression
    if score.get("has_dynamics"):
        parts.append("with dynamics")
    if score.get("dynamic_range"):
        parts.append(score["dynamic_range"])
    if score.get("has_ornaments"):
        parts.append("ornamented")

    # Melodic character
    if score.get("melodic_contour"):
        parts.append(f"{score['melodic_contour']} contour")
    if score.get("stepwise_motion_ratio") and score["stepwise_motion_ratio"] > 0.7:
        parts.append("stepwise")

    # Harmony
    if score.get("modulation_count") and score["modulation_count"] > 2:
        parts.append("modulating")

    # Lyrics
    if score.get("has_extracted_lyrics"):
        lang = score.get("lyrics_language")
        if lang:
            parts.append(f"{lang} text")
        else:
            parts.append("with lyrics")

    # Genres (already has period info like "Baroque music")
    if score.get("genres"):
        clean = [g.strip() for g in score["genres"].split("-")
                 if g.strip() and g.strip().upper() != "NA"]
        parts.extend(clean[:5])

    # Tags
    if score.get("tags"):
        clean = [t.strip() for t in score["tags"].split("-")
                 if t.strip() and t.strip().upper() != "NA"]
        parts.extend(clean[:3])

    # Description (truncated)
    if score.get("description"):
        parts.append(score["description"][:150])

    return ". ".join(parts)


def build_index(limit: int = 100):
    """Build vector index from extracted scores.

    Args:
        limit: Number of scores to index (use -1 for all)
    """
    print(f"Fetching extracted scores (limit={limit})...")
    if limit == -1:
        scores = db.get_all_extracted_scores()
    else:
        scores = db.get_extracted_scores(limit=limit)
    print(f"Got {len(scores)} extracted scores")

    if not scores:
        print("No extracted scores found. Run music21 extraction first.")
        return

    # Create documents
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
    print(f"\nSample:\n{documents[0].content[:400]}...\n")

    # Initialize ChromaDB
    config.CHROMA_PATH.mkdir(parents=True, exist_ok=True)
    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    # Embed
    print(f"Loading model: {config.EMBEDDING_MODEL}")
    embedder = SentenceTransformersDocumentEmbedder(model=config.EMBEDDING_MODEL)
    embedder.warm_up()

    print("Embedding...")
    result = embedder.run(documents)
    embedded_docs = result["documents"]

    # Store
    print("Storing in ChromaDB...")
    document_store.write_documents(embedded_docs)

    print(f"\nDone! Indexed {len(embedded_docs)} documents to {config.CHROMA_PATH}")


def main():
    import sys
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    build_index(limit=limit)


if __name__ == "__main__":
    main()
