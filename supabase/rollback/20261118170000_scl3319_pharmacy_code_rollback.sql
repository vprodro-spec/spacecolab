-- Rollback για scl3319: αφαιρεί τον κωδικό φαρμακείου (BI) από το μητρώο. Τα υπόλοιπα δεδομένα δεν επηρεάζονται.
-- Το πλήρες αντίγραφο του μητρώου πριν την αλλαγή βρίσκεται στο scl_private.scl290_registry_bak_20261118.
DROP INDEX IF EXISTS public.scl290_registry_pharmacy_code_key;
ALTER TABLE public.scl290_registry DROP COLUMN IF EXISTS pharmacy_code;
-- (προαιρετικά, αφού επιβεβαιωθεί η αναίρεση) DROP TABLE scl_private.scl290_registry_bak_20261118;
