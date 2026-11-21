#!/bin/bash
# 3.1 · Ταυτόχρονη δημιουργία εργαζομένων χωρίς διπλούς κωδικούς: 4 παράλληλες συνεδρίες × 25 νέοι εργαζόμενοι με κενό κωδικό.
# Τρέχει από το run.sh σε καθαρή βάση με όλες τις migrations. ΕΙΚΟΝΙΚΑ ΣΤΟΙΧΕΙΑ.
set -e
DB="$1"; P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
$P -c "insert into employees(code,first,last,store,company,work_week) values ('0500','Α','Β','Γλυφάδα','BEST GREEK GYMS IKE',5)"
for s in 1 2 3 4; do
  ( for i in $(seq 1 25); do $P -c "insert into employees(code,first,last,store,company,work_week) values ('AUTO','Σ$s','Ε$i','Γλυφάδα','BEST GREEK GYMS IKE',5)"; done ) &
done
wait
R=$($P -At -c "select count(*)||'|'||count(distinct code)||'|'||min(code)||'|'||max(code) from employees where code <> '0500'")
[ "$R" = "100|100|0501|0600" ] || { echo "✗ 88_concurrent_codes.sh: $R"; exit 1; }
echo "  OK 100 ταυτόχρονες δημιουργίες → 100 μοναδικοί διαδοχικοί κωδικοί (0501–0600)"
echo "✓ 88_concurrent_codes.sh"
