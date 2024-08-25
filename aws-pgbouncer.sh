#!/bin/bash

# This script is designed to control a pgbouncer instance with AWS Secrets Manager credentials for a PostgreSQL database.

AWS_SECRET_NAME=${AWS_SECRET_NAME:-"rds-db-credentials"}
AWS_REGION=${AWS_REGION:-"eu-west-3"}
DB_NAME=${DB_NAME:-"postgres"}
DB_HOST=${DB_HOST:-"localhost"}
DB_PORT=${DB_PORT:-"5432"}
PGBOUNCER_LISTEN_PORT=${PGBOUNCER_LISTEN_PORT:-"5432"}
PGBOUNCER_LISTEN_ADDR=${PGBOUNCER_LISTEN_ADDR:-"*"}

SECRET_CHECK_INTERVAL=${SECRET_CHECK_INTERVAL:-"3600"} # 1 hour by default (⚠️ don't set this too low, it will spam AWS Secrets Manager and cost you money)

AWS_SECRET_BODY=

write_pgbouncer_ini() {
    if [ ! -f /tmp/pgbouncer-aws-secret.json ]; then
        echo "No secret file found. Exiting..."
        exit 1
    fi
    local USERNAME=$(cat /tmp/pgbouncer-aws-secret.json | jq -r '.username')
    local PASSWORD=$(cat /tmp/pgbouncer-aws-secret.json | jq -r '.password')
    cat <<EOF > /etc/pgbouncer/pgbouncer.ini
[databases]
${DB_NAME} = host=${DB_HOST} port=${DB_PORT} dbname=${DB_NAME} user=${USERNAME} password=${PASSWORD}

[pgbouncer]
listen_port = ${PGBOUNCER_LISTEN_PORT}
listen_addr = ${PGBOUNCER_LISTEN_ADDR}
auth_type = any
admin_users = app_admin
pool_mode = transaction
max_client_conn = 100
default_pool_size = 20
server_tls_sslmode = require
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid
min_pool_size = 0
reserve_pool_size = 0
# some Java libraries set this extra_float_digits implicitly: https://github.com/Athou/commafeed/issues/559
ignore_startup_parameters = extra_float_digits
EOF
}

get_secret_version() {
    AWS_SECRET_BODY=$(aws secretsmanager get-secret-value --secret-id ${AWS_SECRET_NAME} --region ${AWS_REGION})
    echo ${AWS_SECRET_BODY} | jq -r '.VersionId'
    echo ${AWS_SECRET_BODY} | jq -r '.SecretString' > /tmp/pgbouncer-aws-secret.json
}

PGBOUNCER_PID=
MONITOR_PID=

monitor_pgbouncer() {
    PARENT_PID=$1
    PGBOUNCER_PID=$2
    echo "Monitoring pgbouncer... (parent PID: ${PARENT_PID}, pgbouncer PID: ${PGBOUNCER_PID})"
    trap "exit 0" SIGTERM SIGINT
    while true; do
        if ! is_pgbouncer_running; then
            echo "pgbouncer is not running. Exiting..."
            kill -s 2 ${PARENT_PID}
            exit 1
        fi
        sleep 1 &
        wait $!
    done
}

is_pgbouncer_running() {
    if [ -n "${PGBOUNCER_PID}" ]; then
        if ps -p ${PGBOUNCER_PID} > /dev/null; then
            return 0
        fi
    fi
    return 1
}

start_pgbouncer() {
    if is_pgbouncer_running; then
        echo "Reloading pgbouncer..."
        pkill -HUP pgbouncer
    else
        echo "Starting pgbouncer..."
        pgbouncer -R /etc/pgbouncer/pgbouncer.ini &
        PGBOUNCER_PID=$!
        echo "pgbouncer started with PID ${PGBOUNCER_PID}"
        monitor_pgbouncer $$ $PGBOUNCER_PID &
        MONITOR_PID=$!
    fi
}

shut_down() {
    MUST_STOP=true
    if ps -p ${MONITOR_PID} > /dev/null; then
        echo "Stopping monitor..."
        kill -s 2 ${MONITOR_PID} || true
    fi
    if ps -p ${PGBOUNCER_PID} > /dev/null; then
        echo "Stopping pgbouncer..."
        kill -s 2 ${PGBOUNCER_PID} || true
        wait ${PGBOUNCER_PID} > /dev/null 2>&1 || true
    fi
    exit 0
}

force_reload() {
    echo "Forcing reload... (current: ${SECRET_VERSION})"
    SECRET_VERSION=$(get_secret_version)
    echo "New version: ${SECRET_VERSION}"
    write_pgbouncer_ini
    start_pgbouncer
}

MUST_STOP=false
trap shut_down SIGTERM SIGINT
trap force_reload SIGUSR1

SECRET_VERSION=
while ! ${MUST_STOP}; do
    echo "Checking for new secret version... (current: ${SECRET_VERSION})"
    if [ "${SECRET_VERSION}" != "$(get_secret_version)" ]; then
        echo "New secret version detected. Updating pgbouncer configuration..."
        write_pgbouncer_ini
        start_pgbouncer
        SECRET_VERSION=$(get_secret_version)
    fi
    echo "Waiting for the next secret version... (interval: ${SECRET_CHECK_INTERVAL}, current: ${SECRET_VERSION})"
    sleep ${SECRET_CHECK_INTERVAL} &
    wait $!
done
