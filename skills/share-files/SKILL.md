---
name: share-files
description: Put a file on the server file dump and give the user a link. Use whenever the user asks to share, hand over, send, drop, or publish a file (report, log, PDF, image, archive, export, screenshot, dataset) and expects a link or a place to download it from, including phrases like "скинь файл", "дай ссылку", "положи в шару", "загрузи куда-нибудь", or when an artifact is too big or too structured to paste into chat. Also use when a generated report or screenshot should be shown outside the terminal.
---

# Share files

The server keeps a read-only file dump served at
`https://files.code.aleksei.dev`, protected by Authelia (same login as
`https://draw.aleksei.dev`). Files live under `~/opencode/share` on the server; the dump
only reads them. Anything placed there is treated as shareable, so the rules
below decide what belongs there.

## Share one file

```sh
~/opencode/share.sh FILE [--project NAME] [--topic TEXT] [--move]
```

It copies the file into `~/opencode/share/<project>/<YYYY-MM-DD>/[<topic>/]<file>` and
prints the public URL. Use `--project` when the current directory is not the
project the file belongs to, and `--topic` for a short, readable group name
(`report`, `logs`, `screenshots`, `exports`); without `--topic` the file sits
directly in the day folder. Add `--move` only when the source
is a scratch file that should not stay where it is.

Defaults: project = current directory name, topic = `misc`.

## What belongs in the dump

- Reports, exports, generated documents, screenshots, charts, logs, datasets,
  archives: anything the user asked to have as a file rather than as chat text.
- Files that are useful only for a specific conversation. The dump is a
  temporary handover, not an archive of record.

## What must never be placed there

- Credentials, tokens, API keys, `login.txt`, `.env`, `service.env`, SSH keys,
  database dumps, or anything containing someone else's personal data.
- Files larger than about 200 MB: copy them somewhere deliberate and ask first.
- Files with Cyrillic names, spaces, or parentheses. Rename to latin
  `dash-separated` first; URLs with such names break in messengers.
- Anything already tracked in git when the repo has a proper place for it.

When unsure whether a file is shareable, ask instead of guessing: the dump is
public to anyone with the Authelia session.

## Organising

Group by project first, then by date and topic. One directory per handover,
for example:

```
~/opencode/share/redraft/2026-11-01/
~/opencode/share/authelia/2026-11-01/logs/
~/opencode/share/opencode/2026-11-01/
```

Add a `README.txt` with one line about what the handover is when the folder
holds more than one file; the autoindex shows it first.

## Cleanup

The dump is meant to stay small. When a folder is older than 30 days, offer to
remove it; never delete a folder the user has not mentioned without asking.
`du -sh ~/opencode/share/*` lists what takes space.

## Checking

An anonymous request must redirect to the login page, so verification needs the
user's Authelia session in a browser. Do not test with plain `curl` and do not
disable the auth snippet to make a check pass.
