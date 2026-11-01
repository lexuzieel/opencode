# opencode

Server-side setup for the OpenCode agent: a tmux-based TUI launcher, a
standalone web server behind nginx-proxy-manager, and one-time login links.
Everything deployment specific lives in `.env`; the only secret is `login.txt`.

## Files

| File | Role |
|---|---|
| `opencode.sh` | TUI in a persistent tmux session (best run from a project folder, e.g. `~/projects/<name>/opencode.sh`) |
| `web.sh` | standalone `opencode serve` for the browser and phone UI; binds the docker bridge IP so nginx-proxy-manager can reach it |
| `boot.sh` | cron `@reboot` entry point: waits for Docker, starts `web.sh` in a tmux session |
| `pair.sh` | prints a one-time login link and a QR code for the web UI |
| `.env.example` | template for `.env` (public URL, bind address, password file path) |
| `login.txt` | server password (git-ignored); see `login.example.txt` |

## Architecture

```
TUI:      ./opencode.sh  -> tmux session per project -> opencode -> background service 127.0.0.1:49374
Web:      cron @reboot   -> boot.sh -> tmux session opencode-web -> web.sh
                                                                 -> opencode serve WEB_HOST:WEB_PORT
nginx-proxy-manager -> https://<PUBLIC_URL> -> WEB_HOST:WEB_PORT
```

The local background service stays on `127.0.0.1` and is never rebound: the web
UI runs as a separate standalone server on the docker bridge interface
(`gateway` network), which the proxy container can reach and the internet
cannot.

## Configuration

```sh
cp .env.example .env
```

| Variable | Meaning |
|---|---|
| `PUBLIC_URL` | public URL of the web UI, scheme included |
| `WEB_HOST` | interface the standalone server binds to; must be the docker bridge gateway |
| `WEB_PORT` | port of the standalone server |
| `WEB_ACCESS_FILE` | password file, relative to this directory or absolute |

On a new server find the bridge gateway with:

```sh
docker network inspect gateway --format '{{(index .IPAM.Config 0).Gateway}}'
```

## Login flow

`./pair.sh` mints a one-time code (5 minutes) on the standalone server and
prints the login link together with a terminal QR code for the phone. Opening
the link (or scanning the QR) stores a 30-day cookie in that browser. A new
link is needed only for a new device, after clearing cookies, or after a
password change (changing the password signs every device out).

The shell commands accept optional overrides: `pair.sh [public-url]`,
`web.sh [host] [port]`.

## Deploy on a new server

1. Install `opencode` (v2) and `tmux`; log in to a provider with `opencode auth`.
2. Copy this directory to the server and run `cp .env.example .env`; set
   `PUBLIC_URL`, `WEB_HOST` (bridge gateway), `WEB_PORT`.
3. Create the password: `opencode service set password "…"` and put it into
   `login.txt` as `password: …` (mode 0600).
4. In nginx-proxy-manager add a proxy host for `PUBLIC_URL` forwarding to
   `WEB_HOST:WEB_PORT` with websockets enabled, and request a certificate.
5. Add the boot entry: `crontab -e` ->
   `@reboot /path/to/opencode/boot.sh`.
6. Check: `./pair.sh` prints a link; opening it shows the session list.

Requires: `curl`, `python3` with `qrcode` for the QR (`pip install --user qrcode`;
without it `pair.sh` still prints the link).
