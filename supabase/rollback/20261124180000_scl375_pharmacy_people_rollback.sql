-- ROLLBACK SCL375: οι 5 συναρτήσεις γυρίζουν ακριβώς όπως ήταν, φεύγουν οι νέες στήλες, συναρτήσεις και πίνακες.
-- ΠΡΟΣΟΧΗ: χάνονται οι σύνδεσμοι με όνομα και τα «Στήθηκε».
BEGIN;
DO $do$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM scl_private.backup_v375_functions)<>5 THEN RAISE EXCEPTION 'SCL375 rollback: λείπει αντίγραφο'; END IF;
 FOR r IN SELECT def FROM scl_private.backup_v375_functions LOOP EXECUTE r.def; END LOOP;
END $do$;
ALTER TABLE public.scl292_program_history DROP COLUMN person;
ALTER TABLE public.scl292_reset_requests DROP COLUMN person;
ALTER TABLE scl_private.mk_request_log DROP COLUMN person;
DROP FUNCTION public.scl375_ph_whoami(text),public.scl375_ph_people(text),public.scl375_ph_person_add(text,text,text),public.scl375_ph_person_revoke(text,uuid),public.scl375_ph_done(text,int),public.scl375_hq_people(text,uuid),public.scl375_hq_person_revoke(text,uuid),public.scl375_staff_get(text),public.scl375_staff_done(text,int,int,text,boolean);
DROP FUNCTION scl_private.ph375_person_json(scl_private.ph_person,boolean),scl_private.ph375_pick(jsonb,text[]),scl_private.ph375_who(text),scl_private.ph375_owner_id(text),scl_private.ph375_token(text),scl_private.ph375_actor();
DROP TABLE scl_private.ph_setup_done,scl_private.ph_person,scl_private.backup_v375_functions;
COMMIT;
