-- Λογαριασμός Γενικής Διευθύντριας: mariamaneta@megagym.gr
-- Ορίζεται ρητά ο ρόλος owner (Γενική Διευθύντρια), ενεργός, χωρίς κατάστημα.
-- Αν ο λογαριασμός υπάρχει ήδη, αλλάζουν ΜΟΝΟ ρόλος/κατάστημα/κατάσταση· το όνομα μένει.
-- Κανένας άλλος χρήστης δεν αλλάζει ή διαγράφεται. Η αλλαγή καταγράφεται στο Ιστορικό ενεργειών (actor: system).
insert into public.app_users(email, name, role, store, active)
values ('mariamaneta@megagym.gr', 'Γενική Διευθύντρια', 'owner', null, true)
on conflict (email) do update
  set role = 'owner', store = null, active = true
  where public.app_users.role is distinct from 'owner'
     or public.app_users.store is not null
     or not public.app_users.active;
