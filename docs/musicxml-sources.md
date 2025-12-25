# MusicXML Sources for ScoreBase

Research on additional MusicXML datasets and PDF-to-MusicXML (OMR) options.

## Current State

| Source | Scores | MusicXML Available |
|--------|--------|-------------------|
| PDMX | ~93k (after cleanup) | All (native) |
| IMSLP | Many thousands | Rare (user uploads) |
| CPDL | 43k+ | Rare (user uploads) |

The RAG system's precision depends on extracted metadata (difficulty, ranges, duration, tempo). Without MusicXML, we're limited to inconsistent text-based metadata.

---

## Additional MusicXML Sources

### Commercially Safe (Clear Licensing)

#### OpenScore Lieder Corpus
- **URL**: https://github.com/OpenScore/Lieder
- **Size**: 1,300+ 19th century art songs
- **License**: CC0 (public domain dedication) - fully commercial OK
- **Format**: MuseScore files with batch conversion to MusicXML
- **Content**: Voice + piano, curated with linked metadata
- **Quality**: High - reviewed by volunteers

#### PDMX (Already Using)
- **URL**: https://github.com/pnlong/PDMX
- **Size**: 250k+ scores
- **License**: CC BY 4.0 - commercial OK with attribution
- **Note**: Already our main source

#### Humdrum/KernScores
- **URL**: https://github.com/humdrum-tools/humdrum-data
- **Size**: 26,490 files (381MB)
- **License**: Varies by sub-corpus (check each)
- **Format**: Kern format, converts to MusicXML via music21
- **Includes**:
  - Josquin Research Project (CC BY-SA)
  - Tasso in Music Project
  - Polish Music in Open Access
  - 1520s Project

#### NEUMA
- **URL**: https://neuma.huma-num.fr
- **Content**: French baroque/classical (late 17th - early 19th century)
- **License**: Free, public domain
- **Format**: Native MusicXML

#### Werner Icking Music Archive
- **URL**: http://icking-music-archive.org
- **Content**: Classical, merged with IMSLP but independently accessible
- **License**: Public domain
- **Format**: MusicXML available for many works

### Specialized Collections

| Collection | Content | Size | License |
|------------|---------|------|---------|
| [ASAP Dataset](https://github.com/fosfrancesco/asap-dataset) | Piano with aligned performances | 222 scores | Research |
| [Mozart Piano Sonatas](https://github.com/DCMLab/mozart_piano_sonatas) | Mozart K.279-576 | 18 sonatas | CC BY |
| [Hymnary.org](https://hymnary.org) | Hymn tunes | Thousands | Varies |
| [SymbTr](https://github.com/MTG/SymbTr) | Turkish Makam music | 2,200 pieces | CC BY-NC-SA |
| [musetrainer/library](https://github.com/musetrainer/library) | Classical standards | 73 files | Public domain |

### Not Recommended for Commercial Use

| Source | Reason |
|--------|--------|
| Musicalion (56k MusicXML) | Subscription ToS prohibits redistribution |
| MuseScore user uploads | Many marked "All Rights Reserved" |
| Scraped sources | Contract/ToS violations |

---

## PDF-to-MusicXML (OMR)

### Available Tools

| Tool | Type | Best For | URL |
|------|------|----------|-----|
| Audiveris | Traditional + NN | Clean typeset, interactive correction | https://github.com/Audiveris/audiveris |
| oemer | End-to-end ML | Phone photos, quick batch | https://github.com/BreezeWhite/oemer |
| homr | Recent ML (2024) | Camera images | https://github.com/liebharc/homr |
| Zeus/OLIMPIC | State-of-art | Piano scores, research | https://github.com/ufal/olimpic-icdar24 |

### Realistic Accuracy

| Score Type | Symbol Accuracy |
|------------|-----------------|
| Clean typeset, simple | 85-95% |
| Complex piano/orchestral | 60-80% |
| Historical scans | 40-70% |
| Handwritten | Often unusable |

### Why OMR is Problematic for ScoreBase

Even 90% accuracy causes cascading errors:
- Wrong note → wrong range detection → wrong vocal filtering
- Missing accidentals → wrong key detection
- Rhythm errors → wrong difficulty estimation
- Duration calculations completely off

A 4-page piano piece with 1,000+ symbols at 90% accuracy = 100 errors propagating through music21 analysis.

### If Using OMR

Quality filter after extraction:

```python
def is_usable(score):
    """Reject obviously broken extractions."""
    return (
        score.duration.quarterLength > 0 and
        len(list(score.flat.notes)) > 10 and
        not has_suspicious_patterns(score)  # e.g., all same pitch
    )
```

Only use on:
- IMSLP "typeset" PDFs (not scans)
- Clean, simple scores
- High-value gaps in catalog

---

## Recommendation

### Priority Order

1. **OpenScore Lieder** - Immediate +1,300 art songs, CC0, high quality
2. **Humdrum (Josquin, etc.)** - +26k classical works, convert from Kern
3. **Selective OMR** - Only for specific high-demand gaps
4. **Degraded metadata** - For remaining IMSLP/CPDL, use text metadata with lower confidence

### Attribution Requirement

Add to site footer or about page:

> Score data includes works from [PDMX](https://github.com/pnlong/PDMX) (CC BY 4.0) and [OpenScore](https://github.com/OpenScore/Lieder) (CC0).

### Expected Outcome

- PDMX (~93k) + OpenScore (~1.3k) + Humdrum (~26k) = ~120k precise scores
- Covers majority of actual user searches (popular classical, art songs, piano)
- Remaining IMSLP/CPDL scores indexed with basic metadata only

---

## Legal Notes

### What's Copyrightable

| Element | Copyrightable? |
|---------|---------------|
| Musical composition (notes, rhythms) | No, if public domain |
| Digital encoding/transcription | Yes, by transcriber |
| Extracted facts (key, range, tempo) | Generally no |

Extracted metadata (key = C major, range = C4-G5) are facts, not creative expression. Similar to stating "this book has 300 pages."

### Safe Practices

- Use CC0/CC BY sources
- Provide attribution where required
- Avoid scraping subscription services
- Don't redistribute original files, only derived metadata

---

## References

- PDMX Paper: https://arxiv.org/abs/2409.10831
- OpenScore Project: https://fourscoreandmore.org/openscore/
- MusicXML Sites List: https://www.musicxml.com/music-in-musicxml/
- OMR Research: https://omr-research.net/
- OLIMPIC (2024 OMR): https://arxiv.org/abs/2403.13763
