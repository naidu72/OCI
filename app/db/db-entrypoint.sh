#!/usr/bin/env bash
# Decides whether this node starts as the primary or as a streaming standby of its peer,
# then hands over to the stock postgres entrypoint.
#
#   empty data dir, designated primary, no peer DB running -> initialise a new primary
#   empty data dir otherwise                                 -> wait for the peer primary, clone it
#   old primary data, but the peer was promoted since        -> set old data aside, clone the peer
set -euo pipefail

export PGDATA=/var/lib/postgresql/data/pgdata
export PGCONNECT_TIMEOUT=3
PEER_CONNINFO="host=$PEER_IP port=5432 user=replicator password=$REPLICATION_PASSWORD"

log() { echo "[db-entrypoint] $*"; }

peer_sql() { psql "$PEER_CONNINFO dbname=postgres" -tAqc "$1" 2>/dev/null || true; }
peer_is_primary() { [ "$(peer_sql 'select not pg_is_in_recovery()')" = t ]; }
peer_timeline() { peer_sql "select ('x' || substr(pg_walfile_name(pg_current_wal_lsn()), 1, 8))::bit(32)::int"; }
local_timeline() { pg_controldata "$PGDATA" | awk -F: '/Latest checkpoint.s TimeLineID/ {gsub(/ /, "", $2); print $2}'; }

if [ -s "$PGDATA/PG_VERSION" ] && [ ! -f "$PGDATA/standby.signal" ] && peer_is_primary; then
  mine=$(local_timeline)
  theirs=$(peer_timeline)
  if [ -n "$theirs" ] && [ "$theirs" -gt "$mine" ]; then
    stale="${PGDATA}.stale-$(date +%Y%m%d%H%M%S)"
    log "peer $PEER_IP was promoted (timeline $theirs > $mine); moving old data to $stale and rejoining as standby"
    mv "$PGDATA" "$stale"
  fi
fi

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  if [ "$NODE_ROLE" = primary ] && ! pg_isready -q -h "$PEER_IP" -t 3; then
    log "no peer database running; bootstrapping a new primary"
  else
    log "waiting for a primary at $PEER_IP"
    until peer_is_primary; do sleep 5; done
    log "cloning from $PEER_IP"
    rm -rf "$PGDATA"
    until gosu postgres pg_basebackup -d "$PEER_CONNINFO" -D "$PGDATA" -R -X stream -c fast; do
      log "clone failed; retrying in 5s"
      rm -rf "$PGDATA"
      sleep 5
    done
  fi
fi

exec docker-entrypoint.sh postgres \
  -c listen_addresses='*' \
  -c cluster_name="$NODE_NAME" \
  -c wal_level=replica \
  -c max_wal_senders=10 \
  -c wal_keep_size=2GB \
  -c hot_standby=on
