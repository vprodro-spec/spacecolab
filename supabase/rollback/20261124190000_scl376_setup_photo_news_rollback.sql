-- ROLLBACK SCL376: οι 4 συναρτήσεις γυρίζουν όπως ήταν μετά το SCL375, φεύγουν οι 3 των φωτογραφιών.
-- Ο χώρος αρχείων «scl375-setup» και το πρόγραμμα «scl375-photo» σβήνονται από το Supabase (δεν σβήνονται με SQL). Οι στήλες photo_key μένουν με ό,τι έχουν.
BEGIN;
DO $do$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM scl_private.backup_v376_functions)<>4 THEN RAISE EXCEPTION 'SCL376 rollback: λείπει αντίγραφο'; END IF;
 FOR r IN SELECT def FROM scl_private.backup_v376_functions LOOP EXECUTE r.def; END LOOP;
END $do$;
DROP FUNCTION public.scl375_photo_begin(text,text),public.scl375_photo_commit(text,text,text),public.scl375_photo_path(text,int,int,text);
DROP TABLE scl_private.backup_v376_functions;
COMMIT;
