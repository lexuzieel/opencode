# Working notes for agents

Server setup for the OpenCode agent: tmux launchers, a standalone web UI behind
a reverse proxy, a read-only file dump and an Authelia gate.

`DEPLOY.md` is the deployment order. `README.md` explains the layout.

## Rules

- The local service stays on `127.0.0.1:49374`; never rebind it. The public UI
  is `web.sh`, a separate process.
- Publish nothing on `0.0.0.0`. Containers reach the proxy over the docker
  network `gateway` by container name.
- Secrets and state are git-ignored: `.env`, `password.txt`, `share/`,
  `deploy/authelia/{config,data,backup}`. Never commit them.
- Server-specific values live in `.env`; scripts read them from there instead
  of hardcoding a domain or an address.
- Commit messages follow Conventional Commits, with no double hyphen as a dash.

## Constraints worth knowing

- The web UI is a host process, not a container: it needs the CLI's provider
  credentials and the same session model as the TUI. Only the dump and Authelia
  run in containers.
- The Authelia image chowns `config/` to `PUID:PGID` from
  `deploy/authelia/.env` on every start. Without those values it runs as root
  and the host user can no longer edit `configuration.yml`.
- The docker network `gateway` may be missing on a new host: create it, and
  reuse an existing network when the proxy already has one under another name.
  Never assume a subnet; read the gateway address from the network.
- `DEPLOY.md` describes nginx-proxy-manager. A host that runs Caddy needs
  `forward_auth authelia:9091` with `uri /api/authz/forward-auth` instead of the
  nginx `auth_request` snippet, and Caddy issues its own certificates.
- There is no bootstrap script yet: a new server is set up by following
  `DEPLOY.md` by hand. Write one only when the target host is known.

## Commands

- `./opencode.sh` starts or reattaches the TUI session of the current folder.
- `./web.sh start|stop|restart|status|passwd` manages the web UI.
- `./pair.sh` prints a one-time login link.
- `./share.sh FILE [--project NAME] [--topic TEXT] [--public]` shares a file.
- `./deploy/authelia/setup.sh` installs Authelia; `guard.sh protect|unprotect ID`
  attaches it to a proxy host.
