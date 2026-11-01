# opencode

Server-side setup for the OpenCode agent on `w.aleksei.dev`: a tmux-based TUI
launcher, a standalone web server behind nginx-proxy-manager, and one-time
login links.

## Files

| File | Role |
|---|---|
| `opencode.sh` | TUI in a persistent tmux session (best run from a project folder, e.g. `~/projects/<name>/opencode.sh`) |
| `web.sh` | standalone `opencode serve` for the browser and phone UI; binds the docker bridge IP so nginx-proxy-manager can reach it |
| `boot.sh` | cron `@reboot` entry point: waits for Docker, starts `web.sh` in a tmux session |
| `pair.sh` | prints a one-time login link for the web UI |
| `login.txt` | server password (git-ignored); see `login.example.txt` |

## Architecture

```
TUI:      ./opencode.sh  -> tmux session per project -> opencode -> background service 127.0.0.1:49374
Web:      cron @reboot   -> boot.sh -> tmux session opencode-web -> web.sh
                                                                 -> opencode serve 172.23.0.1:49375
nginx-proxy-manager -> https://code.aleksei.dev -> 172.23.0.1:49375
```

The local background service stays on `127.0.0.1` and is never rebound: the web
UI runs as a separate standalone server on the docker bridge interface
(`gateway` network), which the proxy container can reach and the internet
cannot.

## Login flow

`./pair.sh [public-url]` mints a one-time code (5 minutes) on the standalone
server and prints `https://code.aleksei.dev/auth/connect/<code>` together with a
terminal QR code for the phone. Opening the link (or scanning the QR) stores a
30-day cookie in that browser. A new link is needed only for a new device, after
clearing cookies, or after a password change (changing the password signs every
device out).

Environment overrides: `PAIR_URL`, `WEB_HOST`, `WEB_PORT`, `WEB_ACCESS_FILE`.

## Install

```sh
cp login.example.txt login.txt   # put the real password in, chmod 600
crontab -e                       # @reboot /path/to/boot.sh
```

Requires: `opencode` (v2), `tmux`, docker with the nginx-proxy-manager stack,
and a proxy host pointing the public domain at `WEB_HOST:WEB_PORT` with
websockets enabled.
