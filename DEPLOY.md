# Deploy guide

Order matters: the web server first, then the reverse proxy hosts, then the
file dump, then the Authelia gate. Each phase ends with a check that must pass
before the next one starts.

## 0. Prerequisites

- Linux with `systemd`, `curl`, `python3`, `tmux`, `git`, `openssl`.
- Docker with the `compose` plugin.
- GNU `grep` (the scripts use `-P`) and `iproute2` (only when `WEB_HOST` is a
  docker bridge address).
- `uuidgen` for public links; without it `share.sh` falls back to `openssl`.
- `opencode` v2 in `PATH`:
  ```sh
  curl -fsSL https://opencode.ai/v2/install | bash
  opencode --version
  ```
- A provider logged in: `opencode auth login`.
- A reverse proxy (nginx-proxy-manager, Caddy, nginx) with a domain and TLS.

Every container joins the docker network `gateway`, and the proxy reaches them
by container name, so no port is published to the host:

```sh
docker network inspect gateway >/dev/null 2>&1 || docker network create gateway
```

## 1. Clone and configure

```sh
git clone <repository> ~/opencode
cd ~/opencode
cp .env.example .env
$EDITOR .env
```

| Variable | Value |
|---|---|
| `PUBLIC_URL` | public URL of the web UI, scheme included |
| `SHARE_URL` | public base URL of the file dump, scheme included, no trailing slash |
| `SHARE_PUBLIC_URL` | base URL for published links, served by `deploy/share-public`; falls back to `<SHARE_URL>/public/<uuid>/` |
| `SHARE_ROOT` | where `share.sh` keeps files; default `share/` in this directory |
| `WEB_HOST` | listen address: docker bridge gateway when the proxy is a container, `127.0.0.1` when the proxy runs on the host |
| `WEB_PORT` | port of the standalone server |
| `WEB_ACCESS_FILE` | password file, relative to this directory or absolute; default `password.txt` |

Find the bridge gateway:

```sh
docker network inspect gateway --format '{{(index .IPAM.Config 0).Gateway}}'
```

## 2. Web password

```sh
./web.sh passwd               # generates the password into password.txt, 0600
./web.sh restart              # applies it and prints a login link
```

`passwd` prints the new password once and replaces the file; run it without
`--yes`, so it asks first. Non-interactively, as in a script, add `--yes`.

The password lives in `password.txt` and is read by the web server once, when
its process starts. Editing the file by hand therefore changes nothing until
`./web.sh restart`; `./web.sh status` reports that mismatch as `401` instead of
letting you discover it at the login screen.

`opencode service set password` is a separate credential for the background
service on `127.0.0.1:49374`, which the TUI uses. Set it only if you need both
to match:

```sh
opencode service set password "$(grep -oP '^password: \K\S+' password.txt)"
```

Never change the service hostname away from `127.0.0.1`; the local CLI connects
there, and any other bind makes the TUI hang on "Starting background server".
The public UI is `web.sh`, a separate process.

## 3. Web server and autostart

```sh
./web.sh                      # foreground run, Ctrl+C to stop
./web.sh status               # tmux session, port, and password match
```

Then add the boot entry once:

```sh
crontab -e    # add: @reboot /home/<user>/opencode/boot.sh
```

Check that it works without rebooting:

```sh
tmux -L opencode kill-session -t opencode-web 2>/dev/null || true
env -i HOME="$HOME" ./boot.sh        # waits 20s for docker, then starts
./web.sh status                      # expect api: 200
```

## 4. Reverse proxy hosts

Requirements for every host: TLS for the name, forward to the target, websockets
and SSE passed through, `Host` header preserved.

| Host | Forward to | Notes |
|---|---|---|
| `code.<domain>` | `WEB_HOST:WEB_PORT` | OpenCode web UI |
| `auth.<domain>` | `authelia:9091` | Authelia portal |
| `files.<domain>` | `share-files:80` | read-only file dump, behind the gate |
| `share.<domain>` | `share-public:80` | published links only, no gate, no listing |

Examples: nginx-proxy-manager (Proxy Host, Websockets on, Cache off, request a
certificate, Force SSL), Caddy `reverse_proxy host:port`, nginx `proxy_pass`
plus `Upgrade`/`Connection` headers. Certificates can use DNS-01 with a
Cloudflare token.

## 5. File dump

Create the directory before the container does, otherwise docker creates it as
root and `share.sh` cannot write there:

```sh
mkdir -p ~/opencode/share && chmod 755 ~/opencode/share
printf '# File dump: not for search engines.\nUser-agent: *\nDisallow: /\n' \
  > ~/opencode/share/robots.txt
cd ~/opencode/deploy/share-files && docker compose up -d
```

The compose file mounts `../../share` read-only and serves it with autoindex.
Directories must be world-readable (`chmod 755`), otherwise nginx inside the
container returns 403.

```sh
echo demo > /tmp/demo.txt
~/opencode/share.sh /tmp/demo.txt --project demo      # private link
~/opencode/share.sh /tmp/demo.txt --project demo --public   # plus public link
```

Every share is private by default and needs an Authelia login. `--public` adds a
symlink under `public/<uuid>/` and appends a row to `share/public-links.md`.

### The published tree has its own host

Published links are handed to people, and sometimes to an automated reader, so
they cannot sit behind the same `robots.txt` as the private tree: a file that
says `Disallow: /` next to `Allow: /public/` gets the strict reading from some
clients, which blocks exactly the links we give out. Two small containers keep
the two jobs apart.

```sh
cd ~/opencode/deploy/share-public && docker compose up -d
```

It mounts the same `../../share` read-only, serves only `public/` as its root,
answers `Allow: /`, sends `X-Robots-Tag: index, follow`, and never lists a
directory. Point `share.<domain>` at it and set `SHARE_PUBLIC_URL` so `share.sh`
prints public links on that host:

```sh
# .env
SHARE_PUBLIC_URL=https://share.example.com
```

Check it the way a reader will, without a session:

```sh
curl -sI https://share.<domain>/<uuid>/file.txt   # 200, X-Robots-Tag: index, follow
curl -s  https://share.<domain>/robots.txt        # Allow: /
curl -sI https://files.<domain>/<project>/<date>/file.txt   # 302 to the gate
```

## 6. Authelia gate

```sh
cd ~/opencode/deploy/authelia
AUTHELIA_DOMAIN=example.com ./setup.sh   # generates secrets and a password
cat authelia-login.txt
```

State lives in `deploy/authelia/config/` and `data/`, both git-ignored. The
compose project is named `opencode-authelia` while the container keeps the name
`authelia`, so a second checkout cannot take the live container over.

The container runs as `PUID:PGID` from `deploy/authelia/.env`, which `setup.sh`
fills with the host user, and the image chowns `config/` to that uid on every
start. Without those values it runs as root and takes the directory over, which
leaves `configuration.yml` unreadable for the host user.

Guard a host (this writes the `auth_request` snippet into the proxy host):

```sh
export NPM_URL=http://10.0.0.5:81 NPM_IDENTITY=agent@example.com \
       NPM_SECRET=... AUTH_DOMAIN=auth.example.com
./guard.sh protect <npm-host-id>
./guard.sh unprotect <npm-host-id>     # restores the previous advanced_config
```

Every guarded host also needs a matching rule in
`deploy/authelia/config/configuration.yml` (`access_control.rules`, policy
`one_factor`); the default policy is deny, so an unknown host returns 403
instead of a redirect. Restart the container after editing:

```sh
docker compose restart authelia
```

The dump has one bypass rule ahead of its login rule, for `^/public(/.*)?$` and
`^/robots\.txt$`, which is what makes published links open without a session.

## 7. Skills

The skills ship in the repository and are linked into the agent's skill
directory:

```sh
mkdir -p ~/.agents/skills
for s in ~/opencode/skills/*; do ln -sfn "$s" "$HOME/.agents/skills/$(basename "$s")"; done
```

## 8. Verify

```sh
curl -sI https://files.<domain>/ | head -1      # 302 to the Authelia portal
curl -s  https://auth.<domain>/api/health       # {"status":"OK"}
curl -sI https://files.<domain>/robots.txt | head -1        # 200, no login
curl -sI https://files.<domain>/public/ | head -1           # 404, no listing
```

Open the file dump in a browser, log in once, confirm the listing and a file
download. Only a browser proves the session cookie end to end.

## Updating

```sh
opencode upgrade
cd ~/opencode && git pull
tmux -L opencode kill-session -t opencode-web
./boot.sh                       # waits 20s, starts the web session again
cd deploy/share-files && docker compose up -d
cd ../authelia && docker compose up -d
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Proxy 502 | `ss -ltn \| grep WEB_PORT`; `tmux -L opencode ls` for `opencode-web` |
| TUI hangs on "Starting background server" | service must listen on `127.0.0.1`: `opencode service set hostname 127.0.0.1 && opencode service start` |
| Web UI asks for a link | expected: `./pair.sh` |
| `web.sh status` says `401` | the process runs with another password than `password.txt`: `./web.sh restart` |
| `pair.sh` says no password | `password.txt` missing or without a `password:` line: `./web.sh passwd` |
| `pair.sh` says PUBLIC_URL is unset | no `.env`, or `.env` without `PUBLIC_URL` |
| Guarded host returns 403 instead of a login redirect | host missing from `access_control.rules` in Authelia |
| Dump returns 403 | directory not readable by the nginx user: `chmod 755` |
| `share.sh` prints local paths | `SHARE_URL` is not set in `.env` |
| `docker compose up` fails with "network gateway not found" | `docker network create gateway` |
| Login to the dump loops back | cookie domain in `session.cookies` must match the parent domain of every guarded host |
| QR missing in `pair.sh` | `pip install --user qrcode` |
