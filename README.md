# opencode

Server setup for the OpenCode agent: a tmux TUI launcher, a standalone web
server behind any reverse proxy, login links, a file dump and an Authelia gate.
Deployment settings live in `.env`; machine state lives in `share/` and
`authelia/` (both git-ignored), templates for a new server in `deploy/`.

## Files

| Path | Role |
|---|---|
| `opencode.sh` | TUI in a persistent tmux session (best run from a project folder) |
| `web.sh` | standalone `opencode serve` for the browser and phone UI |
| `boot.sh` | cron `@reboot` entry point: waits for Docker, starts `web.sh` |
| `pair.sh` | one-time login link plus QR for the web UI |
| `share.sh` | copies a file into the dump and prints its public URL |
| `skills/share-files/` | skill that tells agents how to use the dump |
| `deploy/share-files/` | nginx container serving the dump read-only |
| `deploy/authelia/` | Authelia compose, config templates, `setup.sh` |
| `.env.example` | template for `.env` (public URL, bind address, password file) |
| `DEPLOY.md` | step-by-step deployment for a new server |
| `share/`, `authelia/` | machine state: files and secrets, never committed |
| `login.txt` | web UI password (git-ignored); see `login.example.txt` |

## Architecture

```
TUI:      ./opencode.sh  -> tmux session per project -> opencode -> service 127.0.0.1:49374
Web:      cron @reboot   -> boot.sh -> tmux opencode-web -> web.sh
                                                          -> opencode serve WEB_HOST:WEB_PORT
reverse proxy -> https://<public host> -> WEB_HOST:WEB_PORT

files:    deploy/share-files (nginx, gateway network) -> ~/opencode/share (read-only)
authelia: deploy/authelia  -> gateway -> guards the dump and other hosts
```

The local background service stays on `127.0.0.1` and is never rebound: the web
UI runs as a separate standalone server on an interface the proxy can reach.

## File dump

`share.sh FILE [--project NAME] [--topic TEXT]` copies the file to
`share/<project>/<YYYY-MM-DD>/[<topic>/]<file>` and prints
`https://files.<domain>/<project>/<date>/<file>`. The dump is read-only over
HTTP and sits behind Authelia, so one login covers every guarded host.

## Configuration

```sh
cp .env.example .env    # public URL, listen address, password file
```

See `DEPLOY.md` for the full deployment order.
