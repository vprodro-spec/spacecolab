-- scl371: SpaceCoLLab Market, Κ2 συμπλήρωμα (ζητήθηκε 23/11): η φόρμα «Ζητήστε πληροφορίες» διαλέγει Brands από το μητρώο της βάσης,
-- τα Brands του αιτήματος περνούν μόνα τους στην εταιρία όταν τη φτιάξουν τα Κεντρικά, και τα Κεντρικά μπορούν να σβήσουν εταιρία.
-- ΑΛΛΑΓΕΣ: +1 στήλη στον mk_info_request (πίνακας του scl370), 2 νέες συναρτήσεις (scl371_*), και νέα έκδοση 2 συναρτήσεων του scl370
-- (scl370_mk_info_request, scl370_hq_company_save). Τίποτα παλαιότερο του Κ2 δεν αγγίζεται.
-- Προς τον ανώνυμο επισκέπτη φεύγουν ΜΟΝΟ ονόματα Brands (έως 12 ανά αναζήτηση, με 2+ γράμματα). Ποτέ μετρητές, κατηγορίες, εταιρίες.
-- Rollback: supabase/rollback/20261123173000_scl371_market_brand_pick_rollback.sql
-- ΕΦΑΡΜΟΣΤΗΚΕ 23/11/2026 (~17:10) μετά από ρητό «ναι σε όλα». Οι 4 συναρτήσεις ίδιες (md5) με των τοπικών δοκιμών· καμία άλλη συνάρτηση δεν άλλαξε.

CREATE TABLE scl_private.backup_v371_functions AS
 SELECT n.nspname::text AS schema_name, p.proname::text AS fn, pg_get_function_identity_arguments(p.oid) AS args,
        pg_get_functiondef(p.oid) AS definition, now() AS taken_at
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','scl_private') AND p.prokind='f';
ALTER TABLE scl_private.backup_v371_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v371_functions FROM PUBLIC,anon,authenticated;

ALTER TABLE scl_private.mk_info_request ADD COLUMN brand_ids integer[];

-- Αναζήτηση Brand για τη φόρμα (χωρίς σύνδεσμο): μόνο id και όνομα.
CREATE FUNCTION public.scl371_mk_brand_search(p_q text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT CASE WHEN length(btrim(coalesce(p_q,'')))<2 OR length(p_q)>60 THEN '[]'::jsonb ELSE coalesce((
  SELECT jsonb_agg(jsonb_build_object('id',x.id,'name',x.name) ORDER BY x.rn) FROM (
   SELECT b.id,b.name,row_number() OVER(ORDER BY (upper(b.name) LIKE upper(btrim(p_q))||'%') DESC, b.pharmacies DESC, b.name) rn
   FROM scl_private.mk_brand b WHERE position(upper(btrim(p_q)) IN upper(b.name))>0 ORDER BY rn LIMIT 12) x),'[]'::jsonb) END $$;

-- Αίτημα πληροφοριών: όπως στο scl370, και δέχεται brand_ids (έως 30, μόνο υπαρκτά). Τα ονόματά τους μπαίνουν και στο brands_text.
CREATE OR REPLACE FUNCTION public.scl370_mk_info_request(p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_company text:=scl_private.mk_txt(p,'company_name'); v_name text:=scl_private.mk_txt(p,'contact_name'); v_email text:=lower(scl_private.mk_txt(p,'email'));
 v_phone text:=scl_private.mk_txt(p,'phone'); v_brands text:=scl_private.mk_txt(p,'brands_text'); v_msg text:=nullif(btrim(coalesce(p->>'message','')),''); v_origin text;
 v_ids integer[];
BEGIN
 IF scl_private.mk_txt(p,'website') IS NOT NULL THEN RETURN jsonb_build_object('ok',true); END IF;
 IF v_company IS NULL OR length(v_company) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'MARKET_REQUEST:company_name' USING ERRCODE='22023'; END IF;
 IF v_name IS NULL OR length(v_name) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'MARKET_REQUEST:contact_name' USING ERRCODE='22023'; END IF;
 IF v_email IS NULL OR length(v_email)>120 OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' THEN RAISE EXCEPTION 'MARKET_REQUEST:email' USING ERRCODE='22023'; END IF;
 IF length(coalesce(v_phone,''))>30 OR coalesce(v_phone,'0') !~ '^[0-9+() .-]+$' THEN RAISE EXCEPTION 'MARKET_REQUEST:phone' USING ERRCODE='22023'; END IF;
 IF length(coalesce(v_brands,''))>300 THEN RAISE EXCEPTION 'MARKET_REQUEST:brands_text' USING ERRCODE='22023'; END IF;
 IF length(coalesce(v_msg,''))>1000 THEN RAISE EXCEPTION 'MARKET_REQUEST:message' USING ERRCODE='22023'; END IF;
 IF jsonb_typeof(p->'brand_ids')='array' THEN
  IF jsonb_array_length(p->'brand_ids')>30 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p->'brand_ids') e WHERE jsonb_typeof(e)<>'number' OR (e#>>'{}') !~ '^[0-9]{1,9}$') THEN
   RAISE EXCEPTION 'MARKET_REQUEST:brand_ids' USING ERRCODE='22023'; END IF;
  SELECT array_agg(b.id ORDER BY b.name) INTO v_ids FROM scl_private.mk_brand b WHERE b.id IN (SELECT (e#>>'{}')::integer FROM jsonb_array_elements(p->'brand_ids') e);
  IF v_ids IS NOT NULL THEN
   v_brands:=left(concat_ws(', ',(SELECT string_agg(b.name,', ' ORDER BY b.name) FROM scl_private.mk_brand b WHERE b.id=ANY(v_ids)),v_brands),300); END IF;
 END IF;
 BEGIN v_origin:=md5(coalesce(split_part(current_setting('request.headers',true)::jsonb->>'x-forwarded-for',',',1),''));
 EXCEPTION WHEN OTHERS THEN v_origin:=md5(''); END;
 IF (SELECT count(*) FROM scl_private.mk_info_request WHERE origin=v_origin AND created_at>now()-interval '1 hour')>=5
  OR (SELECT count(*) FROM scl_private.mk_info_request WHERE created_at>now()-interval '1 hour')>=40 THEN
  RAISE EXCEPTION 'MARKET_REQUEST_RATE' USING ERRCODE='53400'; END IF;
 INSERT INTO scl_private.mk_info_request(company_name,contact_name,email,phone,brands_text,message,origin,brand_ids)
  VALUES(v_company,v_name,v_email,v_phone,v_brands,v_msg,v_origin,v_ids);
 RETURN jsonb_build_object('ok',true);
END $$;

-- Δημιουργία/διόρθωση εταιρίας: όπως στο scl370· όταν φτιάχνεται από αίτημα, παίρνει μόνη της όσα Brands του αιτήματος είναι ελεύθερα.
CREATE OR REPLACE FUNCTION public.scl370_hq_company_save(p_hq_key text, p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE cid uuid:=nullif(p->>'id','')::uuid; v_name text:=scl_private.mk_txt(p,'name'); pr jsonb:=coalesce(p->'person','{}'::jsonb);
 v_person text:=scl_private.mk_txt(pr,'full_name'); rid uuid:=nullif(p->>'request_id','')::uuid;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF v_name IS NULL OR length(v_name) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'MARKET_COMPANY:name' USING ERRCODE='22023'; END IF;
 IF v_person IS NULL OR length(v_person) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'MARKET_COMPANY:person' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM scl_private.mk_company c WHERE upper(c.name)=upper(v_name) AND c.id IS DISTINCT FROM cid) THEN
  RAISE EXCEPTION 'MARKET_COMPANY_EXISTS' USING ERRCODE='23505'; END IF;
 IF cid IS NULL THEN
  INSERT INTO scl_private.mk_company(name,legal_name,vat,tax_office,address,billing_email,notes,request_id)
   VALUES(v_name,scl_private.mk_txt(p,'legal_name'),scl_private.mk_txt(p,'vat'),scl_private.mk_txt(p,'tax_office'),scl_private.mk_txt(p,'address'),
    lower(scl_private.mk_txt(p,'billing_email')),nullif(btrim(coalesce(p->>'notes','')),''),
    (SELECT r.id FROM scl_private.mk_info_request r WHERE r.id=rid)) RETURNING id INTO cid;
  UPDATE scl_private.mk_info_request SET status='done',handled_at=now() WHERE id=rid AND status='new';
  INSERT INTO scl_private.mk_company_brand(brand_id,company_id)
   SELECT b.id,cid FROM scl_private.mk_info_request r JOIN scl_private.mk_brand b ON b.id=ANY(r.brand_ids) WHERE r.id=rid
   ON CONFLICT(brand_id) DO NOTHING;
 ELSE
  UPDATE scl_private.mk_company SET name=v_name,legal_name=scl_private.mk_txt(p,'legal_name'),vat=scl_private.mk_txt(p,'vat'),tax_office=scl_private.mk_txt(p,'tax_office'),
   address=scl_private.mk_txt(p,'address'),billing_email=lower(scl_private.mk_txt(p,'billing_email')),notes=nullif(btrim(coalesce(p->>'notes','')),''),updated_at=now()
  WHERE id=cid;
  IF NOT FOUND THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  UPDATE scl_private.mk_access SET label=left(v_name,80) WHERE company_id=cid;
 END IF;
 INSERT INTO scl_private.mk_company_person(company_id,full_name,email,phone,role,is_primary)
  VALUES(cid,v_person,lower(scl_private.mk_txt(pr,'email')),scl_private.mk_txt(pr,'phone'),scl_private.mk_txt(pr,'role'),true)
 ON CONFLICT(company_id) WHERE is_primary DO UPDATE SET full_name=EXCLUDED.full_name,email=EXCLUDED.email,phone=EXCLUDED.phone,role=EXCLUDED.role;
 RETURN scl_private.mk_company_hq(cid);
END $$;

-- Οριστική διαγραφή εταιρίας: σβήνει εταιρία, υπεύθυνο, συνδέσμους και αναθέσεις Brands. Τα Brands μένουν στο μητρώο.
-- Αν είχε φτιαχτεί από αίτημα πληροφοριών, το αίτημα γυρίζει σε «νέο».
CREATE FUNCTION public.scl371_hq_company_delete(p_hq_key text, p_company_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE rid uuid;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT request_id INTO rid FROM scl_private.mk_company WHERE id=p_company_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 DELETE FROM scl_private.mk_access WHERE company_id=p_company_id;
 DELETE FROM scl_private.mk_company_brand WHERE company_id=p_company_id;
 DELETE FROM scl_private.mk_company_person WHERE company_id=p_company_id;
 DELETE FROM scl_private.mk_company WHERE id=p_company_id;
 UPDATE scl_private.mk_info_request SET status='new',handled_at=NULL WHERE id=rid AND status='done';
 RETURN jsonb_build_object('ok',true);
END $$;

REVOKE ALL ON FUNCTION public.scl371_mk_brand_search(text),public.scl371_hq_company_delete(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl371_mk_brand_search(text),public.scl371_hq_company_delete(text,uuid) TO anon,authenticated;
