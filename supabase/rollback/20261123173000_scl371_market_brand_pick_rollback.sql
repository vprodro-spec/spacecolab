-- Αναίρεση του scl371. Γυρίζει τις 2 συναρτήσεις του scl370 στην προηγούμενη έκδοσή τους (από το αντίγραφο backup_v371_functions),
-- σβήνει τις 2 νέες συναρτήσεις και τη στήλη brand_ids. Εταιρίες, Brands και αιτήματα μένουν.
DROP FUNCTION IF EXISTS public.scl371_hq_company_delete(text,uuid);
DROP FUNCTION IF EXISTS public.scl371_mk_brand_search(text);
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT definition FROM scl_private.backup_v371_functions WHERE schema_name='public' AND fn IN ('scl370_mk_info_request','scl370_hq_company_save') LOOP
  EXECUTE r.definition; END LOOP; END $$;
ALTER TABLE scl_private.mk_info_request DROP COLUMN IF EXISTS brand_ids;
DROP TABLE IF EXISTS scl_private.backup_v371_functions;
