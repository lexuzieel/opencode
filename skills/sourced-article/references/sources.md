# Sources and excerpts

## Where they live

Working material, not part of the site: the project's gitignored scratch
directory. A shape that has worked:

```
local/research/<slug>-sources/
    304939.txt
    275022.txt
    hanpira-2003.txt
    claims.json
```

One file per source. The first line is the address and the day it was
fetched, everything after it is the passage verbatim. If two passages
of the same page matter, they go in the same file in reading order.

## Naming

Name the file after something stable: an answer number, an author and a
year, a page slug. The article's citation numbers (`[1]`, `[2]`) are a
separate thing and should not be forced onto the file names, because
sources get reordered while the article is being edited.

## What goes in the file

The passage the claim rests on, not the whole page. Two to six
sentences is usually enough and it keeps the check honest: if the
passage is not there, the sentence it was supposed to support cannot
appear either.

Trim navigation, cookie banners and menus; never trim inside the
passage, and never paraphrase it. If the page is a table, copy the rows
the claim uses.

## What to write down besides the text

- The day you fetched it, for anything that changes: prices, stock,
  "currently", versions.
- Who is answering. A help desk, a dictionary editor, a 2003 journal
  entry and a wiki are four different authorities, and the article
  should say which one it leans on.
- When a page answers a question that was asked in the page itself
  (a letters-to-the-editor answer, a forum reply), keep the asker's
  wording too: sometimes the useful part is what the source declines
  to confirm.

## When a source cannot be fetched

Say so, and let the claim wait. Two temptations to avoid:

- writing the claim and citing the page anyway, because the page
  exists and probably says something like it;
- softening the claim until it is unfalsifiable ("many linguists
  believe"), which is worse than no claim because it looks checked.

If the fact matters and no source can be fetched, the honest options
are to write around it or to say plainly that this point rests on the
author's own judgement.

## Keeping them

The excerpts are the audit trail for the article. They stay after
publication, so a later correction can start from the passage instead
of from the argument. They live in the gitignored working directory:
the article travels to production, the working material does not.
