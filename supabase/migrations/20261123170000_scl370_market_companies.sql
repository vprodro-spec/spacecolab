-- scl370: SpaceCoLLab Market, κομμάτι Κ2 «Εταιρίες & Brands».
-- Μητρώο Brands / κατηγοριών / υποκατηγοριών (μόνο ονόματα, ποτέ ποσά, ποτέ φαρμακείο), εταιρίες που φτιάχνουν ΜΟΝΟ τα Κεντρικά,
-- σύνδεσμος ανά εταιρία (έτοιμο για σύνδεσμο ανά άνθρωπο), αίτημα πληροφοριών από το Market.
-- ΠΡΟΣΘΗΚΕΣ: νέοι πίνακες scl_private.mk_* και νέες συναρτήσεις scl370_* / scl_private.mk_*.
-- ΜΟΝΗ αλλαγή σε υπάρχον αντικείμενο: ο πίνακας scl_private.mk_access αποκτά 2 στήλες (company_id, person_id) και ο έλεγχος
-- του είδους δέχεται και 'company'. Καμία υπάρχουσα συνάρτηση ή γραμμή δεν αλλάζει. Ο δοκιμαστικός σύνδεσμος συνεχίζει να δουλεύει.
-- Προς την εταιρία ΔΕΝ φεύγει ποτέ: το μητρώο, άλλες εταιρίες, πόσα φαρμακεία πουλάνε ένα Brand, ποσά.
-- Rollback: supabase/rollback/20261123170000_scl370_market_companies_rollback.sql
-- ΕΦΑΡΜΟΣΤΗΚΕ 23/11/2026 (~16:15) μετά από ρητό «ναι». Μετά την εφαρμογή: 0 από 137 υπάρχοντες ορισμούς συναρτήσεων άλλαξαν· οι 16 νέοι ίδιοι με των τοπικών δοκιμών (57/57).
-- Το μητρώο Brands φορτώνεται από τα Κεντρικά (σελίδα Market → Brands → «Ενημέρωση μητρώου»)· δεδομένα δεν υπάρχουν σε αυτό το repo.

-- 0. Αντίγραφα ασφαλείας πριν από την αλλαγή.
CREATE TABLE scl_private.backup_v370_functions AS
 SELECT n.nspname::text AS schema_name, p.proname::text AS fn, pg_get_function_identity_arguments(p.oid) AS args,
        pg_get_functiondef(p.oid) AS definition, now() AS taken_at
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','scl_private') AND p.prokind='f';
CREATE TABLE scl_private.backup_v370_mk_access AS TABLE scl_private.mk_access;
ALTER TABLE scl_private.backup_v370_functions ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.backup_v370_mk_access ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v370_functions,scl_private.backup_v370_mk_access FROM PUBLIC,anon,authenticated;

-- 1. Μητρώο (από τα αρχεία πωλήσεων: ΔΙΚΑΙΟΥΧΟΣ = Brand, ΚΑΤΗΓΟΡΙΑ, ΥΠΟΚΑΤΗΓΟΡΙΑ). «pharmacies» = σε πόσα φαρμακεία εμφανίζεται· μόνο για τα Κεντρικά.
CREATE TABLE scl_private.mk_category(
 id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 name text NOT NULL UNIQUE CHECK(length(name) BETWEEN 1 AND 80));
CREATE TABLE scl_private.mk_subcategory(
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 category_id smallint NOT NULL REFERENCES scl_private.mk_category(id) ON DELETE RESTRICT,
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 120),
 UNIQUE(category_id,name));
CREATE TABLE scl_private.mk_brand(
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 name text NOT NULL UNIQUE CHECK(length(name) BETWEEN 1 AND 120),
 pharmacies integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE scl_private.mk_brand_scope(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 brand_id integer NOT NULL REFERENCES scl_private.mk_brand(id) ON DELETE RESTRICT,
 category_id smallint NOT NULL REFERENCES scl_private.mk_category(id) ON DELETE RESTRICT,
 subcategory_id integer REFERENCES scl_private.mk_subcategory(id) ON DELETE RESTRICT,
 pharmacies integer NOT NULL DEFAULT 0);
CREATE UNIQUE INDEX mk_brand_scope_uq ON scl_private.mk_brand_scope(brand_id,category_id,(coalesce(subcategory_id,0)));

-- 2. Αιτήματα πληροφοριών, εταιρίες, άνθρωποι, Brands εταιρίας.
CREATE TABLE scl_private.mk_info_request(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_name text NOT NULL CHECK(length(company_name) BETWEEN 2 AND 120),
 contact_name text NOT NULL CHECK(length(contact_name) BETWEEN 2 AND 80),
 email text NOT NULL CHECK(length(email) BETWEEN 5 AND 120),
 phone text CHECK(phone IS NULL OR length(phone)<=30),
 brands_text text CHECK(brands_text IS NULL OR length(brands_text)<=300),
 message text CHECK(message IS NULL OR length(message)<=1000),
 status text NOT NULL DEFAULT 'new' CHECK(status IN ('new','done','dismissed')),
 origin text,
 created_at timestamptz NOT NULL DEFAULT now(),
 handled_at timestamptz);
CREATE INDEX mk_info_request_created ON scl_private.mk_info_request(created_at);
CREATE TABLE scl_private.mk_company(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name text NOT NULL CHECK(length(name) BETWEEN 2 AND 120),
 legal_name text CHECK(legal_name IS NULL OR length(legal_name)<=160),
 vat text CHECK(vat IS NULL OR length(vat)<=20),
 tax_office text CHECK(tax_office IS NULL OR length(tax_office)<=80),
 address text CHECK(address IS NULL OR length(address)<=200),
 billing_email text CHECK(billing_email IS NULL OR length(billing_email)<=120),
 notes text CHECK(notes IS NULL OR length(notes)<=1000),
 active boolean NOT NULL DEFAULT true,
 request_id uuid REFERENCES scl_private.mk_info_request(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now());
CREATE UNIQUE INDEX mk_company_name_uq ON scl_private.mk_company(upper(name));
-- Ένας άνθρωπος ανά εταιρία σήμερα (is_primary). Ο πίνακας υπάρχει ώστε αργότερα κάθε άνθρωπος να έχει δικό του σύνδεσμο.
CREATE TABLE scl_private.mk_company_person(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES scl_private.mk_company(id) ON DELETE RESTRICT,
 full_name text NOT NULL CHECK(length(full_name) BETWEEN 2 AND 80),
 email text CHECK(email IS NULL OR length(email)<=120),
 phone text CHECK(phone IS NULL OR length(phone)<=30),
 role text CHECK(role IS NULL OR length(role)<=80),
 is_primary boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now());
CREATE UNIQUE INDEX mk_company_person_primary ON scl_private.mk_company_person(company_id) WHERE is_primary;
-- Ένα Brand ανήκει σε μία εταιρία (brand_id = κλειδί).
CREATE TABLE scl_private.mk_company_brand(
 brand_id integer PRIMARY KEY REFERENCES scl_private.mk_brand(id) ON DELETE RESTRICT,
 company_id uuid NOT NULL REFERENCES scl_private.mk_company(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX mk_company_brand_company ON scl_private.mk_company_brand(company_id);

ALTER TABLE scl_private.mk_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_subcategory ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_brand ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_brand_scope ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_info_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_company ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_company_person ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_company_brand ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.mk_category,scl_private.mk_subcategory,scl_private.mk_brand,scl_private.mk_brand_scope,scl_private.mk_info_request,
 scl_private.mk_company,scl_private.mk_company_person,scl_private.mk_company_brand FROM PUBLIC,anon,authenticated;

-- 3. Η ΜΟΝΗ αλλαγή σε υπάρχον: ο σύνδεσμος Market μπορεί να ανήκει σε εταιρία (και, αργότερα, σε άνθρωπο).
ALTER TABLE scl_private.mk_access
 ADD COLUMN company_id uuid REFERENCES scl_private.mk_company(id) ON DELETE RESTRICT,
 ADD COLUMN person_id uuid REFERENCES scl_private.mk_company_person(id) ON DELETE RESTRICT;
ALTER TABLE scl_private.mk_access DROP CONSTRAINT mk_access_kind_check;
ALTER TABLE scl_private.mk_access ADD CONSTRAINT mk_access_kind_check CHECK(kind IN ('test','company'));
ALTER TABLE scl_private.mk_access ADD CONSTRAINT mk_access_company_check CHECK((kind='company')=(company_id IS NOT NULL));
CREATE INDEX mk_access_company ON scl_private.mk_access(company_id) WHERE company_id IS NOT NULL;

-- 4. Ιδιωτικές συναρτήσεις.
-- Φόρτωση/συμπλήρωση μητρώου. p = {"brands":{"<Brand>":<φαρμακεία>},"combos":[["<Brand>","<Κατηγορία>","<Υποκατηγορία ή κενό>",<φαρμακεία>],...]}
-- Μόνο προσθέτει· ο μετρητής φαρμακείων κρατά το μεγαλύτερο που έχει δει· δεν σβήνει ποτέ.
CREATE FUNCTION scl_private.mk_registry_load(p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 INSERT INTO scl_private.mk_category(name)
  SELECT DISTINCT btrim(e->>1) FROM jsonb_array_elements(p->'combos') e WHERE btrim(coalesce(e->>1,''))<>'' ON CONFLICT(name) DO NOTHING;
 INSERT INTO scl_private.mk_subcategory(category_id,name)
  SELECT DISTINCT c.id, btrim(e->>2) FROM jsonb_array_elements(p->'combos') e JOIN scl_private.mk_category c ON c.name=btrim(e->>1)
  WHERE btrim(coalesce(e->>2,''))<>'' ON CONFLICT(category_id,name) DO NOTHING;
 INSERT INTO scl_private.mk_brand(name,pharmacies)
  SELECT btrim(k), v::integer FROM jsonb_each_text(p->'brands') x(k,v) WHERE btrim(k)<>''
  ON CONFLICT(name) DO UPDATE SET pharmacies=greatest(scl_private.mk_brand.pharmacies,EXCLUDED.pharmacies);
 INSERT INTO scl_private.mk_brand_scope(brand_id,category_id,subcategory_id,pharmacies)
  SELECT b.id,c.id,s.id,max((e->>3)::integer) FROM jsonb_array_elements(p->'combos') e
   JOIN scl_private.mk_brand b ON b.name=btrim(e->>0) JOIN scl_private.mk_category c ON c.name=btrim(e->>1)
   LEFT JOIN scl_private.mk_subcategory s ON s.category_id=c.id AND s.name=btrim(e->>2)
  GROUP BY b.id,c.id,s.id
  ON CONFLICT(brand_id,category_id,(coalesce(subcategory_id,0))) DO UPDATE SET pharmacies=greatest(scl_private.mk_brand_scope.pharmacies,EXCLUDED.pharmacies);
 RETURN jsonb_build_object('brands',(SELECT count(*) FROM scl_private.mk_brand),'categories',(SELECT count(*) FROM scl_private.mk_category),
  'subcategories',(SELECT count(*) FROM scl_private.mk_subcategory),'combos',(SELECT count(*) FROM scl_private.mk_brand_scope));
END $$;

-- Κατηγορίες και υποκατηγορίες ενός Brand. p_counts=true μόνο για τα Κεντρικά.
CREATE FUNCTION scl_private.mk_brand_scopes(p_brand integer, p_counts boolean) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT coalesce(jsonb_agg(x.j ORDER BY x.cname),'[]'::jsonb) FROM (
  SELECT c.name cname, jsonb_build_object('category',c.name,'subcategories',
    coalesce(jsonb_agg(CASE WHEN p_counts THEN jsonb_build_object('name',s.name,'pharmacies',bs.pharmacies) ELSE to_jsonb(s.name) END ORDER BY s.name)
             FILTER(WHERE s.id IS NOT NULL),'[]'::jsonb)) j
  FROM scl_private.mk_brand_scope bs JOIN scl_private.mk_category c ON c.id=bs.category_id
   LEFT JOIN scl_private.mk_subcategory s ON s.id=bs.subcategory_id
  WHERE bs.brand_id=p_brand GROUP BY c.name) x $$;

-- Τα Brands μιας εταιρίας, όπως τα βλέπει η ίδια (χωρίς μετρητές).
CREATE FUNCTION scl_private.mk_company_brands(p_company uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'scopes',scl_private.mk_brand_scopes(b.id,false)) ORDER BY b.name),'[]'::jsonb)
 FROM scl_private.mk_company_brand cb JOIN scl_private.mk_brand b ON b.id=cb.brand_id WHERE cb.company_id=p_company $$;

-- Μια εταιρία όπως τη βλέπουν τα Κεντρικά.
CREATE FUNCTION scl_private.mk_company_hq(p_company uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT jsonb_build_object('id',c.id,'name',c.name,'legal_name',c.legal_name,'vat',c.vat,'tax_office',c.tax_office,'address',c.address,
  'billing_email',c.billing_email,'notes',c.notes,'active',c.active,'created_at',c.created_at,
  'person',(SELECT jsonb_build_object('full_name',p.full_name,'email',p.email,'phone',p.phone,'role',p.role)
            FROM scl_private.mk_company_person p WHERE p.company_id=c.id AND p.is_primary),
  'brands',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name) ORDER BY b.name),'[]'::jsonb)
            FROM scl_private.mk_company_brand cb JOIN scl_private.mk_brand b ON b.id=cb.brand_id WHERE cb.company_id=c.id),
  'link',(SELECT a.token FROM scl_private.mk_access a WHERE a.company_id=c.id AND a.revoked_at IS NULL ORDER BY a.created_at DESC LIMIT 1))
 FROM scl_private.mk_company c WHERE c.id=p_company $$;

CREATE FUNCTION scl_private.mk_txt(p jsonb, k text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO '' AS $$
 SELECT nullif(btrim(regexp_replace(coalesce(p->>k,''),'[[:cntrl:]]+',' ','g')),'') $$;

-- 5. Market (εταιρία).
-- Ποιος είμαι: δοκιμαστικός σύνδεσμος ή εταιρία με τα Brands της.
CREATE FUNCTION public.scl370_mk_me(p_key text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a scl_private.mk_access%ROWTYPE; c scl_private.mk_company%ROWTYPE;
BEGIN
 SELECT * INTO a FROM scl_private.mk_access WHERE id=scl_private.mk_access_id(p_key);
 IF a.kind='test' THEN RETURN jsonb_build_object('kind','test','label',a.label); END IF;
 SELECT * INTO c FROM scl_private.mk_company WHERE id=a.company_id;
 IF c.id IS NULL OR NOT c.active THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Μη έγκυρη πρόσβαση Market'; END IF;
 RETURN jsonb_build_object('kind','company',
  'company',jsonb_build_object('name',c.name,'legal_name',c.legal_name,'vat',c.vat,'tax_office',c.tax_office,'address',c.address,'billing_email',c.billing_email),
  'person',(SELECT jsonb_build_object('full_name',p.full_name,'email',p.email,'phone',p.phone,'role',p.role) FROM scl_private.mk_company_person p
            WHERE p.company_id=c.id AND (p.id=a.person_id OR (a.person_id IS NULL AND p.is_primary)) LIMIT 1),
  'brands',scl_private.mk_company_brands(c.id));
END $$;

-- Αίτημα πληροφοριών (χωρίς σύνδεσμο). Δεν δίνει καμία πρόσβαση. Όριο: 5 ανά ώρα από την ίδια προέλευση, 40 ανά ώρα συνολικά.
CREATE FUNCTION public.scl370_mk_info_request(p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_company text:=scl_private.mk_txt(p,'company_name'); v_name text:=scl_private.mk_txt(p,'contact_name'); v_email text:=lower(scl_private.mk_txt(p,'email'));
 v_phone text:=scl_private.mk_txt(p,'phone'); v_brands text:=scl_private.mk_txt(p,'brands_text'); v_msg text:=nullif(btrim(coalesce(p->>'message','')),''); v_origin text;
BEGIN
 IF scl_private.mk_txt(p,'website') IS NOT NULL THEN RETURN jsonb_build_object('ok',true); END IF;
 IF v_company IS NULL OR length(v_company) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'MARKET_REQUEST:company_name' USING ERRCODE='22023'; END IF;
 IF v_name IS NULL OR length(v_name) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'MARKET_REQUEST:contact_name' USING ERRCODE='22023'; END IF;
 IF v_email IS NULL OR length(v_email)>120 OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' THEN RAISE EXCEPTION 'MARKET_REQUEST:email' USING ERRCODE='22023'; END IF;
 IF length(coalesce(v_phone,''))>30 OR coalesce(v_phone,'0') !~ '^[0-9+() .-]+$' THEN RAISE EXCEPTION 'MARKET_REQUEST:phone' USING ERRCODE='22023'; END IF;
 IF length(coalesce(v_brands,''))>300 THEN RAISE EXCEPTION 'MARKET_REQUEST:brands_text' USING ERRCODE='22023'; END IF;
 IF length(coalesce(v_msg,''))>1000 THEN RAISE EXCEPTION 'MARKET_REQUEST:message' USING ERRCODE='22023'; END IF;
 BEGIN v_origin:=md5(coalesce(split_part(current_setting('request.headers',true)::jsonb->>'x-forwarded-for',',',1),''));
 EXCEPTION WHEN OTHERS THEN v_origin:=md5(''); END;
 IF (SELECT count(*) FROM scl_private.mk_info_request WHERE origin=v_origin AND created_at>now()-interval '1 hour')>=5
  OR (SELECT count(*) FROM scl_private.mk_info_request WHERE created_at>now()-interval '1 hour')>=40 THEN
  RAISE EXCEPTION 'MARKET_REQUEST_RATE' USING ERRCODE='53400'; END IF;
 INSERT INTO scl_private.mk_info_request(company_name,contact_name,email,phone,brands_text,message,origin)
  VALUES(v_company,v_name,v_email,v_phone,v_brands,v_msg,v_origin);
 RETURN jsonb_build_object('ok',true);
END $$;

-- 6. Κεντρικά.
CREATE FUNCTION public.scl370_hq_overview(p_hq_key text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN jsonb_build_object(
  'requests',(SELECT coalesce(jsonb_agg(to_jsonb(q)-'origin' ORDER BY (q.status<>'new'),q.created_at DESC),'[]'::jsonb) FROM (
     SELECT r.*,(SELECT c.id FROM scl_private.mk_company c WHERE c.request_id=r.id LIMIT 1) company_id FROM scl_private.mk_info_request r
     WHERE r.status='new' OR r.created_at>now()-interval '90 days' ORDER BY r.created_at DESC LIMIT 200) q),
  'companies',(SELECT coalesce(jsonb_agg(scl_private.mk_company_hq(c.id) ORDER BY NOT c.active,upper(c.name)),'[]'::jsonb) FROM scl_private.mk_company c),
  'categories',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,
      'brands',(SELECT count(DISTINCT bs.brand_id) FROM scl_private.mk_brand_scope bs WHERE bs.category_id=c.id)) ORDER BY c.name),'[]'::jsonb) FROM scl_private.mk_category c),
  'counts',jsonb_build_object('brands',(SELECT count(*) FROM scl_private.mk_brand),'assigned',(SELECT count(*) FROM scl_private.mk_company_brand),
   'subcategories',(SELECT count(*) FROM scl_private.mk_subcategory),
   'requests_new',(SELECT count(*) FROM scl_private.mk_info_request WHERE status='new'),
   'companies',(SELECT count(*) FROM scl_private.mk_company WHERE active)));
END $$;

-- Αναζήτηση στο μητρώο. p_state: 'all' | 'free' (χωρίς εταιρία) | 'taken'.
CREATE FUNCTION public.scl370_hq_brands(p_hq_key text, p_q text, p_category integer, p_state text, p_limit integer, p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE q text:=upper(btrim(coalesce(p_q,''))); lim integer:=least(greatest(coalesce(p_limit,40),1),100); off integer:=greatest(coalesce(p_offset,0),0); res jsonb;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 WITH m AS (
  SELECT b.id,b.name,b.pharmacies,cb.company_id FROM scl_private.mk_brand b LEFT JOIN scl_private.mk_company_brand cb ON cb.brand_id=b.id
  WHERE (q='' OR position(q IN upper(b.name))>0)
   AND (p_category IS NULL OR EXISTS(SELECT 1 FROM scl_private.mk_brand_scope bs WHERE bs.brand_id=b.id AND bs.category_id=p_category))
   AND (coalesce(p_state,'all')='all' OR (p_state='free' AND cb.company_id IS NULL) OR (p_state='taken' AND cb.company_id IS NOT NULL)))
 SELECT jsonb_build_object('total',(SELECT count(*) FROM m),'rows',coalesce((SELECT jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'pharmacies',x.pharmacies,
   'categories',(SELECT coalesce(jsonb_agg(DISTINCT c.name),'[]'::jsonb) FROM scl_private.mk_brand_scope bs JOIN scl_private.mk_category c ON c.id=bs.category_id WHERE bs.brand_id=x.id),
   'company',(SELECT jsonb_build_object('id',c.id,'name',c.name) FROM scl_private.mk_company c WHERE c.id=x.company_id)) ORDER BY x.rn)
   FROM (SELECT m.*,row_number() OVER(ORDER BY (q<>'' AND upper(m.name) LIKE q||'%') DESC, m.pharmacies DESC, m.name) rn FROM m
         ORDER BY rn LIMIT lim OFFSET off) x),'[]'::jsonb)) INTO res;
 RETURN res;
END $$;

CREATE FUNCTION public.scl370_hq_brand(p_hq_key text, p_brand_id integer) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN (SELECT jsonb_build_object('id',b.id,'name',b.name,'pharmacies',b.pharmacies,'scopes',scl_private.mk_brand_scopes(b.id,true),
  'company',(SELECT jsonb_build_object('id',c.id,'name',c.name) FROM scl_private.mk_company_brand cb JOIN scl_private.mk_company c ON c.id=cb.company_id WHERE cb.brand_id=b.id))
  FROM scl_private.mk_brand b WHERE b.id=p_brand_id);
END $$;

-- Δημιουργία ή διόρθωση εταιρίας. p = {id?, name, legal_name, vat, tax_office, address, billing_email, notes, person:{full_name,email,phone,role}, request_id?}
CREATE FUNCTION public.scl370_hq_company_save(p_hq_key text, p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
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

-- Ανάθεση / αφαίρεση Brands. Ένα Brand που έχει άλλη εταιρία δεν αλλάζει χέρια σιωπηλά.
CREATE FUNCTION public.scl370_hq_company_brands(p_hq_key text, p_company_id uuid, p_add integer[], p_remove integer[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE other text;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF NOT EXISTS(SELECT 1 FROM scl_private.mk_company WHERE id=p_company_id) THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 DELETE FROM scl_private.mk_company_brand WHERE company_id=p_company_id AND brand_id=ANY(coalesce(p_remove,'{}'));
 SELECT b.name||' → '||c.name INTO other FROM scl_private.mk_company_brand cb JOIN scl_private.mk_company c ON c.id=cb.company_id
  JOIN scl_private.mk_brand b ON b.id=cb.brand_id WHERE cb.brand_id=ANY(coalesce(p_add,'{}')) AND cb.company_id<>p_company_id LIMIT 1;
 IF other IS NOT NULL THEN RAISE EXCEPTION 'MARKET_BRAND_TAKEN:%',other USING ERRCODE='23505'; END IF;
 INSERT INTO scl_private.mk_company_brand(brand_id,company_id)
  SELECT b.id,p_company_id FROM scl_private.mk_brand b WHERE b.id=ANY(coalesce(p_add,'{}')) ON CONFLICT(brand_id) DO NOTHING;
 RETURN scl_private.mk_company_hq(p_company_id);
END $$;

-- Σύνδεσμος εταιρίας. p_renew=true: ο παλιός σταματά και βγαίνει νέος.
CREATE FUNCTION public.scl370_hq_company_link(p_hq_key text, p_company_id uuid, p_renew boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE c scl_private.mk_company%ROWTYPE;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT * INTO c FROM scl_private.mk_company WHERE id=p_company_id;
 IF c.id IS NULL THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF NOT c.active THEN RAISE EXCEPTION 'MARKET_COMPANY_INACTIVE' USING ERRCODE='22023'; END IF;
 IF coalesce(p_renew,false) THEN UPDATE scl_private.mk_access SET revoked_at=now() WHERE company_id=c.id AND revoked_at IS NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM scl_private.mk_access WHERE company_id=c.id AND revoked_at IS NULL) THEN
  INSERT INTO scl_private.mk_access(label,kind,company_id) VALUES(left(c.name,80),'company',c.id); END IF;
 RETURN scl_private.mk_company_hq(c.id);
END $$;

-- Απενεργοποίηση: ο σύνδεσμος σταματά αμέσως. Επανενεργοποίηση: χρειάζεται νέος σύνδεσμος.
CREATE FUNCTION public.scl370_hq_company_active(p_hq_key text, p_company_id uuid, p_active boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 UPDATE scl_private.mk_company SET active=coalesce(p_active,false),updated_at=now() WHERE id=p_company_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF NOT coalesce(p_active,false) THEN UPDATE scl_private.mk_access SET revoked_at=now() WHERE company_id=p_company_id AND revoked_at IS NULL; END IF;
 RETURN scl_private.mk_company_hq(p_company_id);
END $$;

CREATE FUNCTION public.scl370_hq_request_set(p_hq_key text, p_id uuid, p_status text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_status NOT IN ('new','done','dismissed') THEN RAISE EXCEPTION 'MARKET_REQUEST:status' USING ERRCODE='22023'; END IF;
 UPDATE scl_private.mk_info_request SET status=p_status,handled_at=CASE WHEN p_status='new' THEN NULL ELSE now() END WHERE id=p_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'MARKET_REQUEST_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('ok',true);
END $$;

-- Ενημέρωση μητρώου από τα Κεντρικά (αρχείο μητρώου ή αρχεία πωλήσεων που διαβάζει ο browser· στέλνονται μόνο ονόματα και μετρητές, ποτέ ποσά).
CREATE FUNCTION public.scl370_hq_registry_load(p_hq_key text, p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF jsonb_typeof(p->'brands')<>'object' OR jsonb_typeof(p->'combos')<>'array' OR jsonb_array_length(p->'combos')>60000
  OR (SELECT count(*) FROM jsonb_object_keys(p->'brands'))>20000
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p->'combos') e WHERE jsonb_typeof(e)<>'array' OR jsonb_array_length(e)<4 OR length(coalesce(e->>0,''))>120 OR length(coalesce(e->>1,''))>80
            OR length(coalesce(e->>2,''))>120 OR coalesce(e->>3,'') !~ '^[0-9]{1,4}$')
  OR EXISTS(SELECT 1 FROM jsonb_each_text(p->'brands') x(k,v) WHERE length(k)>120 OR v !~ '^[0-9]{1,4}$') THEN
  RAISE EXCEPTION 'MARKET_REGISTRY_FORMAT' USING ERRCODE='22023'; END IF;
 RETURN scl_private.mk_registry_load(p);
END $$;

-- 7. Δικαιώματα.
REVOKE ALL ON FUNCTION scl_private.mk_registry_load(jsonb),scl_private.mk_brand_scopes(integer,boolean),scl_private.mk_company_brands(uuid),
 scl_private.mk_company_hq(uuid),scl_private.mk_txt(jsonb,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.scl370_mk_me(text),public.scl370_mk_info_request(jsonb),public.scl370_hq_overview(text),
 public.scl370_hq_brands(text,text,integer,text,integer,integer),public.scl370_hq_brand(text,integer),public.scl370_hq_company_save(text,jsonb),
 public.scl370_hq_company_brands(text,uuid,integer[],integer[]),public.scl370_hq_company_link(text,uuid,boolean),
 public.scl370_hq_company_active(text,uuid,boolean),public.scl370_hq_request_set(text,uuid,text),public.scl370_hq_registry_load(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl370_mk_me(text),public.scl370_mk_info_request(jsonb),public.scl370_hq_overview(text),
 public.scl370_hq_brands(text,text,integer,text,integer,integer),public.scl370_hq_brand(text,integer),public.scl370_hq_company_save(text,jsonb),
 public.scl370_hq_company_brands(text,uuid,integer[],integer[]),public.scl370_hq_company_link(text,uuid,boolean),
 public.scl370_hq_company_active(text,uuid,boolean),public.scl370_hq_request_set(text,uuid,text),public.scl370_hq_registry_load(text,jsonb) TO anon,authenticated;
