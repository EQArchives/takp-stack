#!/bin/bash
# Start the login server once world is up and the enabled zones have booted,
# so players can't log in before there's anywhere to go.
# Gives up waiting after 120 seconds and starts anyway.

deadline=120

echo "loginserver: waiting for world..."
until ss -ltn | grep -q ':9001 ' || ((SECONDS >= deadline)); do sleep 1; done

export MYSQL_PWD="$MARIADB_PASSWORD"
expected=$(mysql --skip-ssl -h mariadb -u "$MARIADB_USER" -N -e \
  "SELECT COUNT(*) FROM launcher_zones WHERE enabled = 1" "$MARIADB_DATABASE")
expected=${expected:-0}

echo "loginserver: waiting for $expected zones..."
until (($(ss -ulpn | grep -c '"zone"') >= expected)) || ((SECONDS >= deadline)); do
  sleep 1
done

echo "loginserver: $(ss -ulpn | grep -c '"zone"') of $expected zones up after ${SECONDS}s, starting"
exec /home/eqemu/server/loginserver
