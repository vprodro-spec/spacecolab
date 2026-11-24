-- ROLLBACK SCL377: οι 2 συναρτήσεις όπως ήταν μετά το SCL376, φεύγουν οι νέες και οι 3 στήλες (χάνονται εγκρίσεις και μεγέθη· οι φωτογραφίες μένουν).
-- Το πρόγραμμα scl375-photo πρέπει να γυρίσει στην έκδοση 1.
BEGIN;
DROP FUNCTION public.scl375_hq_setups(text,int,int),public.scl375_hq_setup_approve(text,uuid,int,int,text,boolean),public.scl375_ph_setup_approve(text,int,int,text,boolean),scl_private.ph377_approve(uuid,int,int,text,boolean,text),public.scl375_photo_path_hq(text,uuid,int,int,text),public.scl375_photo_commit(text,text,text,int);
DO $do$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM scl_private.backup_v377_functions)<>2 THEN RAISE EXCEPTION 'SCL377 rollback: λείπει αντίγραφο'; END IF;
 FOR r IN SELECT def FROM scl_private.backup_v377_functions LOOP EXECUTE r.def; END LOOP;
END $do$;
REVOKE ALL ON FUNCTION public.scl375_photo_commit(text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl375_photo_commit(text,text,text) TO service_role;
ALTER TABLE scl_private.ph_setup_done DROP COLUMN photo_bytes, DROP COLUMN approved_at, DROP COLUMN approved_by;
DROP TABLE scl_private.backup_v377_functions;
COMMIT;
