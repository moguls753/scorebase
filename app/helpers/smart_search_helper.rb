module SmartSearchHelper
  # Percentage of free (non-commercial) scores currently indexed in ChromaDB.
  # Cached for 1 hour — the number only moves when indexing runs.
  def smart_search_indexed_corpus_percent
    Rails.cache.fetch("smart_search:indexed_corpus_pct", expires_in: 1.hour) do
      free_total = Score.free.count
      next "0%" if free_total.zero?

      indexed = Score.where(rag_status: "indexed").count
      "#{(indexed.to_f / free_total * 100).round}%"
    end
  end
end
