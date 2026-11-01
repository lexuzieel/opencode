---
name: sourced-article
description: Write or verify a factual article, explainer, review or long post that rests on sources, in any project. Use whenever the task is a blog post, a magazine piece or a research write-up built from research; whenever a draft cites sources, footnotes or links as evidence; whenever someone asks whether an article's claims are actually supported; and before publishing, to check that what the article says about the product matches what the product really does. Also use for rewriting an existing post for clarity, order or length while keeping its facts intact.
---

# Sourced article

## Why this exists

A link is not evidence. A plausible sentence under a real-looking citation is the most expensive kind of mistake in a factual text: the link resolves, the source is real, the sentence says something the source never said, and neither the writer nor the reader notices. Writers make this error from memory, and models make it more often, because a remembered version of a source feels exactly like a read one.

The defence is mechanical, not moral: have the passage in front of you, and check the sentence against it before it goes in. This skill turns that into a sequence, with a script for the part a machine can settle.

## The loop

1. Read the project's own rules first.
2. Build the source set as excerpts, not links.
3. Write against the excerpts.
4. Verify mechanically.
5. Proofread with independent readers.
6. Check every claim about the product.
7. Report what changed, what was checked, what stayed unverified.

### 1. Read the project's rules first

Every project has its own voice, banned habits, block inventory and length norms. Find them before writing: a `CONTENT.md`, an `AGENTS.md`, a style guide, an editorial policy, an examples folder with past posts. Those rules outrank anything written here, including this skill's own preferences. If the project has no such file, read two published posts and infer the rules, then say what you inferred.

### 2. Build the source set as excerpts

Save one file per source in the project's working directory, for example `<project>/local/research/<slug>-sources/<id>-<name>.txt`:

```
https://example.org/page  (fetched 2026-11-01)
<the passage, verbatim, as much as the claims need>
```

- Save the passage, not the whole page: the excerpt is what you will check against.
- Name the source properly in the article. "A help desk answered" and "a 2003 journal article argues" are different kinds of authority, and the difference belongs in the text.
- Note the date when the claim is time-sensitive: prices, availability, "currently".
- If a source cannot be fetched, the claim waits. It does not go in on memory, and it does not go in as "many experts say".
- Keep these files out of git (working material), but keep them on disk: a later editor will want them.

### 3. Write against the excerpts

- Paraphrase the source; quote only where the wording itself is the point, or where exact words carry the authority. A quote longer than a sentence needs a reason.
- Show the thing before naming it. For a term, an example first, then the definition, so the reader has somewhere to put the word.
- One idea per paragraph, six lines at most. A long paragraph hides a second thought in it.
- Say what the problem costs the reader. "This is a mistake" without a cost is a claim the reader has no reason to accept; the cost is what makes the advice useful.
- End the article body with a conclusion about its own subject, not with the product, the CTA, or a link list.
- Pick illustrative blocks deliberately: one main block, at most one more, and none when there is nothing to show. A chart with nothing to count is furniture.
- Numbers in prose get the source in the same sentence. Dates and names too: they are where a remembered fact drifts.

### 4. Verify mechanically

Write the claims you intend to make into one file next to the sources, then run the checker:

```json
{
  "sources": {
    "1": { "path": "304939.txt", "url": "https://example.org/answer" },
    "2": { "path": "275022.txt", "url": "https://example.org/answer2" }
  },
  "claims": [
    {
      "cite": "1",
      "claim": "плеоназм это повтор смыслов, выраженных разнокорневыми словами",
      "fragments": ["повтор смыслов, выраженных разнокорневыми словами"]
    }
  ]
}
```

```
python3 scripts/claims.py --article app/pages/blog/post.vue \
  --sources local/research/post-sources --claims local/research/post-sources/claims.json
```

The script does three things a person skims past: it finds every sentence in the article that carries a citation number, it fails when such a sentence has no entry in the claims file, and it fails when a required fragment is not verbatim in the source. It also reports, without failing, a claim whose text no longer appears in the article and a source nothing uses: the first is a stale entry, the second is a source saved and forgotten. It cannot judge meaning, so it removes the mechanical failure only. Report its output, including the count: "12 claims, 9 cited sentences, 0 failures" is evidence, "I checked the sources" is not.

Fix the article, or fix the excerpt, but never quietly drop the check.

Then open the rendered page and read it as text, looking for what markup leaks: a literal `/>`, `{{`, `}}`, an unprocessed `[1]`. A template bug prints words the author never wrote, and it is invisible in the source file. Balanced tag counts prove nothing either, since a stray opener and a stray closer cancel out; a parser does catch it, so run the project's linter over the file and treat a parsing error as the first thing to fix.

### 5. Proofread with independent readers

Three passes, split by role, run blind: separate sessions, none of them sees another's notes. One shared brief makes three lists of the same generic remarks, which is work thrown away.

- **The editor** is you, against the project's rules: structure, parallel headings, lead promises, examples to every claim, citation boundaries.
- **An outside reader** reports experience only: where the thread is lost, what the title promised and the body never delivered, which paragraph does no work, which example is unreadable without its neighbours.
- **A structure critic** reports order only: a term used before it is explained, a heading that delivers something else, a point made twice, an argument that proves itself.

Ready-to-paste briefs are in [references/proofreaders.md](references/proofreaders.md).

Merge the three lists into one decision table and show it to the author: accepted because a rule or an excerpt backs it, or rejected with the reason. Rejecting is part of the job; a critic's note is a hypothesis. Never accept a critic's factual correction without checking the excerpt, because that is exactly how a new error enters the article, wearing the authority of a second opinion.

### 6. Check every claim about the product

A claim about the product is a claim like any other. It needs the step of the pipeline that does the work, or a run that shows the behaviour, or the product's own page saying it.

When the product cannot do the thing the article discusses, say so in the text. That line is usually more credible than a vague promise, and it keeps the article from selling something it does not address. The product's pages are the ceiling: a post never promises more than they do.

### 7. Report what happened

Close with evidence, not impressions:

- the claims check output, with counts;
- what changed in the text and why, one line per decision;
- what was rejected from the proofreading pass, and why;
- what stayed unverified, and what would settle it;
- any metric that is a diagnostic rather than a goal (search coverage, word count, reading time) reported beside its baseline, with a plain statement that it was not chased.

### 8. Hand the article over for an outside review

A finished draft goes to the author as a link plus a brief, never as a link alone. A reviewer who opens a URL and nothing else reports taste; a reviewer who knows what the text claims reports errors.

Reviewers that fetch a URL obey the site's own rules: a staging or dev host usually answers `Disallow: /` in robots.txt and sends `X-Robots-Tag: noindex`, and a compliant fetcher then refuses. Check the target's `robots.txt` and headers before promising a link. When the host is closed, hand over a file instead: `scripts/snapshot.js <url> <out-dir>` writes a PDF for layout questions and a plain text file for everything else, and a public file dump that keeps its own paths open on their own host (see the share-files skill) gives a link a reviewer can actually open. Verify the link the way the reviewer will: fetch it with no session, and read its `robots.txt`; a 200 is not enough if the host still says `Disallow: /`.

The brief is short and answers five things:

- the dev URL and the attached snapshot, plus the title and lead as published;
- what the article promises, so the reviewer can say whether it delivers;
- every claim that rests on a source, with the source, so a check can be made without re-finding the pages;
- the two or three riskiest sentences, named: the ones where a mistake would look like a correct sentence;
- what the product is allowed to claim in this article, and what it is not.

Add what was already checked (claims script output, lint, screenshots at which widths) so the reviewer spends its attention on what is left.

Ask for notes, not a rewrite: a quoted sentence, what is wrong, and what would fix it. An outside model's note about a fact is a hypothesis until an excerpt confirms it, exactly as in step 5. Dev URLs and working copies belong in the message and in the working directory, not in the page.

## Files

- [references/sources.md](references/sources.md): naming excerpts, dating them, what to keep out of git.
- [references/proofreaders.md](references/proofreaders.md): the three critic briefs, ready to paste.
- [scripts/claims.py](scripts/claims.py): the citation checker used in step 4.
- [scripts/snapshot.js](scripts/snapshot.js): a PDF and a text file of the rendered page, for a reviewer who cannot fetch the URL.
