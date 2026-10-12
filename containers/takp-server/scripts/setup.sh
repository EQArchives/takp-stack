#!/bin/bash
set -e

: "${MARIADB_DATABASE:?MARIADB_DATABASE is not set}"
: "${MARIADB_USER:?MARIADB_USER is not set}"
: "${MARIADB_PASSWORD:?MARIADB_PASSWORD is not set}"
: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD is not set}"

# Do app work that doesn't require root permissions
# ---- Source ----
if [ ! -d "/home/eqemu/source/.git" ]; then
  git clone ${SOURCE_BRANCH:+--branch "$SOURCE_BRANCH"} "$SOURCE_REPO" /home/eqemu/source
else
  if [ "${AUTO_PULL:-false}" = "true" ]; then
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
  world_key=$(openssl rand -hex 32)
  tmp=$(mktemp)
  jq --arg db "$MARIADB_DATABASE" --arg user "$MARIADB_USER" --arg pass "$MARIADB_PASSWORD" \
    --arg key "$world_key" \
    '
        .server.world.key = $key |
        .server.database.host = "mariadb" | .server.database.db = $db |
        .server.database.username = $user | .server.database.password = $pass |
        .server.qsdatabase.host = "mariadb" | .server.qsdatabase.db = $db |
        .server.qsdatabase.username = $user | .server.qsdatabase.password = $pass |
        .server.world.loginserver1.host = "127.0.0.1" |
        .server.world.loginserver1.account = "" |
        .server.world.loginserver1.password = "" |
        .server.world.loginserver1.legacy = "0" |
        del(.server.world.loginserver2, .server.world.loginserver3)
    ' /home/eqemu/source/utils/defaults/eqemu_config.json >"$tmp"
  mv "$tmp" /home/eqemu/server/eqemu_config.json
  chmod 600 /home/eqemu/server/eqemu_config.json
fi

# ---- Check hand-edited config files before using them ----
check_json() {
  local file="$1" err
  if [ ! -s "$file" ]; then
    err="the file is empty"
  elif ! err=$(jq empty "$file" 2>&1); then
    :
  else
    return 0
  fi
  echo "ERROR: server/$(basename "$file") is broken: $err" >&2
  if [ "$(basename "$file")" = "login.json" ]; then
    echo "Fix it on the host. Don't delete it: a new login.json gets a new password salt, and every account's password stops working." >&2
  else
    echo "Fix it on the host, or delete it and run 'docker compose up -d' to regenerate it." >&2
  fi
  exit 1
}
check_json /home/eqemu/server/login.json
check_json /home/eqemu/server/eqemu_config.json

# ---- Settings owned by .env (applied every start) ----
tmp=$(mktemp)
jq --arg long "${SERVER_LONG_NAME:-My TAKP Server}" \
  --arg short "${SERVER_SHORT_NAME:-mytakp}" \
  --arg local "${SERVER_LOCAL_ADDRESS:-127.0.0.1}" \
  --arg public "${SERVER_PUBLIC_ADDRESS:-}" \
  --arg telnet "${TELNET_ENABLED:-false}" \
  --arg plow "${PORT_RANGE_LOW:-7000}" \
  --arg phigh "${PORT_RANGE_HIGH:-7030}" \
  '
    .server.world.longname = $long |
    .server.world.shortname = $short |
    .server.world.localaddress = $local |
    .server.world.address = $public |
    .server.world.telnet.enabled = $telnet |
    .server.zones.ports.low = $plow |
    .server.zones.ports.high = $phigh
  ' /home/eqemu/server/eqemu_config.json >"$tmp"
cat "$tmp" >/home/eqemu/server/eqemu_config.json
rm -f "$tmp"

# ---- Quests and Maps ----
if [ ! -d "/home/eqemu/server/quests/.git" ]; then
  git clone ${QUESTS_BRANCH:+--branch "$QUESTS_BRANCH"} "$QUESTS_REPO" /home/eqemu/server/quests
elif [ "${AUTO_PULL:-false}" = "true" ]; then
  cd /home/eqemu/server/quests && git pull
fi

if [ ! -d "/home/eqemu/server/maps/.git" ]; then
  git clone ${MAPS_BRANCH:+--branch "$MAPS_BRANCH"} "$MAPS_REPO" /home/eqemu/server/maps
elif [ "${AUTO_PULL:-false}" = "true" ]; then
  cd /home/eqemu/server/maps && git pull
fi

# ---- Build ----
# Rebuild when the source commit differs from the last successful build, when
# there's no build yet, or when FORCE_RECOMPILE=true. The marker is written only
# after ninja succeeds, so an interrupted or failed build runs again next start.
marker=/home/eqemu/build/.built_commit
build_id="$(git -C /home/eqemu/source rev-parse HEAD) ${CMAKE_BUILD_TYPE:-RelWithDebInfo} ${CMAKE_EXTRA_ARGS:-}"
if [ "${FORCE_RECOMPILE:-false}" = "true" ] ||
  [ ! -f /home/eqemu/build/bin/world ] ||
  [ "$(cat "$marker" 2>/dev/null)" != "$build_id" ]; then
  echo "Building server ($build_id)"
  mkdir -p /home/eqemu/build
  cd /home/eqemu/build
  cmake -GNinja \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-RelWithDebInfo}" \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DEQEMU_BUILD_LOGIN=ON \
    -DEQEMU_BUILD_LUA=ON \
    -DEQEMU_BUILD_PERL=ON \
    -DEQEMU_BUILD_LOGGING=ON ${CMAKE_EXTRA_ARGS:-} /home/eqemu/source
  ninja -v
  echo "$build_id" >"$marker"
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
  echo "Applying default zone set..."
  $MYSQL "$DB_NAME" </home/eqemu/default_zones.sql
  echo "Resetting player table IDs to start at 1..."
  for t in $(grep -hoE '^CREATE TABLE `[^`]+`' "$tmp"/player_tables*.sql "$tmp"/login_tables*.sql | cut -d'`' -f2); do
    $MYSQL "$DB_NAME" -e "ALTER TABLE \`$t\` AUTO_INCREMENT = 1"
  done
  rm -rf "$tmp"
else
  echo "$DB_NAME already has $tables tables, skipping load."
fi
has_ls_settings=$($MYSQL -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name='tblloginserversettings'")
if [ "$has_ls_settings" -eq 0 ]; then
  echo "Loading tblloginserversettings..."
  $MYSQL "$DB_NAME" </home/eqemu/source/loginserver/login_util/tblloginserversettings.sql
fi
list_types=$($MYSQL -N -e "SELECT COUNT(*) FROM \`$DB_NAME\`.tblServerListType" 2>/dev/null || echo 0)
if [ "$list_types" -eq 0 ]; then
  echo "Loading tblServerListType..."
  $MYSQL "$DB_NAME" </home/eqemu/source/loginserver/login_util/tblServerListType.sql
fi

# ---- Required updates missing from the database dump ----
# The dump predates these. Each is applied only if its change is missing,
# so this does nothing once the dump includes them.
required=/home/eqemu/source/utils/sql/git/required
has_column() {
  [ "$($MYSQL -N -e "SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$1' AND COLUMN_NAME='$2'")" -gt 0 ]
}
has_index() {
  [ "$($MYSQL -N -e "SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$1' AND INDEX_NAME='$2'")" -gt 0 ]
}

if ! has_column player_event_logs etl_table_id; then
  echo "Applying 2025_05_26_Add_Detail_Player_Event_Logging.sql..."
  $MYSQL "$DB_NAME" <"$required/2025_05_26_Add_Detail_Player_Event_Logging.sql"
fi
if ! has_index player_event_logs idx_event_type_char_id; then
  echo "Applying 2025_07_05_player_event_logs_table.sql..."
  $MYSQL "$DB_NAME" <"$required/2025_07_05_player_event_logs_table.sql"
fi

cd /home/eqemu/server
./shared_memory
