# Έλεγχοι από άκρη σε άκρη (πρόγραμμα περιήγησης)

ΜΟΝΟ ΓΙΑ ΤΟΠΙΚΟ ΕΛΕΓΧΟ — τίποτα από αυτόν τον φάκελο δεν δημοσιεύεται.

Τρέχει την πραγματική εφαρμογή (`web/`) σε Chrome απέναντι σε τοπική PostgreSQL + PostgREST
(το ίδιο REST/RPC επίπεδο που χρησιμοποιεί το Supabase), με όλες τις migrations και τους ελέγχους δικαιωμάτων (RLS).
Χρησιμοποιούνται μόνο εικονικά στοιχεία και δοκιμαστικοί λογαριασμοί (`*@test.gr`, κωδικός `test1234`).

- `supabase-shim.js`: τοπικό υποκατάστατο της βιβλιοθήκης supabase-js (ίδιες κλήσεις που κάνει η εφαρμογή).
  Στην παραγωγή φορτώνεται η κανονική βιβλιοθήκη από το αυτόματο deploy.
- `server.mjs`: σερβίρει την εφαρμογή, προωθεί `/rest/v1` στο PostgREST και δίνει δοκιμαστική σύνδεση `/auth/v1`.

```bash
export PGHOST=localhost PGUSER=postgres PGPASSWORD=...  JWT_SECRET=<32+ χαρακτήρες>
./reset-db.sh && python3 make_xlsx.py
postgrest pgrst.conf &          # db-uri = postgres://authenticator:auth@localhost/mg_e2e, db-anon-role = anon, jwt-secret = $JWT_SECRET
node server.mjs ../../web &     # http://localhost:8787
python3 e2e_1_requests.py && python3 e2e_2_rest.py   # χρειάζεται playwright + Chrome
```
