# opencode

Server-side setup for the OpenCode agent: a tmux-based TUI launcher, a
standalone web server behind any reverse proxy, and one-time login links.
Everything deployment specific lives in `.env`; the only secret is `login.txt`.

## Files

| File | Role |
|---|---|
| `opencode.sh` | TUI in a persistent tmux session (best run from a project folder, e.g. `~/projects/<name>/opencode.sh`) |
| `web.sh` | standalone `opencode serve` for the browser and phone UI; binds the docker bridge IP so a reverse proxy can reach it |
| `boot.sh` | cron `@reboot` entry point: waits for Docker, starts `web.sh` in a tmux session |
| `pair.sh` | prints a one-time login link and a QR code for the web UI |
| `.env.example` | template for `.env` (public URL, bind address, password file path) |
| `DEPLOY.md` | step-by-step deployment guide for a new server |
| `login.txt` | server password (git-ignored); see `login.example.txt` |

## Architecture

```
TUI:      ./opencode.sh  -> tmux session per project -> opencode -> background service 127.0.0.1:49374
Web:      cron @reboot   -> boot.sh -> tmux session opencode-web -> web.sh
                                                                 -> opencode serve WEB_HOST:WEB_PORT
reverse proxy -> https://<PUBLIC_URL> -> WEB_HOST:WEB_PORT
```

The local background service stays on `127.0.0.1` and is never rebound: the web
UI runs as a separate standalone server on an interface the proxy can reach
(the docker bridge gateway when the proxy runs in a container) and the
internet cannot.

## Configuration

```sh
cp .env.example .env
```

| Variable | Meaning |
|---|---|
| `PUBLIC_URL` | public URL of the web UI, scheme included |
| `WEB_HOST` | interface the standalone server binds to; must be reachable from the proxy |
| `WEB_PORT` | port of the standalone server |
| `WEB_ACCESS_FILE` | password file, relative to this directory or absolute |

`WEB_HOST` depends on where the proxy runs:

- proxy is a container (nginx-proxy-manager, Caddy, Traefik, …): bind the docker
  bridge gateway of the network shared with the proxy. For the `gateway`
  network:
  ```sh
  docker network inspect gateway --format '{{(index .IPAM.Config 0).Gateway}}'
  ```
- proxy runs on the host (nginx, Caddy as a system service): bind `127.0.0.1`
  and point the proxy there.

## Reverse proxy requirements

Any reverse proxy works, as long as it:

1. terminates TLS for `PUBLIC_URL` (certificate for that name);
2. forwards to `WEB_HOST:WEB_PORT`;
3. **passes websockets / SSE** through (the UI keeps an event stream open);
4. forwards the `Host` header unchanged.

Examples:

- **nginx-proxy-manager**: Proxy Host, domain = `PUBLIC_URL` host, forward to
  `WEB_HOST:WEB_PORT`, *Websockets Support* on, *Cache Assets* off, SSL tab →
  request a certificate, *Force SSL* on.
- **Caddy** (`Caddyfile`):
  ```
  <PUBLIC_URL host> {
      reverse_proxy WEB_HOST:WEB_PORT
  }
  ```
- **nginx**:
  ```
  server {
      server_name <PUBLIC_URL host>;
      location / {
          proxy_pass http://WEB_HOST:WEB_PORT;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_set_header Host $host;
      }
  }
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
   `PUBLIC_URL`, `WEB_HOST` and `WEB_PORT` (see above).
3. Create the password: `opencode service set password "…"` and put it into
   `login.txt` as `password: …` (mode 0600).
4. Point the reverse proxy at the server as described in
   [Reverse proxy requirements](#reverse-proxy-requirements).
5. Add the boot entry: `crontab -e` ->
   `@reboot /path/to/opencode/boot.sh`.
6. Check: `./pair.sh` prints a link; opening it shows the session list.

Requires: `curl`, `python3` with `qrcode` for the QR (`pip install --user qrcode`;
without it `pair.sh` still prints the link).
