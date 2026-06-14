FROM mariadb:10.5.4

LABEL maintainer="Nazwadi <nazwadi@pm.me>"

COPY my.cnf /etc/mysql/conf.d/my.cnf

ARG INNODB_BUFFER_POOL_SIZE="256MB"
ARG MARIADB_PORT=3306

RUN echo "[mysqld]" >> /etc/mysql/conf.d/my.cnf && \
    echo "port = ${MARIADB_PORT}" >> /etc/mysql/conf.d/my.cnf && \
    echo "innodb_buffer_pool_size = ${INNODB_BUFFER_POOL_SIZE}" >> /etc/mysql/conf.d/my.cnf

EXPOSE ${MARIADB_PORT}

