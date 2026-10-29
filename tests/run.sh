#!/bin/bash
# Έλεγχος δικαιωμάτων της βάσης σε τοπική PostgreSQL.
# Χρήση: PGHOST=... PGPORT=... PGUSER=... ./tests/run.sh
set -e
D=$(cd "$(dirname "$0")" && pwd)
P="psql -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "drop database if exists mg_test" -c "create database mg_test" >/dev/null
$P -d mg_test -f "$D/00_supabase_stub.sql" >/dev/null
for f in "$D"/../supabase/migrations/*.sql; do $P -d mg_test -f "$f" >/dev/null; done
OUT=$($P -d mg_test -f "$D/10_permissions.sql" 2>&1) || { echo "$OUT" | tail -20; exit 1; }
echo "$OUT" | grep -E "NOTICE:  OK" | sed 's/.*NOTICE:  /  /'
echo "$OUT" | grep -q "ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ" && echo "✓ ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ" || { echo "✗ ΑΠΟΤΥΧΙΑ"; exit 1; }
