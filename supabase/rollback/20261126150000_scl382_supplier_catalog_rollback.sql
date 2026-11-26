-- rollback scl382: σβήνει τον κατάλογο και επαναφέρει τις τρεις συναρτήσεις.
-- Προμηθευτές του καταλόγου που πήραν πρόσβαση (source='hq') ΜΕΝΟΥΝ.
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT def FROM scl_private.backup_v380_functions WHERE name LIKE 'v382:%' LOOP EXECUTE r.def; END LOOP;
 DELETE FROM scl_private.backup_v380_functions WHERE name LIKE 'v382:%';
END $$;
DROP FUNCTION IF EXISTS public.scl382_hq_suppliers_load(text,jsonb);
DROP FUNCTION IF EXISTS public.scl382_hq_catalog_search(text,text);
DROP FUNCTION IF EXISTS public.scl382_hq_supplier_grant(text,uuid,uuid);
DROP FUNCTION IF EXISTS scl_private.k3d_supplier_code(text,boolean);
DROP TABLE IF EXISTS scl_private.mk_brand_supplier;
DROP TABLE IF EXISTS scl_private.mk_company_alias;
DELETE FROM scl_private.mk_company WHERE source='catalog';
ALTER TABLE scl_private.mk_company DROP CONSTRAINT IF EXISTS mk_company_source_chk;
ALTER TABLE scl_private.mk_company DROP COLUMN IF EXISTS source;
