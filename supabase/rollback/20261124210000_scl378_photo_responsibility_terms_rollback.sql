-- ROLLBACK SCL378: οι 2 συναρτήσεις όπως ήταν, και οι όροι πίσω στην έκδοση 1. Αν υπάρχει αίτημα με όρους έκδοσης 2, σταματά χωρίς να αλλάξει τίποτα.
BEGIN;
DO $do$ DECLARE r record; BEGIN
 IF EXISTS(SELECT 1 FROM scl_private.mk_request WHERE terms_company=2 OR terms_pharmacy=2) THEN RAISE EXCEPTION 'SCL378 rollback: υπάρχουν αιτήματα με όρους έκδοσης 2'; END IF;
 IF (SELECT count(*) FROM scl_private.backup_v378_functions)<>2 THEN RAISE EXCEPTION 'SCL378 rollback: λείπει αντίγραφο'; END IF;
 FOR r IN SELECT def FROM scl_private.backup_v378_functions LOOP EXECUTE r.def; END LOOP;
END $do$;
DELETE FROM scl_private.mk_terms WHERE version=2;
DROP TABLE scl_private.backup_v378_functions;
COMMIT;
