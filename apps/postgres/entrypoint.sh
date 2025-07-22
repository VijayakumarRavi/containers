#!/bin/bash
set -euo pipefail

# Function to log messages
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [PGBACKREST-ENTRYPOINT] $1" >&2
}

log_message "Starting PostgreSQL with pgbackrest backup support..."

if [ "$1" != "postgres" ]; then
    log_message "Not starting PostgreSQL server, passing through to original entrypoint..."
    exec docker-entrypoint.sh "$@"
fi


if [ ! -f /etc/pgbackrest/pgbackrest.conf ]; then
    log_message "Creating pgbackrest configuration file..."
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

if [ ! -f /etc/pgbackrest/pgbackrest.conf ]; then
    log_message "Creating supercronic cron job configuration file..."
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

log_message "Setting up supercronic for cron job management..."
gosu postgres supercronic -debug -inotify /cronjob > /var/log/pgbackrest/supercronic.log 2>&1 &

log_message "Starting PostgreSQL with pgbackrest archiving enabled..."
shift
# PostgreSQL configuration arguments
postgres_args=(
    "-c" "archive_mode=on"
    "-c" "archive_command=pgbackrest --stanza=production archive-push %p"
    "-c" "archive_timeout=300"
    "-c" "wal_level=replica"
    "-c" "max_wal_senders=10"
    "-c" "wal_keep_size=1GB"
    "-c" "wal_compression=on"
    "-c" "checkpoint_completion_target=0.7"
    "-c" "checkpoint_timeout=15min"
    "-c" "max_wal_size=2GB"
    "-c" "min_wal_size=1GB"
    "-c" "ssl=on"
    "-c" "ssl_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem"
    "-c" "ssl_key_file=/etc/ssl/private/ssl-cert-snakeoil.key"
    "$@"
)

log_message "Setting permissions for pgbackrest directories..."
chown -R postgres:postgres /var/lib/postgresql/data
chown -R postgres:postgres /var/lib/pgbackrest
chown -R postgres:postgres /var/log/pgbackrest
chown -R postgres:postgres /etc/pgbackrest
chown -R postgres:postgres /tmp/pgbackrest

initialize_stanza() {
    log_message "Initializing pgbackrest stanza..."
    if gosu postgres pgbackrest --stanza=production stanza-create --no-online --log-level-console=info; then
        log_message "Stanza initialized successfully"
        return 0
    else
        log_message "❌ Failed to initialize pgbackrest stanza"
        return 1
    fi
}

# Function to check for existing backups
check_existing_backups() {
    local backup_count
    backup_count=$(gosu postgres pgbackrest --stanza=production info --output=json | jq '.[] | select(.name=="production") | .backup | length')
    if [ -n "$backup_count" ] && [ "$backup_count" -ge 0 ]; then
        log_message "Found $backup_count valid backup(s)"
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
    log_message "Restoring latest pgbackrest backup..."
    if [ -d /var/lib/postgresql/data ] && [ -n "$(ls -A /var/lib/postgresql/data)" ]; then
        log_message "Cleaning existing data directory..."
        rm -rf /var/lib/postgresql/data/*
    fi
    if gosu postgres pgbackrest --stanza=production restore --log-level-console=info; then
        log_message "Latest backup restored successfully"
        return 0
    else
        log_message "❌ Failed to restore latest backup"
        return 1
    fi
}

# Function to create initial backup
create_initial_backup() {
    log_message "Creating initial pgbackrest backup..."
    if gosu postgres pgbackrest --stanza=production --type=full --log-level-console=info backup; then
        log_message "Initial backup created successfully"
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
    log_message "PostgreSQL data directory not initialized. Checking for backups to restore..."
    EXISTING_BACKUPS=$(check_existing_backups)
    if [ "$EXISTING_BACKUPS" -gt 0 ]; then
        log_message "Found $EXISTING_BACKUPS existing backup(s), restoring latest backup..."
        if ! restore_latest_backup; then
            log_message "❌ Restore failed, exiting..."
            exit 1
        fi
    else
        log_message "No existing backups found, running initdb..."
        docker-ensure-initdb.sh
        initialize_stanza
    fi
else
    log_message "✅ PostgreSQL data directory already initialized."
    initialize_stanza
fi

# Start PostgreSQL
docker-entrypoint.sh postgres "${postgres_args[@]}" &
POSTGRES_PID=$!

(
    log_message "Waiting for PostgreSQL to be ready..."
    if check_postgres_ready; then
        log_message "PostgreSQL is ready!"
        # Only create a new backup if no data was restored
        EXISTING_BACKUPS=$(check_existing_backups)
        if [ "$EXISTING_BACKUPS" -eq 0 ]; then
            log_message "No existing backups found or new database initialized, creating initial backup..."
            create_initial_backup
        else
            log_message "✅ Backup restoration completed"
        fi
    else
        log_message "❌ PostgreSQL failed to become ready within 2 minutes"
        log_message "Container will continue running, but backup operations were skipped"
    fi
) &

wait $POSTGRES_PID
