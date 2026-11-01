#!/bin/bash
# Έλεγχοι της βάσης σε τοπική PostgreSQL 16 (κάθε αρχείο σε καθαρή βάση).
# Χρήση: PGHOST=... PGPORT=... PGUSER=... ./tests/run.sh
set -e
D=$(cd "$(dirname "$0")" && pwd)
P="psql -v ON_ERROR_STOP=1 -q"
fresh() {
  $P -d postgres -c "drop database if exists mg_test" -c "create database mg_test" >/dev/null
  $P -d mg_test -f "$D/00_supabase_stub.sql" >/dev/null
}
run_file() {
  local f="$1" out
  out=$($P -d mg_test -f "$f" 2>&1) || { echo "✗ $(basename "$f")"; echo "$out" | tail -25; exit 1; }
  echo "$out" | grep -E "NOTICE:  OK" | sed 's/.*NOTICE:  /  /'
  echo "$out" | grep -q "ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ" || { echo "✗ $(basename "$f")"; echo "$out" | tail -15; exit 1; }
  echo "✓ $(basename "$f")"
}

# 1. Αναβάθμιση: δεδομένα μισθοδοσίας πριν από τη νέα migration, έλεγχος ότι δεν αλλοιώθηκαν
fresh
MIGS=("$D"/../supabase/migrations/*.sql)
$P -d mg_test -f "${MIGS[0]}" >/dev/null
$P -d mg_test -f "$D/upgrade/before.sql" >/dev/null
for f in "${MIGS[@]:1}"; do $P -d mg_test -f "$f" >/dev/null; done
run_file "$D/upgrade/after.sql"

# 2. Όλα τα υπόλοιπα αρχεία ελέγχων, το καθένα σε καθαρή βάση με όλες τις migrations
for t in "$D"/[1-9]*.sql; do
  fresh
  for f in "${MIGS[@]}"; do $P -d mg_test -f "$f" >/dev/null; done
  run_file "$t"
done
echo "✓ ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ"
