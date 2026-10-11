FROM debian:13-slim

LABEL maintainer="Nazwadi <nazwadi@pm.me>"

ENV DEBIAN_FRONTEND=noninteractive

# Add a non-root user to prevent files being created with root permissions on host machine
ARG PUID=1000
ENV PUID=${PUID}
ARG PGID=1000
ENV PGID=${PGID}

ENV CC=/usr/bin/gcc
ENV CXX=/usr/bin/g++

# /bin/sh doesn't support brace expansion; explicit bash required
RUN groupadd -g ${PGID} eqemu && \
    useradd -u ${PUID} -g eqemu -m eqemu -G eqemu && \
    usermod -p "*" eqemu && \
    bash -c 'mkdir -p /home/eqemu/{source,build,server,.ccache} && chown -R eqemu:eqemu /home/eqemu/{source,build,server,.ccache}'

RUN apt-get update && apt-get install -yqq \
    bash \
    build-essential \
    ccache \
    clang \
    cmake \
    cpp \
    default-libmysqlclient-dev \
    g++ \
    gcc \
    git \
    gosu \
    jq \
    libboost-all-dev \
    libcurl4-openssl-dev \
    libio-stringy-perl \
    liblua5.2-0 \
    liblua5.2-dev \
    libluabind-dev \
    libmariadbd-dev \
    libmysql++-dev \
    libperl-dev \
    libssl-dev \
    lua5.2 \
    make \
    mariadb-client \
    mariadb-server \
    nano \
    ninja-build \
    openssh-server \
    openssl \
    rsyslog \
    ruby \
    ruby-dev \
    supervisor \
    universal-ctags \
    unzip \
    uuid-dev \
    valgrind \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd && \
    ssh-keygen -A && \
    mkdir -p /etc/ssh/sshd_config.d && \
    printf 'PermitRootLogin no\nPasswordAuthentication no\nPubkeyAuthentication yes\n' \
        > /etc/ssh/sshd_config.d/00-hardening.conf && \
    printf 'auth,authpriv.* /var/log/auth.log\n' > /etc/rsyslog.d/50-auth.conf && \
    sed -i '/imklog/d' /etc/rsyslog.conf

COPY --chmod=755 entrypoint.sh /home/eqemu/entrypoint.sh
COPY --chmod=755 setup.sh /home/eqemu/setup.sh
COPY --chmod=644 supervisord.conf /home/eqemu/supervisord.conf
COPY --chmod=644 default_zones.sql /home/eqemu/default_zones.sql
COPY --chmod=755 start-loginserver.sh /home/eqemu/start-loginserver.sh

ENTRYPOINT ["/home/eqemu/entrypoint.sh"]

