#!/bin/bash
set -e

: "${MARIADB_DATABASE:?MARIADB_DATABASE is not set}"
: "${MARIADB_USER:?MARIADB_USER is not set}"
: "${MARIADB_PASSWORD:?MARIADB_PASSWORD is not set}"
: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD is not set}"

# Do app work that doesn't require root permissions
# ---- Source ----
if [ ! -d "/home/eqemu/source/.git" ]; then
  git clone https://github.com/EQArchives/Server.git /home/eqemu/source
else
  if [ "${AUTO_PULL:-true}" = "true" ]; then
    cd /home/eqemu/source && git pull
  fi
fi

# ---- Config files (generated once, then left alone) ----
if [ ! -f "/home/eqemu/server/login.json" ]; then
  salt=$(openssl rand -hex 32)
  jq --arg db "$MARIADB_DATABASE" --arg user "$MARIADB_USER" \
    --arg pass "$MARIADB_PASSWORD" --arg salt "$salt" '
      .database.host = "mariadb" | .database.db = $db |
      .database.user = $user | .database.password = $pass | .database.salt = $salt |
      .logsys_database.host = "mariadb" | .logsys_database.db = $db |
      .logsys_database.user = $user | .logsys_database.password = $pass
    ' /home/eqemu/source/loginserver/login_util/login.json >/home/eqemu/server/login.json
  chmod 600 /home/eqemu/server/login.json
fi

if [ ! -f "/home/eqemu/server/eqemu_config.json" ]; then
  jq --arg db "$MARIADB_DATABASE" --arg user "$MARIADB_USER" --arg pass "$MARIADB_PASSWORD" '
        .server.database.host = "mariadb" | .server.database.db = $db |
        .server.database.username = $user | .server.database.password = $pass
        .server.world.loginserver1.host = "127.0.0.1" |
        .server.world.loginserver1.account = "" |
        .server.world.loginserver1.password = ""
    ' /home/eqemu/source/utils/defaults/eqemu_config.json >/home/eqemu/server/eqemu_config.json
  chmod 600 /home/eqemu/server/eqemu_config.json
fi

# ---- Quests and Maps ----
if [ ! -d "/home/eqemu/server/quests/.git" ]; then
  git clone https://github.com/EQArchives/quests.git /home/eqemu/server/quests
elif [ "${AUTO_PULL:-true}" = "true" ]; then
  cd /home/eqemu/server/quests && git pull
fi

if [ ! -d "/home/eqemu/server/maps/.git" ]; then
  git clone https://github.com/EQMacEmu/Maps.git /home/eqemu/server/maps
elif [ "${AUTO_PULL:-true}" = "true" ]; then
  cd /home/eqemu/server/maps && git pull
fi

# ---- Build ----
if [ ! -f "/home/eqemu/build/bin/world" ] || [ "${FORCE_RECOMPILE:-false}" = "true" ]; then
  mkdir -p /home/eqemu/build
  cd /home/eqemu/build
  cmake -GNinja \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DEQEMU_BUILD_LOGIN=ON \
    -DEQEMU_BUILD_LUA=ON \
    -DEQEMU_BUILD_PERL=ON \
    -DEQEMU_BUILD_LOGGING=ON /home/eqemu/source
  ninja -v
fi

# ---- Server directory layout ----
mkdir -p /home/eqemu/server/shared/
mkdir -p /home/eqemu/server/logs/
mkdir -p /home/eqemu/server/assets/opcodes/
mkdir -p /home/eqemu/server/assets/patches/

ln -sf /home/eqemu/source/utils/patches/chat_opcodes.conf /home/eqemu/server/assets/opcodes/chat_opcodes.conf
ln -sf /home/eqemu/source/utils/patches/opcodes.conf /home/eqemu/server/assets/opcodes/opcodes.conf
ln -sf /home/eqemu/source/loginserver/login_util/login_opcodes*.conf /home/eqemu/server/assets/opcodes/
ln -sf /home/eqemu/source/utils/patches/patch_Mac.conf /home/eqemu/server/assets/patches/patch_Mac.conf

for bin in eqlaunch libcommon.a libluabind.a loginserver queryserv shared_memory ucs world zone; do
  ln -sf "/home/eqemu/build/bin/$bin" "/home/eqemu/server/$bin"
done

# ---- Database ----
DB_NAME="$MARIADB_DATABASE"
export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"
MYSQL="mysql --skip-ssl -h mariadb -u root"
DUMP_DIR="/home/eqemu/source/utils/sql/database_full"

echo "Waiting for MariaDB..."
for i in $(seq 1 30); do
  $MYSQL -e "SELECT 1" >/dev/null 2>&1 && break
  if [ "$i" -eq 30 ]; then
    echo "Can't log in to MariaDB as $DB_USER@$DB_HOST. Check the password." >&2
    exit 1
  fi
  sleep 2
done

$MYSQL -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`"

tables=$($MYSQL -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME'")
if [ "$tables" -eq 0 ]; then
  dump=$(ls -t "$DUMP_DIR"/*.tar.gz 2>/dev/null | head -1)
  if [ -z "$dump" ]; then
    echo "No database dump found in $DUMP_DIR" >&2
    exit 1
  fi
  echo "Loading $dump into $DB_NAME..."
  tmp=$(mktemp -d)
  tar -xzf "$dump" -C "$tmp"
  for pattern in 'alkabor*.sql' 'player_tables*.sql' 'data_tables*.sql' 'login_tables*.sql'; do
    for f in $(find "$tmp" -name "$pattern" | sort); do
      echo "  $(basename "$f")"
      $MYSQL "$DB_NAME" <"$f"
    done
  done
  rm -rf "$tmp"
else
  echo "$DB_NAME already has $tables tables, skipping load."
fi

cd /home/eqemu/server
./shared_memory
