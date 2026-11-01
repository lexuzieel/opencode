# Deploy guide

Order matters: the OpenCode web server first, then the reverse proxy hosts, then
the Authelia gate, then the file dump. Each phase ends with a check that must
pass before the next one starts.

## 0. Prerequisites

- Linux with `systemd`, `curl`, `python3`, `tmux`, `git`, Docker.
- `opencode` v2 in `PATH`:
  ```sh
  curl -fsSL https://opencode.ai/v2/install | bash
  opencode --version
  ```
- A provider logged in: `opencode auth login`.
- A reverse proxy (nginx-proxy-manager, Caddy, nginx) with a domain and TLS.
- Docker network `gateway` shared with the proxy. Proxy hosts reach containers
  by container name; no ports are published to the host.

## 1. Clone and configure

```sh
git clone git@github.com:lexuzieel/opencode.git ~/opencode
cd ~/opencode
cp .env.example .env
```

`.env`:

| Variable | Value |
|---|---|
| `PUBLIC_URL` | public URL of the web UI, scheme included |
| `WEB_HOST` | listen address: docker bridge gateway when the proxy is a container, `127.0.0.1` when the proxy runs on the host |
| `WEB_PORT` | port of the standalone server |
| `WEB_ACCESS_FILE` | password file, relative to this directory or absolute |

Find the bridge gateway:

```sh
docker network inspect gateway --format '{{(index .IPAM.Config 0).Gateway}}'
```

## 2. Web password

```sh
PW=$(openssl rand -hex 16)
opencode service set password "$PW"
printf '# login: opencode\npassword: %s\n' "$PW" > login.txt
chmod 600 login.txt
```

`opencode service set password` restarts the background service, so open TUI
sessions reconnect for a moment and every web session is signed out.

Never change the service hostname away from `127.0.0.1`; the local CLI connects
there, and any other bind makes the TUI hang on "Starting background server".
The public UI is `web.sh`, a separate process.

## 3. Web server and autostart

```sh
./web.sh                      # foreground run, Ctrl+C to stop
curl -s -u "opencode:$(grep -oP 'password: \K\S+' login.txt)" \
  -o /dev/null -w '%{http_code}\n' "$PUBLIC_URL/api/info"    # expect 200
```

Then add the boot entry once:

```sh
crontab -e    # add: @reboot /home/<user>/opencode/boot.sh
```

Check that it works without rebooting:

```sh
tmux -L opencode kill-session -t opencode-web 2>/dev/null
env -i HOME="$HOME" ./boot.sh        # takes ~20s
tmux -L opencode ls
```

## 4. Reverse proxy hosts

Requirements for every host: TLS for the name, forward to the target, websockets
and SSE passed through, `Host` header preserved.

| Host | Forward to | Notes |
|---|---|---|
| `code.<domain>` | `WEB_HOST:WEB_PORT` | OpenCode web UI |
| `auth.<domain>` | `authelia:9091` | Authelia portal |
| `files.<domain>` | `share-files:80` | read-only file dump |

Examples: nginx-proxy-manager (Proxy Host, Websockets on, Cache off, request a
certificate, Force SSL), Caddy `reverse_proxy host:port`, nginx
`proxy_pass` plus `Upgrade`/`Connection` headers. Certificates can use DNS-01
with a Cloudflare token; `~/.agents/NPM.md` documents that flow on the servers
that use nginx-proxy-manager.

## 5. File dump

```sh
cd ~/opencode/deploy/share-files && docker compose up -d
```

The compose file mounts `../../share` read-only and serves it with autoindex.
Directories must be world-readable (`chmod 755`), otherwise nginx inside the
container returns 403.

```sh
echo demo > /tmp/demo.txt
~/opencode/share.sh /tmp/demo.txt --project demo
```

## 6. Authelia gate

```sh
cd ~/opencode/deploy/authelia
./setup.sh                    # generates secrets and a password, starts the container
cat login.txt                 # the login written by setup.sh
```

Then protect hosts in the proxy: add the `auth_request` snippet to each guarded
host's advanced config. It must sit at server level, next to the `location`
block that the proxy generates itself:

```nginx
auth_request /authelia;
error_page 401 =302 https://auth.<domain>/?rd=$scheme://$http_host$request_uri;

location = /authelia {
    internal;
    proxy_pass http://authelia:9091/api/authz/auth-request;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header Cookie $http_cookie;
    proxy_set_header Host $http_host;
}
```

Every guarded host needs a matching rule in `authelia/config/configuration.yml`
(`access_control.rules`, policy `one_factor`); the default policy is deny and an
unknown host returns 403 instead of a redirect. Restart the container after
editing:

```sh
docker compose restart authelia
```

## 7. Skill install

The skill ships in the repository and is linked into the agent's skill
directory:

```sh
ln -sfn ~/opencode/skills/share-files ~/.agents/skills/share-files
```

## 8. Verify

```sh
curl -sI https://files.<domain>/ | head -1      # 302 to the Authelia portal
curl -s  https://auth.<domain>/api/health       # {"status":"OK"}
```

Open the file dump in a browser, log in once, confirm the listing and a file
download. Only a browser proves the session cookie end to end.

## Updating

```sh
opencode upgrade
cd ~/opencode && git pull
tmux -L opencode kill-session -t opencode-web
tmux -L opencode new-session -d -s opencode-web -c ~/opencode 'bash ~/opencode/web.sh'
cd deploy/share-files && docker compose up -d
cd ../authelia && docker compose up -d
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Proxy 502 | `ss -ltn \| grep WEB_PORT`; `tmux -L opencode ls` for `opencode-web` |
| TUI hangs on "Starting background server" | service must listen on `127.0.0.1`; `opencode service set hostname 127.0.0.1 && opencode service start` |
| Web UI asks for a link | expected: `./pair.sh` |
| Guarded host returns 403 instead of a login redirect | host missing from `access_control.rules` in Authelia |
| Dump returns 403 | directory not readable by the nginx user: `chmod 755` |
| QR missing in `pair.sh` | `pip install --user qrcode` |
| `pair.sh` says no password | `login.txt` missing or without a `password:` line |
