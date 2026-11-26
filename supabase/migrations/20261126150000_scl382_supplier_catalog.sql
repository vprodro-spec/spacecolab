-- scl382 · Κατάλογος προμηθευτών από το αρχείο κωδικών
-- Όλοι οι προμηθευτές μπαίνουν στην ίδια λίστα (mk_company) με source='catalog' και χωρίς πρόσβαση στο Market.
-- Οι πιθανοί προμηθευτές ανά Brand (για τις τοπικές συμφωνίες) ζουν στο mk_brand_supplier· ο κανόνας του Market
-- «ένα Brand, ένας προμηθευτής» (mk_company_brand) δεν αλλάζει.
INSERT INTO scl_private.backup_v380_functions(name,def)
SELECT 'v382:'||p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p
WHERE p.oid IN ('public.scl370_hq_overview(text)'::regprocedure,'public.scl380_ph_brand_search(text,text)'::regprocedure,'public.scl380_ph_supplier_brands(text,uuid)'::regprocedure)
ON CONFLICT(name) DO NOTHING;

ALTER TABLE scl_private.mk_company ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'hq';
ALTER TABLE scl_private.mk_company ADD CONSTRAINT mk_company_source_chk CHECK (source IN ('hq','catalog'));

CREATE TABLE scl_private.mk_brand_supplier(
 brand_id integer NOT NULL REFERENCES scl_private.mk_brand(id) ON DELETE CASCADE,
 company_id uuid NOT NULL REFERENCES scl_private.mk_company(id) ON DELETE CASCADE,
 items integer NOT NULL DEFAULT 0,
 PRIMARY KEY(brand_id,company_id)
);
CREATE INDEX mk_brand_supplier_company ON scl_private.mk_brand_supplier(company_id);
-- Άλλα ονόματα του ίδιου προμηθευτή (π.χ. όπως γράφεται στο αρχείο), για να μη μπει δύο φορές.
CREATE TABLE scl_private.mk_company_alias(
 name_key text PRIMARY KEY,
 company_id uuid NOT NULL REFERENCES scl_private.mk_company(id) ON DELETE CASCADE
);
ALTER TABLE scl_private.mk_brand_supplier ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_company_alias ENABLE ROW LEVEL SECURITY;

-- Ο PIERRE υπάρχει ήδη· στο αρχείο γράφεται με την πλήρη επωνυμία.
INSERT INTO scl_private.mk_company_alias(name_key,company_id)
SELECT 'PIERRE FABRE HELLAS S.A.',id FROM scl_private.mk_company WHERE code='PIERRE' ON CONFLICT DO NOTHING;

-- Μοναδικός κωδικός: πρώτη λέξη· αν υπάρχει, οι δύο πρώτες· αλλιώς με αριθμό.
CREATE OR REPLACE FUNCTION scl_private.k3d_supplier_code(p_name text, p_two boolean DEFAULT false)
 RETURNS text LANGUAGE plpgsql STABLE SET search_path TO ''
AS $function$
DECLARE nm text:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g'); c text;
BEGIN
 c:=scl_private.k3c_first_code(nm);
 IF NOT coalesce(p_two,false) AND c ~ '^[A-Z0-9]{2,20}$' AND NOT EXISTS(SELECT 1 FROM scl_private.mk_company x WHERE x.code=c) THEN RETURN c; END IF;
 c:=left(scl_private.mk_code_from(split_part(nm,' ',1)||split_part(nm,' ',2)),20);
 IF c ~ '^[A-Z0-9]{2,20}$' AND NOT EXISTS(SELECT 1 FROM scl_private.mk_company x WHERE x.code=c) THEN RETURN c; END IF;
 RETURN scl_private.mk_code_unique('company',nm,NULL);
END $function$;

-- Κεντρικά: φόρτωση από το αρχείο κωδικών. p = {suppliers:[όνομα,…], links:[[brand, δείκτης προμηθευτή, πλήθος κωδικών],…]}
CREATE OR REPLACE FUNCTION public.scl382_hq_suppliers_load(p_hq_key text, p jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE nm text; i integer:=0; cid uuid; ids uuid[]:='{}'; added integer:=0; l jsonb; bid integer; nl integer:=0; miss integer:=0; dups text[];
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF jsonb_typeof(p->'suppliers')<>'array' OR jsonb_typeof(p->'links')<>'array' OR jsonb_array_length(p->'suppliers')>5000 OR jsonb_array_length(p->'links')>20000 THEN RAISE EXCEPTION 'REGISTRY_FORMAT' USING ERRCODE='22023'; END IF;
 -- Ονόματα με ίδια πρώτη λέξη μέσα στο αρχείο παίρνουν όλα κωδικό από τις δύο πρώτες λέξεις.
 dups:=ARRAY(SELECT z.c FROM (SELECT scl_private.k3c_first_code(value) c FROM jsonb_array_elements_text(p->'suppliers')) z GROUP BY z.c HAVING count(*)>1);
 FOR nm IN SELECT left(regexp_replace(btrim(value),'\s+',' ','g'),120) FROM jsonb_array_elements_text(p->'suppliers') WITH ORDINALITY t(value,o) ORDER BY o LOOP
  cid:=NULL;
  IF length(nm)>=2 AND upper(nm) NOT LIKE '%UNKNOWN%' AND upper(nm) NOT LIKE '%ΑΓΝΩΣΤ%' THEN
   SELECT a.company_id INTO cid FROM scl_private.mk_company_alias a WHERE a.name_key=upper(nm);
   IF cid IS NULL THEN SELECT c.id INTO cid FROM scl_private.mk_company c WHERE upper(c.name)=upper(nm); END IF;
   IF cid IS NULL THEN
    INSERT INTO scl_private.mk_company(name,code,active,source,notes) VALUES(nm,scl_private.k3d_supplier_code(nm,scl_private.k3c_first_code(nm)=ANY(dups)),false,'catalog','Από το αρχείο κωδικών') RETURNING id INTO cid;
    added:=added+1;
   END IF;
  END IF;
  ids:=ids||cid; i:=i+1;
 END LOOP;
 FOR l IN SELECT value FROM jsonb_array_elements(p->'links') LOOP
  cid:=ids[(l->>1)::integer+1];
  IF cid IS NULL THEN CONTINUE; END IF;
  SELECT b.id INTO bid FROM scl_private.mk_brand b WHERE upper(b.name)=upper(regexp_replace(btrim(l->>0),'\s+',' ','g')) LIMIT 1;
  IF bid IS NULL THEN miss:=miss+1; CONTINUE; END IF;
  INSERT INTO scl_private.mk_brand_supplier(brand_id,company_id,items) VALUES(bid,cid,greatest(0,coalesce((l->>2)::integer,0)))
  ON CONFLICT(brand_id,company_id) DO UPDATE SET items=excluded.items;
  nl:=nl+1;
 END LOOP;
 RETURN jsonb_build_object('added',added,'suppliers',(SELECT count(*) FROM scl_private.mk_company),'catalog',(SELECT count(*) FROM scl_private.mk_company WHERE source='catalog'),
  'links',(SELECT count(*) FROM scl_private.mk_brand_supplier),'sent_links',nl,'unknown_brands',miss,
  'multi',(SELECT count(*) FROM (SELECT brand_id FROM scl_private.mk_brand_supplier GROUP BY brand_id HAVING count(*)>1) x));
END $function$;

-- Κεντρικά: αναζήτηση στους προμηθευτές χωρίς πρόσβαση.
CREATE OR REPLACE FUNCTION public.scl382_hq_catalog_search(p_hq_key text, p_q text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE q text:=upper(btrim(coalesce(p_q,'')));
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN jsonb_build_object('total',(SELECT count(*) FROM scl_private.mk_company WHERE source='catalog'),
  'rows',CASE WHEN length(q)<2 THEN '[]'::jsonb ELSE coalesce((SELECT jsonb_agg(x.j ORDER BY x.rn) FROM (
   SELECT jsonb_build_object('id',c.id,'name',c.name,'code',c.code,
     'brands',(SELECT coalesce(jsonb_agg(z.name ORDER BY z.items DESC,z.name),'[]'::jsonb) FROM (SELECT b.name,bs.items FROM scl_private.mk_brand_supplier bs JOIN scl_private.mk_brand b ON b.id=bs.brand_id WHERE bs.company_id=c.id ORDER BY bs.items DESC,b.name LIMIT 8) z),
     'brand_count',(SELECT count(*) FROM scl_private.mk_brand_supplier bs WHERE bs.company_id=c.id)) j,
    row_number() OVER(ORDER BY (upper(c.name) LIKE q||'%') DESC,(SELECT coalesce(sum(items),0) FROM scl_private.mk_brand_supplier bs WHERE bs.company_id=c.id) DESC,c.name) rn
   FROM scl_private.mk_company c WHERE c.source='catalog' AND (position(q IN upper(c.name))>0 OR c.code LIKE q||'%'
     OR EXISTS(SELECT 1 FROM scl_private.mk_brand_supplier bs JOIN scl_private.mk_brand b ON b.id=bs.brand_id WHERE bs.company_id=c.id AND upper(b.name)=q))
   ORDER BY rn LIMIT 20) x),'[]'::jsonb) END);
END $function$;

-- Κεντρικά: «Δώσε πρόσβαση». Ο προμηθευτής περνά στους κανονικούς και παίρνει στο Market όσα Brands του είναι ελεύθερα.
CREATE OR REPLACE FUNCTION public.scl382_hq_supplier_grant(p_hq_key text, p_company_id uuid, p_request_id uuid DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE taken jsonb;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 UPDATE scl_private.mk_company SET source='hq',active=true,updated_at=now(),
   request_id=coalesce((SELECT r.id FROM scl_private.mk_info_request r WHERE r.id=p_request_id),request_id) WHERE id=p_company_id AND source='catalog';
 IF NOT FOUND THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 -- Αν ήρθε από «Ζητήστε πληροφορίες»: το αίτημα κλείνει και μπαίνουν τα Brands που ζήτησε (όσα είναι ελεύθερα).
 IF p_request_id IS NOT NULL THEN
  UPDATE scl_private.mk_info_request SET status='done',handled_at=now() WHERE id=p_request_id AND status='new';
  INSERT INTO scl_private.mk_company_brand(brand_id,company_id)
   SELECT b.id,p_company_id FROM scl_private.mk_info_request r JOIN scl_private.mk_brand b ON b.id=ANY(r.brand_ids) WHERE r.id=p_request_id ON CONFLICT(brand_id) DO NOTHING;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('brand',b.name,'owner',o.name) ORDER BY b.name),'[]'::jsonb) INTO taken
  FROM scl_private.mk_brand_supplier bs JOIN scl_private.mk_brand b ON b.id=bs.brand_id
  JOIN scl_private.mk_company_brand cb ON cb.brand_id=bs.brand_id JOIN scl_private.mk_company o ON o.id=cb.company_id
  WHERE bs.company_id=p_company_id AND cb.company_id<>p_company_id;
 INSERT INTO scl_private.mk_company_brand(brand_id,company_id)
  SELECT bs.brand_id,p_company_id FROM scl_private.mk_brand_supplier bs WHERE bs.company_id=p_company_id ON CONFLICT(brand_id) DO NOTHING;
 RETURN jsonb_build_object('company',scl_private.mk_company_hq(p_company_id),'taken',taken);
END $function$;

-- Η καρτέλα «Προμηθευτές» δείχνει μόνο όσους έχουν ή είχαν πρόσβαση.
CREATE OR REPLACE FUNCTION public.scl370_hq_overview(p_hq_key text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN jsonb_build_object(
  'requests',(SELECT coalesce(jsonb_agg(to_jsonb(q)-'origin' ORDER BY (q.status<>'new'),q.created_at DESC),'[]'::jsonb) FROM (
     SELECT r.*,(SELECT c.id FROM scl_private.mk_company c WHERE c.request_id=r.id LIMIT 1) company_id FROM scl_private.mk_info_request r
     WHERE r.status='new' OR r.created_at>now()-interval '90 days' ORDER BY r.created_at DESC LIMIT 200) q),
  'companies',(SELECT coalesce(jsonb_agg(scl_private.mk_company_hq(c.id) ORDER BY NOT c.active,upper(c.name)),'[]'::jsonb) FROM scl_private.mk_company c WHERE c.source='hq'),
  'categories',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,
      'brands',(SELECT count(DISTINCT bs.brand_id) FROM scl_private.mk_brand_scope bs WHERE bs.category_id=c.id)) ORDER BY c.name),'[]'::jsonb) FROM scl_private.mk_category c),
  'counts',jsonb_build_object('brands',(SELECT count(*) FROM scl_private.mk_brand),'assigned',(SELECT count(*) FROM scl_private.mk_company_brand),
   'subcategories',(SELECT count(*) FROM scl_private.mk_subcategory),
   'requests_new',(SELECT count(*) FROM scl_private.mk_info_request WHERE status='new'),
   'companies',(SELECT count(*) FROM scl_private.mk_company WHERE active),
   'catalog',(SELECT count(*) FROM scl_private.mk_company WHERE source='catalog')));
END $function$;

-- Φαρμακείο: το Brand επιστρέφει όλους τους πιθανούς προμηθευτές (suppliers)· supplier = ο μοναδικός, όταν είναι ένας.
CREATE OR REPLACE FUNCTION public.scl380_ph_brand_search(p_token text, p_q text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE q text:=btrim(coalesce(p_q,''));
BEGIN
 PERFORM public.scl290_token_id(p_token);
 IF length(q)<2 OR length(q)>60 THEN RETURN '[]'::jsonb; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',y.id,'name',y.name,'code',y.code,'scopes',scl_private.mk_brand_scopes(y.id,false),
    'suppliers',y.sup,'supplier',CASE WHEN jsonb_array_length(y.sup)=1 THEN y.sup->0 END) ORDER BY y.rn) FROM (
  SELECT b.id,b.name,b.code,
    coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'code',c.code,'test',c.is_test) ORDER BY c.is_test,s.w DESC,c.name)
      FROM (SELECT z.company_id,max(z.w) w FROM (SELECT cb.company_id,1000000 w FROM scl_private.mk_company_brand cb WHERE cb.brand_id=b.id
            UNION ALL SELECT bs.company_id,bs.items FROM scl_private.mk_brand_supplier bs WHERE bs.brand_id=b.id) z GROUP BY z.company_id) s
      JOIN scl_private.mk_company c ON c.id=s.company_id),'[]'::jsonb) sup,
   row_number() OVER(ORDER BY (upper(b.name) LIKE upper(q)||'%') DESC, b.pharmacies DESC, b.name) rn
  FROM scl_private.mk_brand b WHERE position(upper(q) IN upper(b.name))>0 ORDER BY rn LIMIT 12) y),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.scl380_ph_supplier_brands(p_token text, p_company_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_token_id(p_token);
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'code',b.code,'scopes',scl_private.mk_brand_scopes(b.id,false)) ORDER BY b.name)
  FROM scl_private.mk_brand b WHERE b.id IN (SELECT cb.brand_id FROM scl_private.mk_company_brand cb WHERE cb.company_id=p_company_id
    UNION SELECT bs.brand_id FROM scl_private.mk_brand_supplier bs WHERE bs.company_id=p_company_id)),'[]'::jsonb);
END $function$;

REVOKE ALL ON FUNCTION public.scl382_hq_suppliers_load(text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl382_hq_catalog_search(text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl382_hq_supplier_grant(text,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl382_hq_suppliers_load(text,jsonb) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl382_hq_catalog_search(text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl382_hq_supplier_grant(text,uuid,uuid) TO anon,authenticated;
