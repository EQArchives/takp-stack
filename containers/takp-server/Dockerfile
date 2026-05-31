FROM debian:13-slim

LABEL maintainer="Nazwadi <nazwadi@pm.me>"

ENV DEBIAN_FRONTEND=noninteractive

# Add a non-root user to prevent files being created with root permissions on host machine
ARG PUID=1000
ENV PUID=${PUID}
ARG PGID=1000
ENV PGID=${PGID}

ENV TZ=US/Eastern

ENV CC=/usr/bin/clang
ENV CXX=/usr/bin/clang++

RUN groupadd -g ${PGID} eqemu && \
    useradd -u ${PUID} -g eqemu -m eqemu -G eqemu && \
    usermod -p "*" eqemu

RUN apt-get update && apt-get install -yqq \
	bash \
	openssh-server \
	git \
	gcc \
	g++ \
	cpp \
	unzip \
	make \
	cmake \
    libperl-dev \
    uuid-dev \
    default-libmysqlclient-dev \
    libmariadbd-dev \
    libmysql++-dev \
    mariadb-server \
    mariadb-client \
    libboost-all-dev \
    liblua5.2-0 \
    liblua5.2-dev \
    libluabind-dev \
    lua5.2 \
    build-essential \
    libssl-dev \
    openssl \
    libcurl4-openssl-dev \
    libio-stringy-perl \
    valgrind \
    ruby \
    ruby-dev \
    universal-ctags \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/{source,build,server} && \
    chown -R eqemu:eqemu /opt/{source,build,server} && \
    git clone https://github.com/EQArchives/Server.git /opt/source

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
