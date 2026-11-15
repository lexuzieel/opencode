---
name: codex-image
description: Draw a picture with the Codex CLI on this server and hand the PNG back. Use whenever the user asks opencode to generate an image, illustration, picture, artwork, icon, or visual ("нарисуй", "сгенери картинку", "make me an image"), because opencode itself has no image tool and the ChatGPT login that Codex already has is the way to draw one.
---

# Images through Codex

Codex CLI (installed in `~/codex`, wrapper `~/.local/bin/codex`) has a built-in
`image_gen` tool backed by the ChatGPT login on this server. No API key, no extra
account, no per-image charge — the plan covers it.

## Draw

```sh
mkdir -p /tmp/opencode/img && cd /tmp/opencode/img
timeout 240 codex exec --skip-git-repo-check "Use the built-in image_gen tool and generate <PROMPT>" < /dev/null
```

- `< /dev/null` is required: without it codex waits on stdin and never returns.
- `--skip-git-repo-check` because the scratch directory is not a repository.
- No `--sandbox` flag: the server's `~/.codex/config.toml` runs
  `danger-full-access` (bubblewrap cannot make a user namespace here).
- One image per run, 30–60 s, roughly 5–20k tokens of the plan.

## Find the file

Codex never writes where you ask unless you name a path; by default the PNG lands
in its own home, one directory per session:

```sh
ls -t ~/.codex/generated_images/*/*.png | head -1
```

Take the newest file created after the run started — do not pick up an older
image. Look at it before you report, and say what it shows: a broken or empty
image is a failure even when codex answered "done".

## Hand it over

Give the local path in the answer. For a link, use the dump:

```sh
~/opencode/share.sh "$(ls -t ~/.codex/generated_images/*/*.png | head -1)" --public
```

Private by default; `--public` adds a uuid link that needs no login. See the
`share-files` skill for the rest.

## When it fails

| Symptom | Cause and fix |
|---|---|
| `image tool failed to start … host executable is missing` | `codex-code-mode-host` is missing next to the binary — rerun `~/codex/install.sh` |
| `bwrap: setting up uid map: Permission denied` | the sandbox is on again; check `sandbox_mode` in `~/.codex/config.toml` |
| `Not logged in` | `codex login --device-auth` and hand the code to whoever owns the account |
| answer without a picture | the prompt did not ask for one; say "generate an image …" explicitly |
