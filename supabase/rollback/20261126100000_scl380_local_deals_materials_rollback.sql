-- Rollback scl380: σβήνει ό,τι πρόσθεσε· επαναφέρει τη mk_req_json από το αντίγραφο.
DROP TRIGGER IF EXISTS scl380_material_guard ON public.scl290_snapshots;
DROP FUNCTION IF EXISTS scl_private.material_guard();
DROP FUNCTION IF EXISTS public.scl380_ph_brand_search(text,text);
DROP FUNCTION IF EXISTS public.scl380_ph_supplier_brands(text,uuid);
DROP FUNCTION IF EXISTS public.scl380_ph_supplier_code(text,text);
DROP FUNCTION IF EXISTS public.scl380_ph_reserve(text,integer,text,text,jsonb,jsonb);
DROP FUNCTION IF EXISTS public.scl380_ph_mark_sent(text,integer,text,text,text);
DROP FUNCTION IF EXISTS public.scl380_ph_materials(text,integer);
DROP FUNCTION IF EXISTS public.scl380_hq_materials(text,integer);
DROP FUNCTION IF EXISTS public.scl380_hq_pending(text);
DROP FUNCTION IF EXISTS public.scl380_hq_pending_resolve(text,uuid,text,text,text);
DROP FUNCTION IF EXISTS scl_private.k3c_first_code(text);
DO $r$ DECLARE d text; BEGIN
 SELECT def INTO d FROM scl_private.backup_v380_functions WHERE name='scl_private.mk_req_json(scl_private.mk_request,text)';
 IF d IS NOT NULL THEN EXECUTE d; END IF;
END $r$;
DELETE FROM scl_private.mk_terms WHERE version=3 AND NOT EXISTS(SELECT 1 FROM scl_private.mk_request WHERE terms_company=3 OR terms_pharmacy=3);
DROP TABLE IF EXISTS scl_private.ph_registry_pending;
DROP TABLE IF EXISTS scl_private.material_sent;
DROP TABLE IF EXISTS scl_private.material_file;
-- Προμηθευτές/Brands που πρόσθεσαν τα Κεντρικά από «Από φαρμακεία» μένουν στο μητρώο (σβήνονται με το χέρι αν χρειαστεί).
