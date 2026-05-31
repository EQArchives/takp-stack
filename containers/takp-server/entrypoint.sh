#!/bin/bash
set -e

if [ ! -d "/opt/source/.git" ]; then
    git clone https://github.com/EQArchives/Server.git /opt/source
else
    cd /opt/source && git pull
fi

if [ ! -d "/opt/server/quests/.git" ]; then
   git clone https://github.com/EQArchives/quests.git /opt/server/quests
else
    cd /opt/server/quests && git pull
fi

if [ ! -d "/opt/server/maps/.git" ]; then
   git clone https://github.com/EQMacEmu/Maps.git /opt/server/maps
else
   cd /opt/server/maps && git pull
fi
