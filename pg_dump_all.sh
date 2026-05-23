#!/usr/bin/env bash
# pg_dump_all.sh — Dump all PostgreSQL databases to individual files.
#
# Required environment variables:
#   PGHOST      — PostgreSQL host (default: localhost)
#   PGPORT      — PostgreSQL port (default: 5432)
#   PGUSER      — PostgreSQL superuser
#   PGPASSWORD  — PostgreSQL password
#
# Optional environment variables:
#   BACKUP_DIR  — Directory to write dumps into (default: ./backups)
#   DUMP_FORMAT — pg_dump format: plain|custom|directory|tar (default: custom)

set -euo pipefail

# ---------------------------------------------------------------------------
# Validate required credentials
# ---------------------------------------------------------------------------
: "${PGUSER:?Environment variable PGUSER is required}"
: "${PGPASSWORD:?Environment variable PGPASSWORD is required}"

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGPASSWORD  # makes it available to child processes (pg_dump / psql)

BACKUP_DIR="${BACKUP_DIR:-./backups}"
DUMP_FORMAT="${DUMP_FORMAT:-custom}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
TARGET_DIR="${BACKUP_DIR}/${TIMESTAMP}"

mkdir -p "${TARGET_DIR}"

echo "==> Backup directory : ${TARGET_DIR}"
echo "==> Host             : ${PGHOST}:${PGPORT}"
echo "==> User             : ${PGUSER}"
echo "==> Format           : ${DUMP_FORMAT}"
echo ""

# ---------------------------------------------------------------------------
# Fetch list of databases (exclude templates)
# ---------------------------------------------------------------------------
DATABASES="$(psql \
  --host="${PGHOST}" \
  --port="${PGPORT}" \
  --username="${PGUSER}" \
  --no-password \
  --tuples-only \
  --no-align \
  --command="SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;")"

if [[ -z "${DATABASES}" ]]; then
  echo "ERROR: No databases found or connection failed." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Determine file extension based on format
# ---------------------------------------------------------------------------
case "${DUMP_FORMAT}" in
  plain)     EXT="sql"  ;;
  custom)    EXT="dump" ;;
  directory) EXT="dir"  ;;
  tar)       EXT="tar"  ;;
  *)
    echo "ERROR: Unknown DUMP_FORMAT '${DUMP_FORMAT}'. Use plain|custom|directory|tar." >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Dump each database
# ---------------------------------------------------------------------------
SUCCESS=0
FAILURE=0

while IFS= read -r DB; do
  [[ -z "${DB}" ]] && continue

  OUTFILE="${TARGET_DIR}/${DB}.${EXT}"

  printf "  Dumping %-40s ... " "${DB}"

  DUMP_ARGS=(
    --host="${PGHOST}"
    --port="${PGPORT}"
    --username="${PGUSER}"
    --no-password
    --format="${DUMP_FORMAT}"
    --blobs
    --verbose
  )

  # For directory format, --file is the target directory; otherwise a file.
  if [[ "${DUMP_FORMAT}" == "directory" ]]; then
    DUMP_ARGS+=(--file="${OUTFILE}")
  else
    DUMP_ARGS+=(--file="${OUTFILE}")
  fi

  DUMP_ARGS+=("${DB}")

  if pg_dump "${DUMP_ARGS[@]}" 2>>"${TARGET_DIR}/${DB}.log"; then
    echo "OK"
    (( SUCCESS++ )) || true
  else
    echo "FAILED (see ${TARGET_DIR}/${DB}.log)"
    (( FAILURE++ )) || true
  fi
done <<< "${DATABASES}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==> Done. ${SUCCESS} succeeded, ${FAILURE} failed."
echo "==> Dumps written to: ${TARGET_DIR}"

[[ "${FAILURE}" -eq 0 ]]
