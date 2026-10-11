#!/bin/bash
set -e

# Write authorized keys for eqemu from env var
if [ -n "${SSH_AUTHORIZED_KEYS}" ]; then
  mkdir -p /home/eqemu/.ssh
  printf '%s\n' "${SSH_AUTHORIZED_KEYS}" >/home/eqemu/.ssh/authorized_keys
  chmod 700 /home/eqemu/.ssh
  chmod 600 /home/eqemu/.ssh/authorized_keys
  chown -R eqemu:eqemu /home/eqemu/.ssh
fi

# Ensure auth.log exists before rsyslog/sshd start (fail2ban watches this)
touch /var/log/auth.log
rsyslogd
/usr/sbin/sshd

chown -R eqemu:eqemu /home/eqemu/source /home/eqemu/server /home/eqemu/build /home/eqemu/.ccache
exec su -s /bin/bash eqemu /home/eqemu/setup.sh
