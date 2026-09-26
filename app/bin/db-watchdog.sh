#!/usr/bin/env bash
# Runs on both VMs (systemd: db-watchdog.service).
#   local standby, peer primary unreachable for FAILOVER_AFTER_SECONDS -> promote local standby
#   local primary, peer is also primary on a newer timeline             -> restart local db, which
#                                                                          rejoins as a standby
set -uo pipefail
set -a
source /opt/app/.env
set +a

INTERVAL=5
THRESHOLD=${FAILOVER_AFTER_SECONDS:-60}
PEER_CONNINFO="host=$PEER_IP port=5432 user=replicator dbname=postgres connect_timeout=3"
TIMELINE_SQL="select ('x' || substr(pg_walfile_name(pg_current_wal_lsn()), 1, 8))::bit(32)::int"

log() { logger -t db-watchdog "$*"; echo "$*"; }
local_sql() { docker exec db psql -U postgres -tAqc "$1" 2>/dev/null; }
peer_sql() { docker exec -e PGPASSWORD="$REPLICATION_PASSWORD" db psql "$PEER_CONNINFO" -tAqc "$1" 2>/dev/null; }

down=0
while sleep "$INTERVAL"; do
  local_standby=$(local_sql 'select pg_is_in_recovery()')
  peer_standby=$(peer_sql 'select pg_is_in_recovery()')

  case "$local_standby" in
    t)
      if [ "$peer_standby" = f ]; then
        down=0
        continue
      fi
      down=$((down + INTERVAL))
      log "no primary reachable at $PEER_IP for ${down}s (threshold ${THRESHOLD}s)"
      if [ "$down" -ge "$THRESHOLD" ]; then
        log "promoting local standby to primary"
        local_sql 'select pg_promote()'
        down=0
      fi
      ;;
    f)
      down=0
      if [ "$peer_standby" = f ]; then
        mine=$(local_sql "$TIMELINE_SQL")
        theirs=$(peer_sql "$TIMELINE_SQL")
        if [ -n "$mine" ] && [ -n "$theirs" ] && [ "$theirs" -gt "$mine" ]; then
          log "peer is primary on newer timeline $theirs (local $mine); restarting local db to rejoin as standby"
          docker restart db
        fi
      fi
      ;;
    *)
      down=0 # local db not up yet (starting or cloning)
      ;;
  esac
done
