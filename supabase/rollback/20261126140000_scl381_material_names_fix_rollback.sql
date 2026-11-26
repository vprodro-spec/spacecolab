-- rollback scl381: επαναφέρει τις τρεις συναρτήσεις όπως ήταν στο scl380
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT def FROM scl_private.backup_v380_functions WHERE name LIKE 'v381:%' LOOP EXECUTE r.def; END LOOP;
 DELETE FROM scl_private.backup_v380_functions WHERE name LIKE 'v381:%';
END $$;
