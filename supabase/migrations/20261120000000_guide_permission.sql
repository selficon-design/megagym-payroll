-- Δικαίωμα «Οδηγός χρήσης»: η ΓΔ ορίζει από τον πίνακα Ρόλοι & Δικαιώματα ποιοι ρόλοι βλέπουν τον οδηγό (και το PDF του).
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: μόνο προσθήκη. Ξεκινά ανοιχτό σε όλους τους ρόλους, όπως λειτουργούσε ως τώρα· η ΓΔ το κλείνει όπου θέλει.
-- Ο οδηγός δίνεται από τη λειτουργία server «guide», που ελέγχει αυτό το δικαίωμα.
insert into public.permissions(code, module, label, description, fixed_roles, sort)
values ('guide.view', 'Γενικά', 'Οδηγός χρήσης (προβολή και PDF)', 'Η σελίδα «Οδηγός χρήσης» και η λήψη του σε PDF', null, 81)
on conflict (code) do nothing;

insert into public.role_permissions(role, perm, allowed)
select r, 'guide.view', true from unnest(array['owner','hr','accounting','manager','trainer']) r
on conflict (role, perm) do nothing;
