---
name: share-files
description: Put a file on the server file dump and give the user a link. Use whenever the user asks to share, hand over, send, drop, or publish a file (report, log, PDF, image, archive, export, screenshot, dataset) and expects a link or a place to download it from, including phrases like "скинь файл", "дай ссылку", "положи в шару", "загрузи куда-нибудь", or when an artifact is too big or too structured to paste into chat. Also use when a generated report or screenshot should be shown outside the terminal.
---

# Share files

The server keeps a read-only file dump, protected by the same Authelia login as
the other guarded hosts. Its base URL is `SHARE_URL` in `~/opencode/.env`:

```sh
grep -oP '^SHARE_URL=\K\S+' ~/opencode/.env
```

Files live under `~/opencode/share` on the server (or `SHARE_ROOT` when set);
the dump only reads them. Anything placed there is treated as shareable, so the
rules below decide what belongs there.

## Share one file

```sh
~/opencode/share.sh FILE [--project NAME] [--topic TEXT] [--move] [--public]
```

It copies the file into `<share root>/<project>/<YYYY-MM-DD>/[<topic>/]<file>` and
prints the private link. Use `--project` when the current directory is not the
project the file belongs to, and `--topic` for a short, readable group name
(`report`, `logs`, `screenshots`, `exports`); without `--topic` the file sits
directly in the day folder. Add `--move` only when the source is a scratch file
that should not stay where it is.

Defaults: project = current directory name, no topic folder. The script lowercases
the stored name and replaces every character outside `a-z0-9._-` with a dash, so a
file called `Отчёт за март.pdf` becomes `otchet-za-mart.pdf`; still rename files to
latin dash-separated names when you can, because the result reads better in chat.

## What belongs in the dump

- Reports, exports, generated documents, screenshots, charts, logs, datasets,
  archives: anything the user asked to have as a file rather than as chat text.
- Files that are useful only for a specific conversation. The dump is a
  temporary handover, not an archive of record.

## Public links

Every share is private by default: it lands behind Authelia and only the user can
open it. A file becomes public only when the user explicitly asks to publish it,
and then `--public` creates a relative symlink inside a fresh uuid folder:
`public/<uuid>/<file>`. Authelia serves that path without login, the file itself
stays in the normal tree, so the private link keeps working and deleting the
symlink unshares it again.

The script prints the private link first and the public one second, and appends a
row to `<share root>/public-links.md`. That journal is the only mapping from a
uuid back to the file it publishes, so check it rather than guessing when the
user asks what was published before.

The uuid makes the address unguessable and nginx refuses to list `/public/`, so
publishing one file never exposes the others.

Use `--public` only for something the user is happy to show to anyone with the
link: demo pages, shareable reports, screenshots. Never for credentials,
customer data, internal drafts, or anything the user has not asked to publish.
The dump sends `X-Robots-Tag: noindex` and a blocking `robots.txt`, but treat
search engines as able to find anything once a link circulates.

## What must never be placed there

- Credentials, tokens, API keys, `login.txt`, `.env`, SSH keys, database dumps,
  or anything containing someone else's personal data.
- Files larger than about 200 MB: copy them somewhere deliberate and ask first.
- Anything already tracked in git when the repo has a proper place for it.

When unsure whether a file is shareable, ask instead of guessing: the dump is
public to anyone with the Authelia session.

## Organising

Group by project first, then by date and topic. One directory per handover, for
example:

```
<share root>/redraft/2026-11-01/
<share root>/authelia/2026-11-01/logs/
<share root>/opencode/2026-11-01/
```

When a folder holds more than one file, add a note named `00-README.txt`: nginx
sorts directories before files and names alphabetically, so the `00-` prefix is
what puts it first in the autoindex.

## Cleanup

The dump has no expiry, so it grows. `du -sh ~/opencode/share/*` shows what takes
space; offer cleanup of folders nobody needs and remove only what the user
confirms. Public links are the first thing to review when a file should stop
being reachable: delete the uuid folder listed in `public-links.md`.

## Checking

A private link must redirect to the login page, so verifying it needs the user's
Authelia session in a browser; do not disable the auth snippet to make a check
pass. A public link is the opposite: it must answer 200 without any cookie.

```sh
curl -s -o /dev/null -w '%{http_code}\n' "<public link>"     # 200
curl -s -o /dev/null -w '%{http_code}\n' "<private link>"    # 302
curl -s -o /dev/null -w '%{http_code}\n' "${SHARE_URL}/public/"   # 404
```
