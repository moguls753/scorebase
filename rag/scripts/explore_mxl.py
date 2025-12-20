#!/usr/bin/env python3
"""Explore what music21 extracts from MXL files.

Run from rag/ directory:
    python scripts/explore_mxl.py
"""

import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from src import config, db
from src.enrichment import parser
from src.enrichment.enrich import get_mxl_path


def main():
    print("=" * 60)
    print("MusicXML Exploration")
    print("=" * 60)

    # Check paths exist
    print(f"\nConfig:")
    print(f"  PDMX path:  {config.PDMX_PATH}")
    print(f"  DB path:    {config.RAILS_DB_PATH}")
    print(f"  PDMX exists: {config.PDMX_PATH.exists()}")
    print(f"  DB exists:   {config.RAILS_DB_PATH.exists()}")

    if not config.PDMX_PATH.exists():
        print("\nERROR: PDMX path not found. Edit src/config.py")
        return

    if not config.RAILS_DB_PATH.exists():
        print("\nERROR: Rails database not found. Run: bin/rails db:setup")
        return

    # Fetch a score
    print("\n" + "-" * 60)
    print("Fetching a score with MXL file...")
    scores = db.get_scores(limit=1)

    if not scores:
        print("No scores with MXL files found in database!")
        return

    score = scores[0]
    print(f"\nScore: {score['title']}")
    print(f"Composer: {score['composer']}")
    print(f"DB mxl_path: {score['mxl_path']}")

    # Resolve full path
    mxl_path = score.get("mxl_path")
    if not mxl_path:
        print("No mxl_path in this score")
        return

    full_path = get_mxl_path(mxl_path)
    print(f"Full path: {full_path}")
    print(f"File exists: {full_path.exists()}")

    if not full_path.exists():
        print("\nERROR: MXL file not found at expected path")
        return

    # Parse with music21
    print("\n" + "-" * 60)
    print("Parsing with music21...")
    print("-" * 60)

    result = parser.parse_mxl(full_path)

    if result:
        print("\nExtracted features:")
        for key, value in result.items():
            if key == "parts":
                print(f"  {key}:")
                for part in value:
                    print(
                        f"    - {part['name']}: {part['lowest']} to {part['highest']}"
                    )
            else:
                print(f"  {key}: {value}")
    else:
        print("Failed to parse file!")


if __name__ == "__main__":
    main()
