"""Build vector index from scores using Haystack."""

from haystack import Document
from haystack.components.embedders import SentenceTransformersDocumentEmbedder
from haystack_integrations.document_stores.chroma import ChromaDocumentStore

from .. import config, db


def _safe_int(value, default=None):
    """Safely convert value to int."""
    if value is None:
        return default
    try:
        return int(value)
    except (ValueError, TypeError):
        return default


def _safe_float(value, default=None):
    """Safely convert value to float."""
    if value is None:
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def make_searchable_text(score: dict) -> str:
    """Convert score metadata to natural prose for embedding.

    Creates readable sentences that match how users search.
    """
    sentences = []

    # 1. Title and composer sentence
    title = score.get("title", "Untitled")
    composer = score.get("composer")
    if composer and composer != "NA":
        sentences.append(f'"{title}" by {composer}.')
    else:
        sentences.append(f'"{title}".')

    # 2. Instrumentation sentence - build grammatically correct phrases
    is_vocal = score.get("is_vocal")
    if is_vocal:
        vocal_parts = ["a vocal work"]
        if score.get("voicing"):
            vocal_parts.append(f"for {score['voicing']}")
        if score.get("has_accompaniment"):
            vocal_parts.append("with accompaniment")
        sentences.append("This is " + " ".join(vocal_parts) + ".")
    elif score.get("instruments"):
        instr_sentence = f"This is for {score['instruments']}"
        if score.get("has_accompaniment"):
            instr_sentence += " with accompaniment"
        sentences.append(instr_sentence + ".")

    # 3. Difficulty sentence - prioritize complexity, fallback to melodic
    complexity = _safe_int(score.get("complexity"))
    if complexity is not None and complexity in (0, 1, 2, 3):
        difficulty_text = {
            0: "This is a beginner piece, suitable for students just starting out.",
            1: "This is an easy piece, good for early learners.",
            2: "This is an intermediate piece, requiring some experience.",
            3: "This is an advanced piece, suitable for experienced players.",
        }
        sentences.append(difficulty_text[complexity])
    else:
        melodic = _safe_float(score.get("melodic_complexity"))
        if melodic is not None:
            if melodic < 0.3:
                sentences.append("This is an easy, simple piece suitable for beginners.")
            elif melodic < 0.5:
                sentences.append("This piece has moderate complexity, suitable for intermediate players.")
            elif melodic < 0.7:
                sentences.append("This is a challenging piece for advanced players.")
            else:
                sentences.append("This is a virtuoso piece, technically demanding and difficult.")

    # 4. Musical characteristics sentence
    chars = []
    if score.get("key_signature"):
        chars.append(f"in {score['key_signature']}")
    if score.get("time_signature"):
        chars.append(f"in {score['time_signature']} time")
    if score.get("tempo_marking"):
        chars.append(score["tempo_marking"].lower())
    if chars:
        sentences.append("The piece is " + ", ".join(chars) + ".")

    # 5. Duration sentence
    duration = _safe_float(score.get("duration_seconds"))
    if duration is not None and duration > 0:
        mins = int(duration // 60)
        if mins == 0:
            sentences.append("A very short piece, under 1 minute.")
        elif mins == 1:
            sentences.append("Duration is about 1 minute, a short piece.")
        elif mins < 5:
            sentences.append(f"Duration is about {mins} minutes, a short piece.")
        elif mins < 10:
            sentences.append(f"Duration is about {mins} minutes, medium length.")
        else:
            sentences.append(f"Duration is about {mins} minutes, an extended work.")

    # 6. Texture and structure sentence
    texture_parts = []
    if score.get("texture_type"):
        texture_parts.append(score["texture_type"])
    num_parts = _safe_int(score.get("num_parts"))
    if num_parts:
        part_names = {1: "solo", 2: "duet", 3: "trio", 4: "quartet"}
        texture_parts.append(part_names.get(num_parts, f"{num_parts} parts"))
    if texture_parts:
        sentences.append("The texture is " + ", ".join(texture_parts) + ".")

    # 7. Range sentence - contextual label based on vocal/instrumental
    if score.get("lowest_pitch") and score.get("highest_pitch"):
        range_type = "Vocal range" if is_vocal else "Pitch range"
        sentences.append(f"{range_type} spans from {score['lowest_pitch']} to {score['highest_pitch']}.")

    # 8. Expression sentence
    expr_parts = []
    if score.get("has_dynamics"):
        expr_parts.append("dynamic markings")
    if score.get("has_ornaments"):
        expr_parts.append("ornaments")
    if score.get("has_articulations"):
        expr_parts.append("articulations")
    if expr_parts:
        sentences.append("Contains " + ", ".join(expr_parts) + ".")

    # 9. Period/genre sentence
    genres = score.get("genres")
    if genres and isinstance(genres, str):
        clean = [g.strip() for g in genres.split("-")
                 if g.strip() and g.strip().upper() != "NA"]
        if clean:
            sentences.append("Genre: " + ", ".join(clean[:4]) + ".")

    # 10. Lyrics language
    if score.get("has_extracted_lyrics"):
        lang = score.get("lyrics_language")
        lang_names = {"en": "English", "de": "German", "fr": "French",
                      "it": "Italian", "la": "Latin", "es": "Spanish"}
        if lang and lang in lang_names:
            sentences.append(f"Text is in {lang_names[lang]}.")
        elif lang:
            sentences.append(f"Text is in {lang}.")

    # 11. Description (if available) - ensure it ends with punctuation
    desc = score.get("description")
    if desc and isinstance(desc, str):
        desc = desc[:150].strip()
        if desc:
            if desc[-1] not in ".!?":
                desc += "."
            sentences.append(desc)

    return " ".join(sentences)


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
