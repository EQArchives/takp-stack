#!/bin/bash
set -e

# Do app work that doesn't require root permissions
if [ ! -d "/home/eqemu/source/.git" ]; then
    git clone https://github.com/EQArchives/Server.git /home/eqemu/source
else
    if [ "${AUTO_PULL:-true}" = "true" ]; then
		cd /home/eqemu/source && git pull
	fi
fi

if [ ! -f "/home/eqemu/server/login.json" ]; then
    cp /home/eqemu/source/loginserver/login_util/login.json /home/eqemu/server/login.json
fi

if [ ! -f "/home/eqemu/server/eqemu_config.json" ]; then
    cp /home/eqemu/source/utils/defaults/eqemu_config.json /home/eqemu/server/eqemu_config.json
fi

if [ ! -d "/home/eqemu/server/quests/.git" ]; then
   git clone https://github.com/EQArchives/quests.git /home/eqemu/server/quests
else
	if [ "${AUTO_PULL:-true}" = "true" ]; then
		cd /home/eqemu/server/quests && git pull
	fi
fi

if [ ! -d "/home/eqemu/server/maps/.git" ]; then
   git clone https://github.com/EQMacEmu/Maps.git /home/eqemu/server/maps
else
    if [ "${AUTO_PULL:-true}" = "true" ]; then
		cd /home/eqemu/server/maps && git pull
	fi
fi

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

mkdir -p /home/eqemu/server/shared/
mkdir -p /home/eqemu/server/logs/

mkdir -p /home/eqemu/server/opcodes/
ln -sf /home/eqemu/source/utils/patches/chat_opcodes.conf /home/eqemu/server/opcodes/chat_opcodes.conf
ln -sf /home/eqemu/source/utils/patches/opcodes.conf /home/eqemu/server/opcodes/opcodes.conf
ln -sf /home/eqemu/source/utils/patches/patch_Mac.conf /home/eqemu/server/opcodes/patch_Mac.conf

ln -sf /home/eqemu/source/utils/patches/patch_Mac.conf /home/eqemu/server/patch_Mac.conf
ln -sf /home/eqemu/build/bin/eqlaunch /home/eqemu/server/eqlaunch
ln -sf /home/eqemu/build/bin/libcommon.a /home/eqemu/server/libcommon.a
ln -sf /home/eqemu/build/bin/libluabind.a /home/eqemu/server/libluabind.a
ln -sf /home/eqemu/build/bin/loginserver /home/eqemu/server/loginserver
ln -sf /home/eqemu/build/bin/queryserv /home/eqemu/server/queryserv
ln -sf /home/eqemu/build/bin/shared_memory /home/eqemu/server/shared_memory
ln -sf /home/eqemu/build/bin/ucs /home/eqemu/server/ucs
ln -sf /home/eqemu/build/bin/world /home/eqemu/server/world
ln -sf /home/eqemu/build/bin/zone /home/eqemu/server/zone

exec tail -f /dev/null

