-- Επιστροφή του scl361: σβήνει τη νέα συνάρτηση και τα σημεία των φαρμακείων χωρίς οθόνες. Τα 16 σημεία των φαρμακείων με οθόνες δεν αγγίζονται.
BEGIN;
DROP FUNCTION IF EXISTS public.scl361_mk_dots(text);
DELETE FROM scl_private.mk_pharmacy WHERE geo_source='scl361 · κατά προσέγγιση (mockup)' AND terms_accepted_at IS NULL;
COMMIT;
