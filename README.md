# takp-stack

A Docker Compose stack that builds and runs a [TAKP](https://www.takproject.net/) (The Al'Kabor Project — an EQEmu-based EverQuest "Mac" era emulator) server from source, backed by MariaDB, with fail2ban protecting SSH and the database.

On first boot the stack clones the EQEmu-derived server source and the TAKP quest/map repos, compiles the server binaries, loads a database dump, and starts all the server processes under `supervisord`. Subsequent boots skip anything already done (source already cloned, binaries already built, database already loaded) unless you tell it to redo that step.

## Architecture

| Service | Purpose |
|---|---|
| `takp-server` | Compiles (via CMake/Ninja + ccache) and runs the EQEmu server processes: `world`, `queryserv`, `ucs`, four zone launchers, and `loginserver`. Also runs `sshd` so you can get a shell in the build environment. |
| `mariadb` | The game database (schema `peq` by default). Data persists on the host at `${DATA_PATH_HOST}/mariadb`. |
| `fail2ban-server` | Watches `takp-server`'s SSH auth log and bans brute-forcers via `iptables` (host network mode). |
| `fail2ban-mariadb` | Watches MariaDB's auth log the same way. |

Everything is built from Dockerfiles under `containers/`; there are no prebuilt images.

### Volumes and bind mounts

- `./server` → `/home/eqemu/server` — the live server directory: compiled binaries (symlinked), generated configs (`login.json`, `eqemu_config.json`), logs, quests, maps. This is a bind mount, so you can inspect/edit it from the host. It's gitignored.
- `./source` → `/home/eqemu/source` — the cloned EQEmu/TAKP server source. Also bind-mounted and gitignored.
- `build` / `build-cache` — named Docker volumes for the CMake build directory and the ccache cache, so rebuilds are fast and survive container recreation.
- `./data/mariadb` → MariaDB's data directory (host path controlled by `DATA_PATH_HOST`).
- `takp-var-log` / `mariadb-var-log` — named volumes sharing each service's `/var/log` with its matching fail2ban sidecar.

## Prerequisites

- Docker and Docker Compose v2 (`docker compose ...`)
- Enough disk space for a full C++ build (the source tree, build artifacts, and ccache can add up to several GB)
- An SSH public key if you want shell access into the server container

## First-time setup

1. Copy the example environment file and fill in real values:
   ```bash
   cp .env.example .env
   ```
   At minimum, set `MARIADB_PASSWORD` and `MARIADB_ROOT_PASSWORD` to real secrets, and set `SSH_AUTHORIZED_KEYS` to your public key (or a `~`-path to it) if you want SSH access to `takp-server`. `.env` is gitignored — never commit it.

2. Build and start everything:
   ```bash
   docker compose up -d --build
   ```

3. Watch the first boot, which does a lot of work the first time (clone, build, DB load):
   ```bash
   docker compose logs -f takp-server
   ```

The first run will take a while — it's cloning three git repos and compiling the entire server with CMake/Ninja. Subsequent starts are fast because the build and ccache volumes persist.

## Starting and stopping

```bash
# Start everything (build images if needed)
docker compose up -d

# Stop everything, keep volumes/data
docker compose down

# Stop and remove containers but also wipe named volumes (build cache, logs) — NOT the ./data or ./server bind mounts
docker compose down -v

# Restart just the game server (re-runs setup.sh, so it'll re-check source/build/DB state)
docker compose restart takp-server

# Follow logs for one or all services
docker compose logs -f takp-server
docker compose logs -f mariadb
```

`takp-server` has `stop_grace_period: 60s` and the zone launchers run with `stopasgroup`/`killasgroup`, so a `docker compose stop` / `down` gives `supervisord` time to signal `world`, the zones, and `loginserver` to shut down and save characters cleanly instead of being killed outright.

### Managing individual processes once the container is running

Inside the container, the actual game processes (`world`, `queryserv`, `ucs`, the zone launchers, `loginserver`) are managed by `supervisord`, not by Docker directly. To control them individually:

```bash
docker compose exec takp-server supervisorctl status
docker compose exec takp-server supervisorctl restart world
docker compose exec takp-server supervisorctl restart zones:*   # the launcher group
docker compose exec takp-server supervisorctl tail -f world
```

This is useful if, say, a single zone process crashes and you want to bounce it without restarting the whole container (though `autorestart=true` means supervisord will already restart a crashed process on its own).

## What happens on container start (`entrypoint.sh` → `setup.sh`)

1. `entrypoint.sh` (as root): writes `~/.ssh/authorized_keys` from `SSH_AUTHORIZED_KEYS`, starts `rsyslogd` and `sshd`, fixes ownership on the bind-mounted/volume directories, then drops to the `eqemu` user to run `setup.sh`.
2. `setup.sh` (as `eqemu`):
   - Clones `EQArchives/Server` into `/home/eqemu/source` if not already present; otherwise `git pull`s if `AUTO_PULL=true` (the default).
   - Generates `server/login.json` and `server/eqemu_config.json` from the source repo's templates on first run only (DB host/user/password/salt filled in from env vars) — these are **not** regenerated on later runs, so manual edits to them persist.
   - Clones `EQArchives/quests` and `EQMacEmu/Maps` into `server/quests` and `server/maps` (same clone-once/pull-if-`AUTO_PULL` behavior).
   - Builds the server with CMake + Ninja (using ccache) if `/home/eqemu/build/bin/world` doesn't exist yet, or if `FORCE_RECOMPILE=true`.
   - Symlinks the compiled binaries and opcode/patch config files into `server/`.
   - Waits (up to 60s) for MariaDB to accept connections, creates the database if missing, and — only if it has zero tables — extracts and loads the SQL dump from `source/utils/sql/database_full/*.tar.gz`. An already-populated database is left alone.
   - Runs `shared_memory` once to build the shared-memory item/spell cache.
3. `entrypoint.sh` then execs `supervisord`, which starts `world`, `queryserv`, `ucs`, the four zone launchers, and finally `loginserver` (delayed 20s so zones are already registering with `world` before players can log in).

## Rebuilding after source changes

If you edit code under `./source` (or just want a clean rebuild):

```bash
# One-off forced rebuild on next start
docker compose run -e FORCE_RECOMPILE=true --rm takp-server

# Or persistently, for this and future starts: set FORCE_RECOMPILE=true in .env, then
docker compose up -d takp-server
```

Or just shell in and run the build manually (handy for iterating without going through `setup.sh`'s other checks):

```bash
docker compose exec takp-server bash
cd /home/eqemu/build && ninja -v
docker compose restart takp-server   # or supervisorctl restart world/zones:*/etc. to pick up new binaries
```

ccache makes incremental rebuilds fast; the cache lives in the `build-cache` named volume and survives `docker compose down` (but not `down -v`).

## Ports

All ports bind to `${IP_ADDRESS}` (default `0.0.0.0`, i.e. all interfaces).

| Port | Protocol | Purpose |
|---|---|---|
| 2222 → 22 | TCP | SSH into `takp-server` |
| 5998 | TCP | Login server (client connects here first) |
| 6000 | UDP | Login server, legacy/old-client opcode set |
| 6999 | UDP | Reserved for legacy client compatibility |
| 7778 | TCP + UDP | Chat/mail (UCS) server |
| 9000–9001 | TCP + UDP | World server (client handoff) and telnet admin console |
| `PORT_RANGE_LOW`–`PORT_RANGE_HIGH` (default 7000–7030) | TCP + UDP | Zone server ports — one pair per concurrent zone instance. Raise `PORT_RANGE_HIGH` if you need more zones running simultaneously. |
| 3307 (host) → 3306 | TCP | MariaDB, exposed on `MARIADB_EXTERNAL_PORT` for external tools (e.g. a SQL client on the host) |

## fail2ban

`fail2ban-server` and `fail2ban-mariadb` run with `network_mode: host` and `NET_ADMIN`/`NET_RAW` so they can manipulate `iptables` directly (`DOCKER-USER` chain), banning IPs that fail SSH login or MySQL auth repeatedly (3 and 6 retries respectively, within a 10-minute window, 1-day ban — see `containers/fail2ban-*/jail.local`).

## Key environment variables (`.env`)

| Variable | Notes |
|---|---|
| `MARIADB_DATABASE` | Schema name (default `peq`) |
| `MARIADB_USER` / `MARIADB_PASSWORD` | App DB credentials, written into the generated server configs |
| `MARIADB_ROOT_PASSWORD` | Used by `setup.sh` to create the database and load the initial dump |
| `MARIADB_PORT` / `MARIADB_EXTERNAL_PORT` | Internal MariaDB port vs. the host-exposed port |
| `DATA_PATH_HOST` | Where MariaDB's data directory lives on the host (default `./data`) |
| `IP_ADDRESS` | Interface to bind published ports to |
| `SSH_AUTHORIZED_KEYS` | Public key(s) allowed to SSH into `takp-server` as `eqemu` |
| `PORT_RANGE_LOW` / `PORT_RANGE_HIGH` | Zone port range — determines max concurrent zones |
| `AUTO_PULL` | `true` (default) pulls latest source/quests/maps on every container start |
| `FORCE_RECOMPILE` | `true` forces a full rebuild even if binaries already exist |
| `TZ` | Container timezone |

## Troubleshooting

- **Build fails / takes forever**: check `docker compose logs -f takp-server` during first boot — CMake/Ninja output streams through. A failed build leaves no `build/bin/world`, so it'll retry the full build on next start.
- **"Can't log in to MariaDB"**: `setup.sh` retries for 60s before giving up — this usually means `MARIADB_ROOT_PASSWORD` in `.env` doesn't match what MariaDB was actually initialized with (it's only set on the *first* `mariadb` container start against an empty `./data/mariadb`). If you need to reset credentials, you generally need to wipe `./data/mariadb` and let it reinitialize — this destroys the database, so back it up first if it matters.
- **Config changes not taking effect**: `login.json` and `eqemu_config.json` are only generated once; edit them directly under `./server/` and restart the relevant process via `supervisorctl`, or delete them and restart `takp-server` to have `setup.sh` regenerate from env vars.
- **Players can't log in right after a restart**: `loginserver` intentionally starts ~20s after everything else so zones are registered first; give it a moment.

## Backing up the database

```bash
docker compose exec mariadb mysqldump -u root -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE" > backup.sql
```

Or just stop the stack and copy `./data/mariadb` elsewhere.
