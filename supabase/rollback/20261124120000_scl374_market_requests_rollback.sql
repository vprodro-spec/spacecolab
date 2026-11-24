-- Αναίρεση του scl374. Γυρίζει τις 2 συναρτήσεις του Κ2 στην προηγούμενη έκδοση (από το backup_v374_functions) και σβήνει ό,τι πρόσθεσε.
-- ΠΡΟΣΟΧΗ: σβήνει και όλα τα αιτήματα με το ιστορικό τους. Αν υπάρχουν πραγματικά αιτήματα, πάρε πρώτα αντίγραφο των δύο πινάκων.
DROP FUNCTION IF EXISTS public.scl374_mk_planogram_delete(text,uuid),public.scl374_mk_planogram_save(text,jsonb),public.scl374_mk_planograms(text),public.scl374_mk_terms(text),public.scl374_hq_test_purge(text,uuid),public.scl374_hq_company_test(text,uuid,boolean),public.scl374_hq_request_log(text,uuid),
 public.scl374_hq_request_cancel(text,uuid,text),public.scl374_hq_requests(text),public.scl374_ph_request_log(text,uuid),public.scl374_ph_request_decline(text,uuid,text,text),
 public.scl374_ph_requests(text,boolean),public.scl374_mk_request_log(text,uuid),public.scl374_mk_request_withdraw(text,uuid),public.scl374_mk_requests_seen(text),
 public.scl374_mk_requests(text),public.scl374_mk_request_send(text,jsonb);
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT definition FROM scl_private.backup_v374_functions WHERE (schema_name='scl_private' AND fn='mk_company_hq') OR (schema_name='public' AND fn='scl371_hq_company_delete') LOOP
  EXECUTE r.definition; END LOOP; END $$;
DROP FUNCTION IF EXISTS scl_private.mk_terms_items(text,integer,boolean),scl_private.mk_plan_list(uuid),scl_private.mk_shelves(jsonb,text),scl_private.mk_shelf_spec(text),scl_private.mk_ints(jsonb,integer),scl_private.mk_strs(jsonb,integer),scl_private.mk_req_history(uuid,text),scl_private.mk_req_json(scl_private.mk_request,text),
 scl_private.mk_req_sweep(uuid,uuid),scl_private.mk_req_log(uuid,text,text,text,jsonb),scl_private.mk_req_block(uuid,text,integer,integer[]),scl_private.mk_req_label(integer,timestamptz);
DROP TABLE IF EXISTS scl_private.mk_request_log,scl_private.mk_request,scl_private.mk_planogram,scl_private.mk_terms;
DROP FUNCTION IF EXISTS scl_private.mk_request_log_guard(),scl_private.mk_request_guard();
DROP SEQUENCE IF EXISTS scl_private.mk_request_no;
ALTER TABLE scl_private.mk_company DROP COLUMN IF EXISTS is_test;
DROP TABLE IF EXISTS scl_private.backup_v374_functions;
