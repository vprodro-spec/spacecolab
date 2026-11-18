-- scl3319 (v331.9): κωδικός φαρμακείου (BI / Lavinet) στο μητρώο, ξεχωριστά από τον κωδικό τιμολόγησης.
-- ΕΦΑΡΜΟΣΤΗΚΕ στη βάση στις 2026-11-18 (μετά από backup και ρητό «ναι»).
-- Προσθετική αλλαγή: νέα στήλη + μοναδικό ευρετήριο. Δεν αγγίζει καμία υπάρχουσα στήλη, λειτουργία ή γραμμή.
-- Οι λειτουργίες scl290_hq_registry_save / scl290_hq_data δεν αλλάζουν: η save ενημερώνει μόνο συγκεκριμένες στήλες,
-- άρα η νέα τιμή διατηρείται, και η hq_data επιστρέφει όλη τη γραμμή (to_jsonb).
-- Backup πριν την αλλαγή: scl_private.scl290_registry_bak_20261118 (πλήρες αντίγραφο, 99 γραμμές, ιδιωτικό σχήμα).
-- Οι τιμές του pharmacy_code (αντιστοίχιση BI ↔ κωδικός τιμολόγησης) ΔΕΝ βρίσκονται σε αυτό το αρχείο: το repo είναι δημόσιο
-- και τα δεδομένα μητρώου ζουν μόνο στη βάση. Συμπληρώθηκαν ξεχωριστά με UPDATE (78 γραμμές), χωρίς αλλαγή revision/updated_at.
-- Rollback: supabase/rollback/20261118170000_scl3319_pharmacy_code_rollback.sql

ALTER TABLE public.scl290_registry ADD COLUMN IF NOT EXISTS pharmacy_code text;
CREATE UNIQUE INDEX IF NOT EXISTS scl290_registry_pharmacy_code_key ON public.scl290_registry (pharmacy_code) WHERE pharmacy_code IS NOT NULL;
