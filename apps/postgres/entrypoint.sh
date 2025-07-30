#!/bin/bash
set -euo pipefail

# Function to log messages
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [PGBACKREST-ENTRYPOINT] $1" >&2
}

log_message "📢 Starting PostgreSQL with pgbackrest backup support..."

if [ "$1" != "postgres" ]; then
    log_message "⚠️ Not starting PostgreSQL server, passing through to original entrypoint..."
    exec docker-entrypoint.sh "$@"
fi

if [ ! -f /etc/pgbackrest/pgbackrest.conf ]; then
    log_message "📢 Creating pgbackrest configuration file..."
    mkdir -p /var/lib/pgbackrest
    chown postgres:postgres /var/lib/pgbackrest
    cat <<EOF > /etc/pgbackrest/pgbackrest.conf
[production]
pg1-path=/var/lib/postgresql/data
pg1-port=5432
pg1-user=postgres
pg1-database=postgres


[global]
start-fast=y
archive-async=y
archive-push-queue-max=5GiB
compress-type=bz2
compress-level=9

# Local repository configuration
repo1-bundle=y
repo1-block=y
repo1-path=/var/lib/pgbackrest
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=some-secret-passphrase
repo1-retention-archive=2
repo1-retention-full=7
repo1-retention-full-type=time
EOF
fi

log_message "📢 Creating postgresql configuration file..."
mkdir -p /var/lib/postgresql/data
chown postgres:postgres /var/lib/postgresql/data
cat <<EOF > /var/lib/postgresql/data/postgresql.conf
listen_addresses = '*'
port = 5432
max_connections = 100
unix_socket_directories = '/var/run/postgresql'
shared_buffers = 128MB

archive_mode = on
archive_command = 'pgbackrest --stanza=production archive-push %p'
archive_timeout = 300

wal_level = replica
max_wal_senders = 10
wal_keep_size = 1GB
wal_compression = on
checkpoint_completion_target = 0.7
checkpoint_timeout = 15min
max_wal_size = 2GB
min_wal_size = 1GB

ssl=on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'

shared_preload_libraries = vchord

logging_collector = on
log_directory = '/var/log/pgbackrest/postgres'
log_filename = 'postgresql-%Y-%m-%d.log'
log_file_mode = 0777
log_rotation_age = 1d
log_truncate_on_rotation = on
EOF

if [ ! -f /etc/pgbackrest/pgbackrest.conf ]; then
    log_message "📢 Creating supercronic cron job configuration file..."
    cat <<EOF > /cronjob
# Pgbackrest repo1
# Full backup: Sunday at 01:00
0 1 * * 0 pgbackrest --stanza=production backup --repo=1 --type=full
# Differential backup: Monday-Saturday at 01:00
0 1 * * 1-6 pgbackrest --stanza=production backup --repo=1 --type=diff
# Incremental backup: Every hour except 01:00
0 2-23 * * * pgbackrest --stanza=production backup --repo=1 --type=incr

# Backup status check
0 1 * * * pgbackrest --stanza=production info --repo=1 >> /var/log/pgbackrest/repo1-backup-status.log 2>&1
EOF
fi

log_message "📢 Setting up supercronic for cron job management..."
gosu postgres supercronic -debug -inotify /cronjob > /var/log/pgbackrest/supercronic.log 2>&1 &

log_message "📢 Starting PostgreSQL with pgbackrest archiving enabled..."
shift

log_message "📢 Setting permissions for pgbackrest directories..."
chown -R postgres:postgres /var/lib/postgresql/data
chown -R postgres:postgres /var/lib/pgbackrest
chown -R postgres:postgres /var/log/pgbackrest
chown -R postgres:postgres /etc/pgbackrest
chown -R postgres:postgres /tmp/pgbackrest

initialize_stanza() {
    log_message "📢 Initializing pgbackrest stanza..."
    gosu postgres pg_ctl start -o "-p 5432 -k /var/run/postgresql" -D /var/lib/postgresql/data

    if gosu postgres pgbackrest --stanza=production --log-level-console=info stanza-create; then
        log_message "✅ Pgbackrest stanza initialized successfully"
        gosu postgres pg_ctl restart -o "-p 5432 -k /var/run/postgresql" -D /var/lib/postgresql/data
    else
        log_message "❌ Pgbackrest stanza initialization failed, exiting..."
        gosu postgres pg_ctl stop -o "-p 5432 -k /var/run/postgresql" -D /var/lib/postgresql/data
        exit 1
    fi

    log_message "📢 Checking pgbackrest stanza..."
    if gosu postgres pgbackrest --stanza=production --log-level-console=info check; then
        log_message "✅ Pgbackrest stanza check passed"
        gosu postgres pg_ctl stop -o "-p 5432 -k /var/run/postgresql" -D /var/lib/postgresql/data
    else
        log_message "❌ Pgbackrest stanza check failed, exiting..."
        gosu postgres pg_ctl stop -o "-p 5432 -k /var/run/postgresql" -D /var/lib/postgresql/data
        exit 1
    fi
}

# Function to check for existing backups
check_existing_backups() {
    local backup_count
    backup_count=$(gosu postgres pgbackrest --stanza=production info --output=json | jq '.[] | select(.name=="production") | .backup | length')
    if [ -n "$backup_count" ] && [ "$backup_count" -ge 0 ]; then
        log_message "📢 Found $backup_count valid backup(s)"
        echo "$backup_count"
        return 0
    else
        log_message "❌ Failed to check existing backups"
        echo 0
        return 1
    fi
}

# Function to restore the latest backup
restore_latest_backup() {
    log_message "📢 Restoring latest pgbackrest backup..."
    if [ -d /var/lib/postgresql/data ] && [ -n "$(ls -A /var/lib/postgresql/data)" ]; then
        log_message "⚠️ Cleaning existing data directory..."
        rm -rf /var/lib/postgresql/data/*
    fi
    if gosu postgres pgbackrest --stanza=production --log-level-console=info restore; then
        log_message "✅ Latest backup restored successfully"
    else
        log_message "❌ Failed to restore latest backup, exiting..."
        exit 1
    fi
}

# Function to create initial backup
create_initial_backup() {
    log_message "📢 Creating initial pgbackrest backup..."
    if gosu postgres pgbackrest --stanza=production --type=full --log-level-console=info backup; then
        log_message "✅ Initial backup created successfully"
        return 0
    else
        log_message "❌ Failed to create initial backup"
        return 1
    fi
}

# Function to check if PostgreSQL is ready
check_postgres_ready() {
    for i in {1..60}; do
        if pg_isready -U "${POSTGRES_USER:-postgres}" -h /var/run/postgresql >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

# Initialize database if pg_control doesn't exist
if [ ! -f /var/lib/postgresql/data/global/pg_control ]; then
    log_message "📢 PostgreSQL data directory not initialized. Checking for backups to restore..."
    EXISTING_BACKUPS=$(check_existing_backups)
    if [ "$EXISTING_BACKUPS" -gt 0 ]; then
        restore_latest_backup
    else
        log_message "📢 No existing backups found, running initdb..."
        docker-ensure-initdb.sh
        initialize_stanza
    fi
else
    log_message "✅ PostgreSQL data directory already initialized."
    initialize_stanza
fi

# Start PostgreSQL
docker-entrypoint.sh postgres "$@" &
POSTGRES_PID=$!

(
    log_message "📢 Waiting for PostgreSQL to be ready..."
    if check_postgres_ready; then
        log_message "✅ PostgreSQL is ready!"
        # Only create a new backup if no data was restored
        EXISTING_BACKUPS=$(check_existing_backups)
        if [ "$EXISTING_BACKUPS" -eq 0 ]; then
            log_message "📢 No existing backups found or new database initialized, creating initial backup..."
            create_initial_backup
        fi
    else
        log_message "❌ PostgreSQL failed to become ready within 2 minutes"
        log_message "❌ Container will continue running, but backup operations were skipped"
    fi
) &

wait $POSTGRES_PID
