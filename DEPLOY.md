# Deploy guide

Step-by-step deployment of this setup on a fresh Linux server. The same steps
work for a second server next to an existing one. Everything below assumes a
systemd host with Docker only where a containerized reverse proxy is used.

## 0. Prerequisites

- Linux with `systemd`, `curl`, `python3`, `tmux`, `git`.
- `opencode` v2 installed and reachable as `opencode` in `PATH`:
  ```sh
  curl -fsSL https://opencode.ai/v2/install | bash
  opencode --version
  ```
- A reverse proxy (nginx-proxy-manager, Caddy, nginx, Traefik) with a domain
  for the web UI and a way to issue a TLS certificate.
- A provider logged in for the agent itself:
  ```sh
  opencode auth login
  ```

## 1. Get the files

```sh
git clone git@github.com:lexuzieel/opencode.git ~/opencode
cd ~/opencode
```

If the repository is not available on the new machine, copy the directory and
skip git.

## 2. Configure

```sh
cp .env.example .env
```

Edit `.env`:

| Variable | Value |
|---|---|
| `PUBLIC_URL` | e.g. `https://code.example.com` |
| `WEB_HOST` | interface for the standalone server (see below) |
| `WEB_PORT` | e.g. `49375` |
| `WEB_ACCESS_FILE` | `login.txt` |

Pick `WEB_HOST` by where the proxy runs:

- **Proxy in a container** (nginx-proxy-manager, Caddy, Traefik): the docker
  bridge gateway of the network shared with the proxy.
  ```sh
  docker network inspect gateway --format '{{(index .IPAM.Config 0).Gateway}}'
  ```
  A value like `172.23.0.1` is typical. This address is reachable from the
  proxy container and not from the internet.
- **Proxy on the host** (nginx or Caddy as a system service): `127.0.0.1`.

## 3. Set the web password

The password protects the web UI API and is the key that mints login links.
Generate it, apply it, and keep the same value in `login.txt` in one go:

```sh
PW=$(openssl rand -hex 16)
opencode service set password "$PW"
printf '# login: opencode\npassword: %s\n' "$PW" > login.txt
chmod 600 login.txt
```

`opencode service set password` restarts the background service, so an open
TUI reconnects for a moment. It also signs every existing web session out.

> Never change the service hostname away from `127.0.0.1`. The local CLI/TUI
> connects to the background service strictly on `127.0.0.1:49374`; binding it
> to another interface makes the TUI hang on "Starting background server…".
> The public web UI is served by the separate `web.sh` process instead.

## 4. Reverse proxy

Requirements: TLS for `PUBLIC_URL`, forward to `WEB_HOST:WEB_PORT`,
**websockets/SSE enabled**, `Host` header passed through.

- **nginx-proxy-manager**: Proxy Hosts → Add:
  domain = `PUBLIC_URL` host, scheme `http`, forward hostname `WEB_HOST`,
  forward port `WEB_PORT`, **Websockets Support on**, Cache Assets off;
  SSL tab → request certificate, Force SSL on.
- **Caddy** (`/etc/caddy/Caddyfile`):
  ```
  code.example.com {
      reverse_proxy 172.23.0.1:49375
  }
  ```
- **nginx**:
  ```
  server {
      server_name code.example.com;
      location / {
          proxy_pass http://172.23.0.1:49375;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_set_header Host $host;
      }
  }
  ```

## 5. First run

```sh
./web.sh          # foreground, Ctrl+C to stop
```

Expect `server listening on http://WEB_HOST:WEB_PORT`. In another shell:

```sh
curl -s -u "opencode:$(grep -oP 'password: \K\S+' login.txt)" \
  -o /dev/null -w '%{http_code}\n' "$PUBLIC_URL/api/info"
```

`200` means proxy, TLS and the server all work.

## 6. Autostart at boot

```sh
crontab -e
```

Add:

```
@reboot /home/<user>/opencode/boot.sh
```

`boot.sh` waits for Docker, then starts `web.sh` inside the tmux session
`opencode-web`. Verify without rebooting:

```sh
tmux -L opencode kill-session -t opencode-web 2>/dev/null
env -i HOME="$HOME" ./boot.sh        # takes ~20s
tmux -L opencode ls
```

## 7. Log in on devices

```sh
./pair.sh
```

Prints a one-time link (5 minutes) and a QR code. Open the link (or scan the
QR) on the phone or in a browser: the device gets a 30-day cookie. Repeat only
for a new device, after clearing cookies, or after a password change.

## 8. Project sessions in the TUI

The tmux TUI launcher is independent of the web server. In a project folder:

```sh
~/opencode/opencode.sh          # or a project wrapper: ./opencode.sh
```

Sessions are shared with the web UI through `~/.local/share/opencode`.

## Updating

```sh
opencode upgrade
cd ~/opencode && git pull
tmux -L opencode kill-session -t opencode-web
tmux -L opencode new-session -d -s opencode-web -c ~/opencode 'bash ~/opencode/web.sh'
```

If a release changes the pairing API, `pair.sh` may need adjusting: it calls
`POST /api/pair` with basic auth on `WEB_HOST:WEB_PORT`.

## Troubleshooting

| Symptom | Check |
|---|---|
| Proxy returns 502 | `ss -ltn \| grep WEB_PORT` — is `web.sh` running? `tmux -L opencode ls` for `opencode-web` |
| TUI hangs on "Starting background server…" | the background service must listen on `127.0.0.1`; reset with `opencode service set hostname 127.0.0.1` and `opencode service start` |
| Web UI asks for a login link | that is expected: run `./pair.sh` |
| Link opened but no session list | proxy strips websockets/SSE; enable them |
| QR missing in `pair.sh` output | `pip install --user qrcode` |
| `pair.sh` says no password | `login.txt` missing or without a `password:` line |
