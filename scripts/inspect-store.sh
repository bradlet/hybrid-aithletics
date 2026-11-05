#!/usr/bin/env bash
#
# inspect-store.sh — open the app's SwiftData (SQLite) store in sqlite3.
#
# Locates the store, copies it (+ its -wal/-shm) to a temp dir so the live
# database is never touched, and opens an sqlite3 session with two convenience
# views that un-mangle the Core Data Z-names and decode the nested workout JSON:
#
#     SELECT * FROM exercises;   -- one row per Exercise (planned + completed)
#     SELECT * FROM workouts;    -- one row per *recorded* exercise, decoded
#
# Usage:
#   scripts/inspect-store.sh                 # booted simulator's installed app
#   scripts/inspect-store.sh <file.store>    # a specific store file
#   scripts/inspect-store.sh <dir|.xcappdata># search a folder for default.store
#                                            #   (e.g. a container downloaded from
#                                            #    a physical device via Xcode)
#   scripts/inspect-store.sh -q "SELECT ..." # run one query and exit
#
# Env:
#   BUNDLE_ID   app bundle id (default: bradlet.Hybrid-AIthletics)
#
# See docs/INSPECTING_DATA.md for the full walkthrough.

set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-bradlet.Hybrid-AIthletics}"
QUERY=""
SOURCE=""

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--query) QUERY="${2:-}"; shift 2;;
    -h|--help)  usage 0;;
    -*)         echo "Unknown option: $1" >&2; usage 1;;
    *)          SOURCE="$1"; shift;;
  esac
done

# --- Resolve the store file -------------------------------------------------

resolve_store() {
  # 1) explicit path argument
  if [[ -n "$SOURCE" ]]; then
    if [[ -f "$SOURCE" ]]; then
      echo "$SOURCE"; return
    fi
    if [[ -d "$SOURCE" ]]; then
      local found
      found=$(find "$SOURCE" -name "default.store" -print -quit 2>/dev/null || true)
      [[ -n "$found" ]] && { echo "$found"; return; }
      echo "No default.store found under: $SOURCE" >&2; exit 1
    fi
    echo "Path not found: $SOURCE" >&2; exit 1
  fi

  # 2) booted simulator's installed app
  local container
  container=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data 2>/dev/null || true)
  if [[ -z "$container" ]]; then
    echo "Could not find '$BUNDLE_ID' on a booted simulator." >&2
    echo "Boot a sim and run the app once, or pass a store path / .xcappdata folder." >&2
    echo "Booted devices:" >&2
    xcrun simctl list devices booted >&2 || true
    exit 1
  fi
  echo "$container/Library/Application Support/default.store"
}

STORE="$(resolve_store)"
[[ -f "$STORE" ]] || { echo "Store file does not exist: $STORE" >&2; exit 1; }

# --- Copy to a temp dir (incl. WAL/SHM) so the live store is untouched ------

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
for ext in "" "-wal" "-shm"; do
  [[ -f "${STORE}${ext}" ]] && cp "${STORE}${ext}" "$WORKDIR/default.store${ext}"
done
COPY="$WORKDIR/default.store"

echo "Source store : $STORE" >&2
echo "Working copy : $COPY (read-only snapshot; live data is untouched)" >&2

# --- Convenience views (TEMP, so they vanish with the session) --------------
# 978307200 = seconds between 2001-01-01 (Core Data epoch) and the Unix epoch.

read -r -d '' SETUP <<'SQL' || true
CREATE TEMP VIEW IF NOT EXISTS exercises AS
SELECT Z_PK                                                       AS pk,
       ZNAME                                                      AS name,
       ZTYPE                                                      AS type,
       datetime(ZDATE + 978307200, 'unixepoch', 'localtime')      AS date,
       ZDURATIONSECONDS                                           AS planned_dur_s,
       ZDISTANCEMILES                                             AS planned_mi,
       hex(ZSERIESID)                                             AS series_id,
       ZCOUNTSTOWARDMILEAGE                                       AS counts_toward_mileage,
       (ZWORKOUTDATA IS NOT NULL)                                 AS completed,
       ZNOTES                                                     AS notes
FROM ZEXERCISE;

CREATE TEMP VIEW IF NOT EXISTS workouts AS
SELECT Z_PK                                                          AS exercise_pk,
       ZNAME                                                         AS name,
       ZTYPE                                                         AS type,
       datetime(ZDATE + 978307200, 'unixepoch', 'localtime')         AS date,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.distanceMiles')   AS actual_mi,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.durationSeconds') AS actual_dur_s,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.feeling')         AS feeling,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.perceivedExertion') AS rpe,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.source')          AS source,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.externalID')      AS external_id,
       ZNOTES                                                        AS planned_notes
FROM ZEXERCISE
WHERE ZWORKOUTDATA IS NOT NULL;
SQL

if [[ -n "$QUERY" ]]; then
  sqlite3 -box "$COPY" -cmd "$SETUP" "$QUERY"
else
  echo "Views: 'exercises', 'workouts'. Try: SELECT * FROM workouts ORDER BY date DESC;" >&2
  echo "Quit with .quit" >&2
  sqlite3 -box "$COPY" \
    -cmd ".headers on" \
    -cmd "$SETUP"
fi
