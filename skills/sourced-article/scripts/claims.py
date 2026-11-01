#!/usr/bin/env python3
"""Check a sourced article's citations against its saved excerpts.

    python3 claims.py --article app/pages/blog/post.vue \
        --sources local/research/post-sources \
        --claims local/research/post-sources/claims.json

Three failures, all mechanical:

1. a sentence in the article carries a citation number that no claim
   entry covers;
2. a claim entry names a source that is not in the claims file or not
   on disk;
3. a required fragment is not verbatim in its source.

The script cannot tell whether a sentence means what the source means;
it only proves the passage exists and that no citation was left
unexamined. A passing run is the floor, not the finish line.

claims.json:

    {
      "sources": {"1": {"path": "304939.txt", "url": "https://..."}},
      "claims": [
        {"cite": "1",
         "claim": "плеоназм это повтор смыслов, выраженных разнокорневыми словами",
         "fragments": ["повтор смыслов, выраженных разнокорневыми словами"]}
      ]
    }

Exit status: 0 when every check passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path

CITE = re.compile(r"\[(\d+)\]")
SENTENCE_END = re.compile(r"(?<=[.!?…])\s+")


def normalise(text: str) -> str:
    """Compare-ready text: same words, tolerant of dash and space noise.

    Sources arrive as scraped HTML, so the same sentence carries
    different dashes, no-break spaces and a space before a closing
    bracket depending on the page. None of that changes the claim.
    """
    text = text.replace("\u2013", "-").replace("\u2014", "-")
    text = text.replace("\u00a0", " ").replace("\u202f", " ")
    text = re.sub(r"[\s\)\]]+", " ", text)
    return text.strip().lower()


def article_text(path: Path) -> str:
    """The readable text of an article file, whatever markup it is in.

    Components often carry prose in an attribute (`text="..."`), and
    plain tag stripping throws that prose away with the tag. So a tag
    that holds a text or title attribute becomes its own value first.
    """
    raw = path.read_text(encoding="utf-8")
    raw = re.sub(r"<script.*?</script>|<style.*?</style>", " ", raw, flags=re.S)
    raw = re.sub(r'<[^>]*?(?:text|title)="([^"]*)"[^>]*>', r" \1 ", raw)
    raw = re.sub(r"<[^>]+>", " ", raw)
    raw = html.unescape(raw.replace("\\'", "'"))
    return re.sub(r"\s+", " ", raw)


def sentences(text: str) -> list[str]:
    return [s.strip() for s in SENTENCE_END.split(text) if s.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--article", required=True, type=Path)
    parser.add_argument("--sources", required=True, type=Path)
    parser.add_argument("--claims", required=True, type=Path)
    args = parser.parse_args()

    spec = json.loads(args.claims.read_text(encoding="utf-8"))
    sources = spec.get("sources", {})
    claims = spec.get("claims", [])

    source_text = {}
    for key, source in sources.items():
        path = args.sources / source["path"]
        if not path.exists():
            print(f"MISSING SOURCE FILE  [{key}] {path}")
            return 1
        source_text[key] = normalise(path.read_text(encoding="utf-8"))

    failures = 0
    cited = [
        (number, sentence)
        for sentence in sentences(article_text(args.article))
        for number in CITE.findall(sentence)
    ]

    for number, sentence in cited:
        flat = normalise(sentence)
        matched = [
            claim
            for claim in claims
            if claim["cite"] == number and normalise(claim["claim"]) in flat
        ]
        if not matched:
            failures += 1
            print(f"NO CLAIM ENTRY  [{number}] {sentence[:90]}...")

    for claim in claims:
        key, text = claim["cite"], claim["claim"]
        if key not in source_text:
            failures += 1
            print(f"UNKNOWN SOURCE  [{key}] {text[:70]}")
            continue
        missing = [
            fragment
            for fragment in claim["fragments"]
            if normalise(fragment) not in source_text[key]
        ]
        if missing:
            failures += 1
            print(f"NOT IN SOURCE   [{key}] {text[:70]}")
            for fragment in missing:
                print(f"                missing: {fragment}")
        else:
            print(f"ok              [{key}] {text[:70]}")

    unused = sorted(set(sources) - {claim["cite"] for claim in claims})
    for key in unused:
        print(f"note: source [{key}] is saved but no claim uses it")

    # A claim whose sentence carries no citation is either attached to
    # the sentence above it or left over from an earlier draft; both
    # are worth seeing, neither breaks the article.
    flat_article = normalise(article_text(args.article))
    for claim in claims:
        if normalise(claim["claim"]) not in flat_article:
            print(f"note: claim not found in the article: {claim['claim'][:70]}")

    checked = len(cited)
    print(
        f"\n{len(claims)} claims, {checked} cited sentences, "
        f"{failures} failure(s)"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
