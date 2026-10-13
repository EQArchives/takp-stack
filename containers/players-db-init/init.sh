#!/bin/sh
# Creates the Players database and MariaDB user, and sets its grants.
# Safe to run on every start: each statement is a no-op once applied.
set -e

: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD is not set}"
: "${MARIADB_DATABASE:?MARIADB_DATABASE is not set}"
: "${PLAYERS_DB_PASSWORD:?PLAYERS_DB_PASSWORD is not set. Set it in .env to use the players profile.}"
: "${PLAYERS_SECRET_KEY:?PLAYERS_SECRET_KEY is not set. Set it in .env to use the players profile.}"

DB="${PLAYERS_DB_NAME:-players}"
USER="${PLAYERS_DB_USER:-players}"
GAME_DB="$MARIADB_DATABASE"
export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"
MYSQL="mysql -h mariadb -u root -P ${MARIADB_PORT:-3306}"

echo "Waiting for MariaDB..."
for i in $(seq 1 30); do
  $MYSQL -e "SELECT 1" >/dev/null 2>&1 && break
  if [ "$i" -eq 30 ]; then
    echo "Can't log in to MariaDB as root. Check MARIADB_ROOT_PASSWORD." >&2
    exit 1
  fi
  sleep 2
done

echo "Waiting for the game database to be loaded..."
for i in $(seq 1 120); do
  n=$($MYSQL -N -e "SELECT COUNT(*) FROM information_schema.TABLES
    WHERE TABLE_SCHEMA='$GAME_DB'
    AND TABLE_NAME IN ('tblLoginServerAccounts', 'account', 'character_data')")
  [ "$n" -eq 3 ] && break
  if [ "$i" -eq 120 ]; then
    echo "Game database '$GAME_DB' isn't loaded after 20 minutes. Start takp-server first." >&2
    exit 1
  fi
  sleep 10
done

# Double any single quotes so the password can't break out of the SQL string
PASS=$(printf '%s' "$PLAYERS_DB_PASSWORD" | sed "s/'/''/g")

echo "Setting up database '$DB' and user '$USER'..."
$MYSQL <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB\` CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '$USER'@'%' IDENTIFIED BY '$PASS';
ALTER USER '$USER'@'%' IDENTIFIED BY '$PASS';
GRANT ALL ON \`$DB\`.* TO '$USER'@'%';
GRANT SELECT ON \`$GAME_DB\`.* TO '$USER'@'%';
GRANT INSERT, UPDATE ON \`$GAME_DB\`.tblLoginServerAccounts TO '$USER'@'%';
GRANT UPDATE ON \`$GAME_DB\`.account TO '$USER'@'%';
GRANT UPDATE ON \`$GAME_DB\`.character_data TO '$USER'@'%';
SQL
echo "Done."
