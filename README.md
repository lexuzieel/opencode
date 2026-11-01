# opencode

Server setup for the OpenCode agent: a tmux TUI launcher, a standalone web
server behind any reverse proxy, login links, a file dump and an Authelia gate.
Settings live in `.env`; machine state lives in `share/` and
`deploy/authelia/{config,data}` (both git-ignored); templates for a new server
live in `deploy/`.

## Files

| Path | Role |
|---|---|
| `opencode.sh` | TUI in a persistent tmux session (best run from a project folder) |
| `bin/agent.sh` | session manager: resumes the newest conversation, named sessions, list and kill |
| `bin/tmux.conf` | tmux defaults and terminal features for those sessions |
| `web.sh` | standalone `opencode serve` for the browser and phone UI: `start`, `stop`, `restart`, `status`, `passwd` |
| `boot.sh` | cron `@reboot` entry point: waits for Docker, runs `web.sh start` |
| `pair.sh` | one-time login link plus QR for the web UI |
| `share.sh` | copies a file into the dump; `--public` adds a uuid link |
| `skills/share-files/` | skill that tells agents how to use the dump |
| `deploy/share-files/` | nginx container serving the dump read-only |
| `deploy/authelia/` | Authelia compose, config templates, `setup.sh`, `guard.sh` |
| `.env.example` | template for `.env` (public URLs, bind address, password file) |
| `DEPLOY.md` | step-by-step deployment for a new server |
| `share/`, `deploy/authelia/config`, `data` | machine state: files and secrets, never committed |
| `password.txt` | web UI password (git-ignored); see `password.example.txt` |

Projects use this launcher rather than keeping their own copy of the session
manager: a wrapper in a project folder only exports `TMUX_PROJECT_DIR` and
execs `~/opencode/opencode.sh`, so session naming, conversation resume and the
tmux settings have one source of truth.

## Architecture

```
TUI:      ./opencode.sh  -> bin/agent.sh -> tmux per project -> opencode
                           -> local service 127.0.0.1:49374
Web:      cron @reboot   -> boot.sh -> web.sh start -> tmux opencode-web
                                                     -> opencode serve WEB_HOST:WEB_PORT
reverse proxy -> https://<PUBLIC_URL> -> WEB_HOST:WEB_PORT

files:    deploy/share-files (nginx, gateway network) -> share/ (read-only)
authelia: deploy/authelia  -> gateway -> guards the dump and other hosts
```

The local background service stays on `127.0.0.1` and is never rebound: the web
UI runs as a separate standalone server on an interface the proxy can reach.

## File dump

```sh
share.sh FILE [--project NAME] [--topic TEXT] [--move] [--public]
```

The file lands in `share/<project>/<YYYY-MM-DD>/[<topic>/]<file>` and the script
prints `<SHARE_URL>/<project>/<date>/[<topic>/]<file>`. The dump is read-only
over HTTP and sits behind Authelia, so one login covers every guarded host.

Shares are private by default. `--public` also creates a symlink under
`public/<uuid>/`, which the dump serves without login, and records it in
`share/public-links.md`: that journal is the only way back from a published link
to the file. Deleting the uuid folder unpublishes the file.

## Configuration

```sh
cp .env.example .env    # public URLs, listen address, password file
```

| Variable | Role |
|---|---|
| `PUBLIC_URL` | public URL of the web UI |
| `SHARE_URL` | public base URL of the file dump |
| `SHARE_ROOT` | where files are stored; default `share/` next to the scripts |
| `WEB_HOST`, `WEB_PORT` | listen address of the standalone web server |
| `WEB_ACCESS_FILE` | password file for the web UI |

See `DEPLOY.md` for the full deployment order.

## Web server

```sh
./web.sh                 # foreground run, Ctrl-C to stop
./web.sh start           # detached in the tmux session "opencode-web"
./web.sh status          # up? and does the password match the file?
./web.sh restart         # apply a changed password, print a login link
./web.sh passwd          # generate a new password (asks first)
```

The password is read from `password.txt` once, when the process starts, so
editing the file has no effect until `./web.sh restart`. `status` reports the
mismatch as `401` instead of leaving it to guesswork.

Browser sessions are signed with that password and last 30 days; `passwd` and a
restart after changing the file end them, and `./pair.sh` mints a new link.
