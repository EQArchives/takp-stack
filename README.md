# takp-stack

Run your own [TAKP](https://www.takproject.net/) (The Al'Kabor Project) EverQuest server with a single command.

Setting up an EQEmu server by hand means compiling C++, installing a database, loading data, and wiring up a half-dozen config files. This project does all of that for you inside Docker. You fill in a couple of passwords, start it, and wait. When it's done you have a working Al'Kabor-era server you can log into with the TAKP client.

It's good for:

- Playing solo or with a few friends on your own server
- Poking at the database, quests, or server code without breaking a live server
- Getting a dev environment for the [EQArchives](https://github.com/EQArchives) server code

## What you need

- A computer running Linux, or Windows/macOS with [Docker Desktop](https://www.docker.com/products/docker-desktop/). An always-on Linux box or a cheap VPS works well if friends will be playing.
- About 10 GB of free disk space and at least 4 GB of RAM
- The [TAKP client](https://www.takproject.net/) installed on whatever machine you play from

## Quick start

1. **Download this project.**
   ```bash
   git clone https://github.com/EQArchives/takp-stack.git
   cd takp-stack
   ```

2. **Make your settings file.**
   ```bash
   cp .env.example .env
   ```
   Open `.env` in a text editor and replace both `<template>` values (`MARIADB_PASSWORD` and `MARIADB_ROOT_PASSWORD`) with passwords of your own. You won't need to type them often, so make them long. While you're there, give your server a name with `SERVER_LONG_NAME`. That's what shows up in the server list. Leave everything else alone for now.

3. **Start the server.**
   ```bash
   docker compose up -d --build
   ```

4. **Wait for it.** The first start downloads the server code, compiles it, and loads the game database. Plan on 15–45 minutes depending on your machine. To watch it work:
   ```bash
   docker compose logs -f takp-server
   ```
   It's ready once the log stops scrolling and shows `loginserver` starting up. Press `Ctrl+C` to stop watching. The server keeps running.

After that, starts take a few seconds. The server also starts again by itself when your computer reboots.

## Logging in

### Point your client at the server

In your TAKP client folder, open `eqhost.txt` and change the login server to your server's address:

```
[LoginServer]
Host=127.0.0.1:6000
```

Use `127.0.0.1` if the server is on the same computer you're playing on. Otherwise use the server's IP address, either its LAN IP (like `192.168.1.50`) or its public IP.

**Playing from another computer on your home network?** Also set `SERVER_LOCAL_ADDRESS` in `.env` to the server's LAN IP and run `docker compose up -d`. Otherwise you'll see the server list but get stuck at character select.

Keep a copy of the original `eqhost.txt` so you can switch back to the official TAKP servers later.

### Create an account

There's no simple way to create accounts yet. A command for it is planned.

In the meantime, you can turn on auto-create:

1. Open `server/login.json` (see [Editing config files](#editing-config-files)) and change `"auto_create_accounts": false` to `true`.
2. Run `docker compose restart takp-server`.
3. Log in with any username and password. The account is created the first time you use it.

> **Heads up:** accounts made this way are created with a blank forum ID, which can cause problems later. Fine for trying things out. For a server other people will play on, wait for the account command.

### Make yourself a GM

After you've logged in once, run this. Replace `yourname` with your account name and `yourpassword` with the `MARIADB_ROOT_PASSWORD` from `.env`.

```bash
docker compose exec mariadb mysql -u root -p'yourpassword' peq \
  -e "UPDATE account SET status = 255 WHERE name = 'yourname';"
```

Log out completely and back in for it to take effect.

## Playing with friends over the internet

To let people connect from outside your home network:

1. **Forward these UDP ports** on your router to the machine running the server: `6000`, `7778`, `9000`, and the zone range (`7000–7030` unless you've changed `PORT_RANGE_LOW`/`PORT_RANGE_HIGH` in `.env`). No TCP ports are needed.
2. **Tell the server its public address.** Set `SERVER_PUBLIC_ADDRESS` in `.env` to your public IP (search "what is my IP" to find it) and run `docker compose up -d`.
3. Have your friends put your public IP in their `eqhost.txt`.

Only the game ports are open to the network. The admin and developer ports (SSH, database, telnet console) only accept connections from the server machine itself unless you choose to open them. See [Ports](#ports).

## Everyday use

| To... | Run |
|---|---|
| Start the server | `docker compose up -d` |
| Stop the server (characters are saved) | `docker compose down` |
| Restart the server | `docker compose restart takp-server` |
| See what the server is doing | `docker compose logs -f takp-server` |
| Check that every server process is up | `docker compose exec takp-server supervisorctl status` |

### Updates

Each time the server starts, it pulls the latest server code, quests, and maps. Updated quests and maps take effect on the next restart. If the server code itself changed, you also need to rebuild:

```bash
docker compose run --rm -e FORCE_RECOMPILE=true takp-server
docker compose up -d
```

To stay on your current version, add `AUTO_PULL=false` to `.env`.

Your characters and database are never touched by updates.

### Running more zones

Out of the box, 30 zones run all the time: the boat docks plus a set of popular zones. That keeps memory use reasonable on a small machine, but any zone not in the set can't be entered. To run more:

1. Turn the zones on in the database. This example turns on every zone up through Velious:
   ```bash
   docker compose exec mariadb sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" peq \
     -e "UPDATE launcher_zones SET enabled = 1 WHERE expansion IN (\"classic\", \"kunark\", \"velious\");"'
   ```
2. Make sure there are more zone ports than running zones. Count the running zones with:
   ```bash
   docker compose exec mariadb sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" peq \
     -N -e "SELECT COUNT(*) FROM launcher_zones WHERE enabled = 1;"'
   ```
   Then raise `PORT_RANGE_HIGH` in `.env` so `PORT_RANGE_HIGH − PORT_RANGE_LOW + 1` is larger than that number.
3. Run `docker compose up -d`, and forward the larger range on your router.

Each zone uses memory even when nobody is in it, so add zones in batches and keep an eye on your machine.

### Editing config files

Server settings that aren't in `.env` live in two files in the `server/` folder: `eqemu_config.json` (the game server) and `login.json` (the login server).

The surest way to edit them, on any setup, is through the container. Use `nano` if you're not sure which to pick:

```bash
docker compose exec -u eqemu -w /home/eqemu/server takp-server nano login.json
docker compose exec -u eqemu -w /home/eqemu/server takp-server vi login.json
```

In nano, save with `Ctrl+O` and exit with `Ctrl+X`. Then run `docker compose restart takp-server`.

You can also open the files in your own text editor:

- **Docker Desktop (Mac or Windows):** works as is.
- **Linux:** set `PUID` and `PGID` in `.env` to the output of `id -u` and `id -g`, then run `docker compose up -d --build`. The files will then be owned by you. If your IDs are 1000, the defaults already match.
- **Rootless Docker:** the files show up as owned by a high-numbered user (like `100999`) and `PUID` can't change that. Use the commands above, or `sudo`.

If the server won't start after an edit, see [Troubleshooting](#troubleshooting).

### Backups

All your characters, accounts, and world data live in the database. Back it up with:

```bash
docker compose exec mariadb sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" peq' > backup-$(date +%F).sql
```

Or stop the server and copy the `data/` folder somewhere safe.

Also keep a copy of `server/login.json`. It holds the password salt for player accounts, and a database backup restored without it leaves every account unable to log in.

## Troubleshooting

**The first start failed partway through.** Look at the end of `docker compose logs takp-server` for the error, fix it, and run `docker compose up -d` again. Finished steps are skipped, so it picks up where it left off.

**"Can't log in to MariaDB."** The database password is set the first time the database starts and never changes after that. If you edited the passwords in `.env` later, they no longer match. Change them back, or, if you have nothing worth keeping, delete the `data/` folder and start over.

**The server won't start after I edited a config file.** Run `docker compose logs --tail 5 takp-server`. If you see `ERROR: server/... is broken`, the message gives the line and column of the mistake, usually a missing or extra comma or quote. Fix it and run `docker compose up -d`. For `eqemu_config.json` only, you can also delete the file and run `docker compose up -d` to regenerate it, though that loses your edits to it. **Don't delete `login.json`:** a regenerated one gets a new password salt, and every existing account's password stops working.

**I can't log in right after a restart.** The login server waits until all enabled zones are up, which can take a minute or two. Check `docker compose logs takp-server | grep "loginserver:"` to see how far along it is.

**I edited `.env` but my change didn't show up in `server/login.json` or `server/eqemu_config.json`.** Those files are created once on the first start, so your hand edits to them are safe. The exceptions are the `SERVER_*`, `TELNET_ENABLED` and `PORT_RANGE_*` settings, which are reapplied on every start. For anything else, edit the files directly. Don't delete `login.json` to regenerate it: that changes the password salt and breaks every existing account.

**I'm stuck at "Submitting to World Server" after picking the server.** Check `server/eqemu_config.json`: under `loginserver1`, `legacy` must be `"0"` for the built-in login server. With `"1"`, the login server never hands you off to world. New installs get `"0"` automatically. Change it, then run `docker compose restart takp-server`.

**Some zones can't be entered.** Only the enabled zones are running. See [Running more zones](#running-more-zones).

**Friends can see the server list but get stuck at character select or zoning.** Usually a port forward is missing (check the zone range) or `SERVER_PUBLIC_ADDRESS` in `.env` isn't set to your public IP. If it's players on your home network who are stuck, check `SERVER_LOCAL_ADDRESS` instead.

---

## For developers

The rest of this is for people who want to work on the server itself.

### What's running

| Service | What it is |
|---|---|
| `takp-server` | Builds and runs `world`, `queryserv`, `ucs`, the zone launchers, and `loginserver`, all under `supervisord`. Also runs `sshd`. |
| `mariadb` | Game database. |
| `fail2ban-server`, `fail2ban-mariadb` | Watch SSH and MariaDB auth logs and ban through the `DOCKER-USER` iptables chain. |

On boot, `containers/takp-server/setup.sh` checks what's missing and does only that work. Read it if you want the details.

### Ports

Player ports listen on `IP_ADDRESS` (all interfaces by default). Everything else listens on `127.0.0.1` only, so it's reachable from the host machine but not the network. To open one up, set its `*_BIND` variable to `0.0.0.0` in `.env` and run `docker compose up -d`.

| Port | Used by | Listens on |
|---|---|---|
| 6000/udp | Login server (client login) | `IP_ADDRESS` |
| 9000/udp | World (character select) | `IP_ADDRESS` |
| 7778/udp | UCS (chat and mail) | `IP_ADDRESS` |
| 7000–7030/udp | Zones (`PORT_RANGE_LOW`–`PORT_RANGE_HIGH`) | `IP_ADDRESS` |
| 2222/tcp | SSH into `takp-server` | `SSH_BIND` |
| 3307/tcp | MariaDB | `MARIADB_BIND` |
| 5998/tcp | Login server: world server registration | `LOGIN_TCP_BIND` |
| 9000/tcp | World telnet console (also needs `TELNET_ENABLED=true`) | `TELNET_BIND` |
| 9001/tcp | World: zone/launcher/UCS connections | `WORLD_TCP_BIND` |

To reach a localhost-only port from another machine, tunnel through SSH to the host instead of opening it:

```bash
ssh -L 3307:localhost:3307 you@yourserver
```

The telnet console sends passwords in plain text, so don't expose it to the network.

[fail2ban](https://github.com/fail2ban/fail2ban) watches SSH and MariaDB logins and bans IPs that keep guessing passwords. It matters most if you open those ports up.

### Where things live

- `source/` holds the [EQArchives/Server](https://github.com/EQArchives/Server) checkout. Edit code here.
- `server/` is the runtime directory: configs, logs, `quests/`, `maps/`, and symlinks to the built binaries.
- `data/mariadb/` holds the database files.
- The CMake build directory and ccache are stored in named Docker volumes (`build`, `build-cache`). They survive `down` but not `down -v`.

### Iterating on server code

```bash
docker compose exec -u eqemu -w /home/eqemu/build takp-server ninja
docker compose exec takp-server supervisorctl restart world zones:*
```

ccache keeps incremental builds fast. To SSH in instead of using `exec`, paste your public key (the one line in `~/.ssh/id_ed25519.pub` or similar) into `SSH_AUTHORIZED_KEYS` in `.env`, run `docker compose up -d`, and connect with `ssh -p 2222 eqemu@localhost`. SSH only accepts connections from the server machine unless you change `SSH_BIND`.

### Using an external login server

By default, world registers with the login server built into this stack, and player accounts live in your database. To list your server on a shared login server instead, you need an account for your server from whoever runs it.

**Decide this before anyone plays.** World can only use one login server, and switching later breaks accounts. Account IDs aren't unique across login servers, so an account from the new login server can end up attached to an existing player's characters.

1. Edit `server/eqemu_config.json` (see [Editing config files](#editing-config-files)) and set the `loginserver1` block under `world`:
   ```json
   "loginserver1": {
     "host": "login.example.com",
     "port": "5998",
     "account": "your-server-account",
     "password": "your-server-password",
     "legacy": "0"
   }
   ```
   Don't add `loginserver2` or `loginserver3`. Leave `legacy` at `"0"` unless the login server's operator tells you to use `"1"`.
2. Run `docker compose restart takp-server`.
3. Players point `eqhost.txt` at the external login server, not at yours.

`setup.sh` only writes `loginserver1` when it first creates `eqemu_config.json`, so your edit is kept across restarts. The built-in login server keeps running but has no world server listed, so nobody should create accounts on it.

### Settings in `.env`

The defaults are fine for most people. The ones you might change:

| Variable | What it does |
|---|---|
| `SERVER_LONG_NAME` / `SERVER_SHORT_NAME` | Your server's name in the server list, and a short ID for it. |
| `SERVER_LOCAL_ADDRESS` | Address for players on this machine or your home network: `127.0.0.1`, or the server's LAN IP for LAN play. |
| `SERVER_PUBLIC_ADDRESS` | Your public IP, for players over the internet. Leave empty otherwise. |
| `IP_ADDRESS` | Which network interface the player ports listen on. Set it to `127.0.0.1` to keep the game local-only. |
| `*_BIND` | Which interface each admin/developer port listens on. See [Ports](#ports). |
| `TELNET_ENABLED` | Set to `true` to turn on the world telnet console. |
| `PORT_RANGE_LOW` / `PORT_RANGE_HIGH` | Ports world hands out to zones, also published to players. Must be larger than the number of enabled zones. See [Running more zones](#running-more-zones). |
| `AUTO_PULL` | Set to `false` to stop pulling updates on start. |
| `FORCE_RECOMPILE` | Set to `true` to do a full rebuild on every start. |
| `SSH_AUTHORIZED_KEYS` | Your SSH *public* key (one line, from a `.pub` file). Empty disables SSH logins. |
| `DATA_PATH_HOST` | Where the database files are stored on the host. |
| `PUID` / `PGID` | User and group IDs that own `server/` and `source/` on the host. See [Editing config files](#editing-config-files). |
| `TZ` | Server timezone. Defaults to `UTC`. Use standard names like `America/New_York`; old names like `US/Eastern` don't work. |
| `CONTAINER_HOSTNAME` | Hostname inside the `takp-server` container, as seen in the shell prompt and logs. Not your server's public name. |

## License

GPL-3.0. See [LICENSE](LICENSE).
