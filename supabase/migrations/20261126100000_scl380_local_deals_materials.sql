-- scl380 · Κ3γ τοπικές συμφωνίες με τη λογική του Market
-- Αρίθμηση υλικών ανά προμηθευτή και μήνα · αναζήτηση Brand από το φαρμακείο · «Από φαρμακεία» · «Στάλθηκε το όνομα»
-- MIX για 2+ Brands στο Market · όροι Market έκδοση 3 με «προμηθευτής».
-- Μόνο προσθήκες· η μόνη αλλαγή σε υπάρχουσα συνάρτηση είναι η mk_req_json (κωδικός Brand = MIX όταν τα Brands είναι 2+).

CREATE TABLE IF NOT EXISTS scl_private.backup_v380_functions(name text PRIMARY KEY, def text NOT NULL, saved_at timestamptz NOT NULL DEFAULT now());
INSERT INTO scl_private.backup_v380_functions(name,def)
SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p
WHERE p.oid IN ('scl_private.mk_req_json(scl_private.mk_request,text)'::regprocedure)
ON CONFLICT(name) DO NOTHING;

-- Υλικά με όνομα αρχείου: ένα όνομα δεν δίνεται ποτέ δεύτερη φορά.
CREATE TABLE scl_private.material_file(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 pharmacy_id uuid NOT NULL,
 year integer NOT NULL,
 position_id text NOT NULL,
 deal_id text NOT NULL,
 grp integer NOT NULL CHECK (grp BETWEEN 0 AND 11),
 first_month integer NOT NULL CHECK (first_month BETWEEN 0 AND 11),
 supplier_code text NOT NULL CHECK (supplier_code ~ '^[A-Z0-9]{2,20}$'),
 brand_code text NOT NULL CHECK (brand_code ~ '^[A-Z0-9]{2,20}$'),
 ym text NOT NULL CHECK (ym ~ '^(0[1-9]|1[0-2])_[0-9]{4}$'),
 seq integer NOT NULL CHECK (seq BETWEEN 1 AND 99),
 file_base text NOT NULL UNIQUE,
 kind text NOT NULL CHECK (kind IN ('local','market')),
 request_id uuid,
 replaced_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(supplier_code,ym,seq)
);
CREATE UNIQUE INDEX material_file_live ON scl_private.material_file(pharmacy_id,year,deal_id,grp) WHERE replaced_at IS NULL;
CREATE INDEX material_file_ph ON scl_private.material_file(pharmacy_id,year);

-- Πότε και πώς στάλθηκε το όνομα αρχείου στον προμηθευτή (τοπικές συμφωνίες).
CREATE TABLE scl_private.material_sent(
 pharmacy_id uuid NOT NULL,
 year integer NOT NULL,
 deal_id text NOT NULL,
 how text NOT NULL CHECK (how IN ('email','pdf','other')),
 by_name text,
 at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(pharmacy_id,year,deal_id)
);

-- Προμηθευτές και Brands που έγραψε φαρμακείο με το χέρι (μόνο με οριστική συμφωνία).
CREATE TABLE scl_private.ph_registry_pending(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 kind text NOT NULL CHECK (kind IN ('supplier','brand')),
 name text NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
 code text NOT NULL,
 supplier_name text,
 brand_names text[],
 pharmacy_id uuid NOT NULL,
 year integer NOT NULL,
 deal_id text NOT NULL,
 position_id text,
 months integer[],
 status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','added','matched','dismissed')),
 company_id uuid,
 brand_id integer,
 resolved_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(kind,pharmacy_id,year,deal_id,name)
);

ALTER TABLE scl_private.material_file ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.material_sent ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.ph_registry_pending ENABLE ROW LEVEL SECURITY;

-- Κωδικός από την πρώτη λέξη (για νέο προμηθευτή).
CREATE OR REPLACE FUNCTION scl_private.k3c_first_code(p text)
 RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $function$
 SELECT CASE WHEN length(c)>=2 THEN c ELSE left(scl_private.mk_code_from(p),20) END
 FROM (SELECT left(scl_private.mk_code_from(split_part(btrim(coalesce(p,'')),' ',1)),20) c) x;
$function$;

-- Αναζήτηση Brand από το φαρμακείο: μόνο όνομα, κωδικός, προμηθευτής του μητρώου, κατηγορίες/υποκατηγορίες.
CREATE OR REPLACE FUNCTION public.scl380_ph_brand_search(p_token text, p_q text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE q text:=btrim(coalesce(p_q,''));
BEGIN
 PERFORM public.scl290_token_id(p_token);
 IF length(q)<2 OR length(q)>60 THEN RETURN '[]'::jsonb; END IF;
 RETURN coalesce((SELECT jsonb_agg(x.j ORDER BY x.rn) FROM (
  SELECT jsonb_build_object('id',b.id,'name',b.name,'code',b.code,
    'supplier',(SELECT jsonb_build_object('id',c.id,'name',c.name,'code',c.code,'test',c.is_test) FROM scl_private.mk_company_brand cb JOIN scl_private.mk_company c ON c.id=cb.company_id WHERE cb.brand_id=b.id ORDER BY c.is_test LIMIT 1),
    'scopes',scl_private.mk_brand_scopes(b.id,false)) j,
   row_number() OVER(ORDER BY (upper(b.name) LIKE upper(q)||'%') DESC, b.pharmacies DESC, b.name) rn
  FROM scl_private.mk_brand b WHERE position(upper(q) IN upper(b.name))>0 ORDER BY rn LIMIT 12) x),'[]'::jsonb);
END $function$;

-- Brands του ίδιου προμηθευτή (για «+ Brand του ίδιου προμηθευτή»).
CREATE OR REPLACE FUNCTION public.scl380_ph_supplier_brands(p_token text, p_company_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_token_id(p_token);
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'code',b.code,'scopes',scl_private.mk_brand_scopes(b.id,false)) ORDER BY b.name)
  FROM scl_private.mk_company_brand cb JOIN scl_private.mk_brand b ON b.id=cb.brand_id JOIN scl_private.mk_company c ON c.id=cb.company_id
  WHERE cb.company_id=p_company_id),'[]'::jsonb);
END $function$;

-- Προτεινόμενος κωδικός για νέο προμηθευτή.
CREATE OR REPLACE FUNCTION public.scl380_ph_supplier_code(p_token text, p_name text)
 RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_token_id(p_token);
 RETURN nullif(scl_private.k3c_first_code(p_name),'');
END $function$;

-- Δέσμευση ονομάτων αρχείων: καλείται λίγο πριν αποθηκευτεί οριστική συμφωνία (τοπική ή «Δέχομαι»).
-- p_items: [{grp, first_month, supplier_code, brand_code}]   p_meta: {kind, request_id, supplier:{name,new}, brands:[names], brand_free:[names], months:[...]}
CREATE OR REPLACE FUNCTION public.scl380_ph_reserve(p_token text, p_year integer, p_position_id text, p_deal_id text, p_items jsonb, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token); it jsonb; g integer; fm integer; sc text; bc text; v_ym text; cur scl_private.material_file; n integer; base text; out jsonb:='[]'; k text:=coalesce(p_meta->>'kind','local'); nm text;
BEGIN
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 OR nullif(btrim(coalesce(p_deal_id,'')),'') IS NULL OR length(p_deal_id)>80 THEN RAISE EXCEPTION 'K3C:bad_request' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.scl290_installations i, jsonb_array_elements(i.positions) p WHERE i.pharmacy_id=pid AND p->>'id'=p_position_id) THEN RAISE EXCEPTION 'K3C:position' USING ERRCODE='22023'; END IF;
 IF k NOT IN ('local','market') OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'K3C:bad_request' USING ERRCODE='22023'; END IF;
 FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  g:=(it->>'grp')::integer; fm:=(it->>'first_month')::integer; sc:=upper(coalesce(it->>'supplier_code','')); bc:=upper(coalesce(it->>'brand_code',''));
  IF g IS NULL OR g NOT BETWEEN 0 AND 11 OR fm IS NULL OR fm NOT BETWEEN 0 AND 11 OR sc !~ '^[A-Z0-9]{2,20}$' OR bc !~ '^[A-Z0-9]{2,20}$' THEN RAISE EXCEPTION 'K3C:bad_item' USING ERRCODE='22023'; END IF;
  v_ym:=lpad((fm+1)::text,2,'0')||'_'||p_year;
  SELECT * INTO cur FROM scl_private.material_file WHERE pharmacy_id=pid AND year=p_year AND deal_id=p_deal_id AND grp=g AND replaced_at IS NULL FOR UPDATE;
  IF cur.id IS NOT NULL AND cur.supplier_code=sc AND cur.brand_code=bc THEN
   out:=out||jsonb_build_array(jsonb_build_object('grp',g,'base',cur.file_base,'new',false)); CONTINUE;
  END IF;
  IF cur.id IS NOT NULL THEN UPDATE scl_private.material_file SET replaced_at=now() WHERE id=cur.id; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('scl380:'||sc||':'||v_ym));
  SELECT coalesce(max(seq),0)+1 INTO n FROM scl_private.material_file WHERE supplier_code=sc AND ym=v_ym;
  IF n>99 THEN RAISE EXCEPTION 'K3C:full' USING ERRCODE='22023'; END IF;
  base:=v_ym||'_'||sc||'_'||bc||'_'||lpad(n::text,2,'0');
  INSERT INTO scl_private.material_file(pharmacy_id,year,position_id,deal_id,grp,first_month,supplier_code,brand_code,ym,seq,file_base,kind,request_id)
  VALUES(pid,p_year,p_position_id,p_deal_id,g,fm,sc,bc,v_ym,n,base,k,nullif(p_meta->>'request_id','')::uuid);
  out:=out||jsonb_build_array(jsonb_build_object('grp',g,'base',base,'new',true));
 END LOOP;
 -- Νέος προμηθευτής / Brand με το χέρι → «Από φαρμακεία» (μόνο για τοπικές, μόνο τώρα που γίνεται οριστική).
 IF k='local' THEN
  nm:=nullif(btrim(coalesce(p_meta#>>'{supplier,name}','')),'');
  IF nm IS NOT NULL AND (p_meta#>>'{supplier,new}')='true' THEN
   INSERT INTO scl_private.ph_registry_pending(kind,name,code,supplier_name,brand_names,pharmacy_id,year,deal_id,position_id,months)
   VALUES('supplier',left(nm,120),scl_private.k3c_first_code(nm),nm,ARRAY(SELECT jsonb_array_elements_text(coalesce(p_meta->'brands','[]'))),pid,p_year,p_deal_id,p_position_id,ARRAY(SELECT jsonb_array_elements_text(coalesce(p_meta->'months','[]')))::integer[])
   ON CONFLICT DO NOTHING;
  END IF;
  FOR nm IN SELECT btrim(value) FROM jsonb_array_elements_text(coalesce(p_meta->'brand_free','[]')) WHERE btrim(value)<>'' LOOP
   INSERT INTO scl_private.ph_registry_pending(kind,name,code,supplier_name,brand_names,pharmacy_id,year,deal_id,position_id,months)
   VALUES('brand',left(nm,120),scl_private.mk_code_from(nm),nullif(btrim(coalesce(p_meta#>>'{supplier,name}','')),''),ARRAY[nm],pid,p_year,p_deal_id,p_position_id,ARRAY(SELECT jsonb_array_elements_text(coalesce(p_meta->'months','[]')))::integer[])
   ON CONFLICT DO NOTHING;
  END LOOP;
 END IF;
 RETURN jsonb_build_object('ok',true,'files',out);
END $function$;

-- Φύλακας: μια συμφωνία με νέο όνομα αρχείου μπορεί να έχει μόνο ονόματα που δεσμεύτηκαν για αυτό το φαρμακείο.
CREATE OR REPLACE FUNCTION scl_private.material_guard()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE bad text;
BEGIN
 SELECT f->>'base' INTO bad
 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(NEW.state_json->'cards')='array' THEN NEW.state_json->'cards' ELSE '[]'::jsonb END) c
 CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(c->'confirmedDeals')='array' THEN c->'confirmedDeals' ELSE '[]'::jsonb END) d
 CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(d#>'{k3,files}')='array' THEN d#>'{k3,files}' ELSE '[]'::jsonb END) f
 WHERE NOT EXISTS(SELECT 1 FROM scl_private.material_file m WHERE m.pharmacy_id=NEW.pharmacy_id AND m.file_base=f->>'base')
 LIMIT 1;
 IF bad IS NOT NULL THEN RAISE EXCEPTION 'MATERIAL_NAME: Το όνομα αρχείου % δεν έχει δοθεί σε αυτό το φαρμακείο', bad; END IF;
 RETURN NEW;
END $function$;
CREATE TRIGGER scl380_material_guard BEFORE INSERT OR UPDATE ON public.scl290_snapshots FOR EACH ROW EXECUTE FUNCTION scl_private.material_guard();

-- «Στάλθηκε το όνομα»
CREATE OR REPLACE FUNCTION public.scl380_ph_mark_sent(p_token text, p_year integer, p_deal_id text, p_how text, p_person text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token);
BEGIN
 IF p_how NOT IN ('email','pdf','other') THEN RAISE EXCEPTION 'K3C:how' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM scl_private.material_file WHERE pharmacy_id=pid AND year=p_year AND deal_id=p_deal_id AND replaced_at IS NULL) THEN RAISE EXCEPTION 'K3C:not_found' USING ERRCODE='P0002'; END IF;
 INSERT INTO scl_private.material_sent(pharmacy_id,year,deal_id,how,by_name) VALUES(pid,p_year,p_deal_id,p_how,left(nullif(btrim(coalesce(p_person,'')),''),160))
 ON CONFLICT(pharmacy_id,year,deal_id) DO UPDATE SET how=excluded.how,by_name=excluded.by_name,at=now();
 RETURN jsonb_build_object('ok',true);
END $function$;

-- Τα ονόματα αρχείων του φαρμακείου και αν στάλθηκαν (Αρχική, παράθυρο αποστολής).
CREATE OR REPLACE FUNCTION public.scl380_ph_materials(p_token text, p_year integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token);
BEGIN
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('deal_id',m.deal_id,'position_id',m.position_id,'grp',m.grp,'first_month',m.first_month,'base',m.file_base,'kind',m.kind,
   'sent',CASE WHEN s.deal_id IS NOT NULL THEN jsonb_build_object('how',s.how,'by',s.by_name,'at',s.at) END) ORDER BY m.first_month,m.position_id,m.grp)
  FROM scl_private.material_file m LEFT JOIN scl_private.material_sent s ON s.pharmacy_id=m.pharmacy_id AND s.year=m.year AND s.deal_id=m.deal_id
  WHERE m.pharmacy_id=pid AND m.year=p_year AND m.replaced_at IS NULL),'[]'::jsonb);
END $function$;

-- Κεντρικά: όλα τα υλικά με όνομα και η κατάστασή τους.
CREATE OR REPLACE FUNCTION public.scl380_hq_materials(p_hq_key text, p_year integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('pharmacy_id',m.pharmacy_id,'pharmacy',g.name,'pharmacy_code',g.pharmacy_code,'position_id',m.position_id,'deal_id',m.deal_id,'grp',m.grp,
   'first_month',m.first_month,'base',m.file_base,'kind',m.kind,'supplier_code',m.supplier_code,'brand_code',m.brand_code,'created_at',m.created_at,
   'sent',CASE WHEN s.deal_id IS NOT NULL THEN jsonb_build_object('how',s.how,'by',s.by_name,'at',s.at) END) ORDER BY m.first_month,g.name,m.position_id)
  FROM scl_private.material_file m JOIN public.scl290_registry g ON g.pharmacy_id=m.pharmacy_id
  LEFT JOIN scl_private.material_sent s ON s.pharmacy_id=m.pharmacy_id AND s.year=m.year AND s.deal_id=m.deal_id
  WHERE m.year=p_year AND m.replaced_at IS NULL),'[]'::jsonb);
END $function$;

-- Κεντρικά: «Από φαρμακεία».
CREATE OR REPLACE FUNCTION public.scl380_hq_pending(p_hq_key text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN jsonb_build_object(
  'open',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'kind',p.kind,'name',p.name,'code',p.code,'supplier_name',p.supplier_name,'brand_names',to_jsonb(p.brand_names),
    'pharmacy',g.name,'position_id',p.position_id,'year',p.year,'months',to_jsonb(p.months),'created_at',p.created_at,
    'suggest',CASE WHEN p.kind='brand' THEN (SELECT jsonb_build_object('id',b.id,'name',b.name,'code',b.code) FROM scl_private.mk_brand b WHERE upper(b.name)=upper(split_part(p.name,' ',1)) OR position(upper(b.name) IN upper(p.name))=1 ORDER BY length(b.name) DESC LIMIT 1)
      ELSE (SELECT jsonb_build_object('id',c.id,'name',c.name,'code',c.code) FROM scl_private.mk_company c WHERE NOT c.is_test AND (c.code=p.code OR upper(c.name)=upper(p.name)) LIMIT 1) END)
   ORDER BY p.created_at) FROM scl_private.ph_registry_pending p JOIN public.scl290_registry g ON g.pharmacy_id=p.pharmacy_id WHERE p.status='open'),'[]'::jsonb),
  'count',(SELECT count(*) FROM scl_private.ph_registry_pending WHERE status='open'));
END $function$;

-- Κεντρικά: πρόσθεσε στο μητρώο / ίδιο με υπάρχον / απόρριψη.
CREATE OR REPLACE FUNCTION public.scl380_hq_pending_resolve(p_hq_key text, p_id uuid, p_action text, p_target text DEFAULT NULL, p_code text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r scl_private.ph_registry_pending%ROWTYPE; cid uuid; bid integer; v text:=upper(btrim(coalesce(p_code,'')));
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT * INTO r FROM scl_private.ph_registry_pending WHERE id=p_id FOR UPDATE;
 IF r.id IS NULL OR r.status<>'open' THEN RAISE EXCEPTION 'K3C:not_found' USING ERRCODE='P0002'; END IF;
 IF p_action='dismiss' THEN
  UPDATE scl_private.ph_registry_pending SET status='dismissed',resolved_at=now() WHERE id=r.id;
 ELSIF p_action='match' AND r.kind='supplier' THEN
  SELECT id INTO cid FROM scl_private.mk_company WHERE id::text=p_target; IF cid IS NULL THEN RAISE EXCEPTION 'K3C:not_found' USING ERRCODE='P0002'; END IF;
  UPDATE scl_private.ph_registry_pending SET status='matched',company_id=cid,resolved_at=now() WHERE id=r.id;
 ELSIF p_action='match' AND r.kind='brand' THEN
  SELECT id INTO bid FROM scl_private.mk_brand WHERE id::text=p_target; IF bid IS NULL THEN RAISE EXCEPTION 'K3C:not_found' USING ERRCODE='P0002'; END IF;
  UPDATE scl_private.ph_registry_pending SET status='matched',brand_id=bid,resolved_at=now() WHERE id=r.id;
 ELSIF p_action='add' AND r.kind='supplier' THEN
  IF v='' THEN v:=r.code; END IF;
  IF v !~ '^[A-Z0-9]{2,20}$' THEN RAISE EXCEPTION 'MARKET_CODE:format' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM scl_private.mk_company WHERE code=v) THEN RAISE EXCEPTION 'MARKET_CODE:taken' USING ERRCODE='23505'; END IF;
  INSERT INTO scl_private.mk_company(name,code,active,notes) VALUES(r.name,v,false,'Από φαρμακείο (τοπική συμφωνία)') RETURNING id INTO cid;
  UPDATE scl_private.ph_registry_pending SET status='added',company_id=cid,resolved_at=now() WHERE id=r.id;
 ELSIF p_action='add' AND r.kind='brand' THEN
  IF v='' THEN v:=r.code; END IF;
  IF v !~ '^[A-Z0-9]{2,20}$' THEN RAISE EXCEPTION 'MARKET_CODE:format' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM scl_private.mk_brand WHERE code=v) THEN RAISE EXCEPTION 'MARKET_CODE:taken' USING ERRCODE='23505'; END IF;
  INSERT INTO scl_private.mk_brand(name,code) VALUES(upper(r.name),v) RETURNING id INTO bid;
  UPDATE scl_private.ph_registry_pending SET status='added',brand_id=bid,resolved_at=now() WHERE id=r.id;
 ELSE RAISE EXCEPTION 'K3C:action' USING ERRCODE='22023'; END IF;
 RETURN public.scl380_hq_pending(p_hq_key);
END $function$;

-- MIX για 2+ Brands στο Market (μία γραμμή: ο κωδικός Brand).
CREATE OR REPLACE FUNCTION scl_private.mk_req_json(r scl_private.mk_request, p_side text)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 WITH f AS (SELECT scl_private.price_at('deal','ADV',make_date(r.year,(SELECT min(m) FROM unnest(r.months) m)+1,1)) fd,
                   scl_private.price_at('market_fee','ADV',make_date(r.year,(SELECT min(m) FROM unnest(r.months) m)+1,1)) fm,
                   scl_private.mk_req_themes(r) th)
 SELECT jsonb_build_object('id',r.id,'no',scl_private.mk_req_label(r.no,r.created_at),'status',r.status,'reason',r.reason,
   'company',r.company_name,'sender',r.person_name,
   'pharmacy',jsonb_build_object('id',r.registry_id,'name',r.pharmacy_name,'area',(SELECT g.area FROM public.scl290_registry g WHERE g.id=r.registry_id)),
   'position',jsonb_build_object('id',r.position_id,'title',r.position_title,'format',r.format),
   'year',r.year,'months',to_jsonb(r.months),'brands',to_jsonb(r.brand_names),'theme',r.theme,'same_theme',r.same_theme,'message',r.message,
   'categories',to_jsonb(r.categories),'subcategories',to_jsonb(r.subcategories),
   'price_month',r.price_month,'total',r.price_month*cardinality(r.months),'plans',r.plans,
   'terms',jsonb_build_object('version',r.terms_company,'company',scl_private.mk_terms_items('company',r.terms_company,false),
     'pharmacy_version',r.terms_pharmacy,'pharmacy',scl_private.mk_terms_items('pharmacy',r.terms_pharmacy,false)),
   'created_at',r.created_at,'answer_by',r.answer_by,'days_left',CASE WHEN r.status='pending' THEN r.answer_by-scl_private.today() END,
   'closed_at',r.closed_at,'is_test',r.is_test,
   'codes',jsonb_build_object('company',(SELECT c.code FROM scl_private.mk_company c WHERE c.id=r.company_id),
     'brand',CASE WHEN cardinality(r.brand_ids)>1 THEN 'MIX' ELSE (SELECT b.code FROM scl_private.mk_brand b WHERE b.id=r.brand_ids[1]) END),
   'accepted_by',r.accepted_by,'cancelled_months',to_jsonb(r.cancelled_months),
   'cancel_ask',CASE WHEN r.cancel_asked_at IS NOT NULL THEN jsonb_build_object('at',r.cancel_asked_at,'note',r.cancel_ask_note,'by',r.cancel_ask_by) END,
   'locked_months',(SELECT coalesce(jsonb_agg(m ORDER BY m),'[]'::jsonb) FROM unnest(r.months) m WHERE scl_private.today()>scl_private.cutoff(r.year,m)),
   'files',(SELECT coalesce(jsonb_agg(m.file_base ORDER BY m.grp),'[]'::jsonb) FROM scl_private.material_file m WHERE m.request_id=r.id AND m.replaced_at IS NULL))
  ||CASE WHEN p_side IN ('pharmacy','hq') THEN jsonb_build_object('seen_pharmacy_at',r.seen_pharmacy_at) ELSE '{}'::jsonb END
  ||CASE WHEN p_side='hq' THEN jsonb_build_object('hq_note',r.hq_note,'seen_company_at',r.seen_company_at,'deal_id',r.deal_id,'cancelled_by',r.cancelled_by,
      'pharmacy_code',(SELECT g.pharmacy_code FROM public.scl290_registry g WHERE g.id=r.registry_id)) ELSE '{}'::jsonb END
  ||CASE WHEN p_side='pharmacy' THEN jsonb_build_object('hq_note',CASE WHEN r.reason='hq' OR r.cancelled_months IS NOT NULL THEN r.hq_note END) ELSE '{}'::jsonb END
  ||CASE WHEN p_side='company' THEN jsonb_build_object('seen_company_at',r.seen_company_at) ELSE '{}'::jsonb END
  ||CASE WHEN p_side IN ('pharmacy','hq') THEN jsonb_build_object(
      'terms',jsonb_build_object('version',r.terms_company,'company',scl_private.mk_terms_items('company',r.terms_company,false),
        'pharmacy_version',r.terms_pharmacy,'pharmacy',scl_private.mk_terms_items('pharmacy',r.terms_pharmacy,true),
        'pharmacy_public',scl_private.mk_terms_items('pharmacy',r.terms_pharmacy,false)),
      'charge',(SELECT jsonb_build_object('themes',f.th,'deal',f.fd,'market',f.fm,'total',(f.fd+f.fm)*f.th,
        'net',r.price_month*cardinality(r.months)-(f.fd+f.fm)*f.th) FROM f)) ELSE '{}'::jsonb END
$function$;

-- Όροι Market έκδοση 3: «προμηθευτής» αντί για «εταιρία». Τα αιτήματα που στάλθηκαν κρατούν την έκδοσή τους.
INSERT INTO scl_private.mk_terms(side,version,items)
SELECT 'company',3,jsonb_build_array(
 jsonb_build_object('t','Ζητάτε την οθόνη της θέσης μαζί με όλα τα ράφια της, για τους μήνες και στην τιμή που αναγράφονται.'),
 jsonb_build_object('t','Αν το φαρμακείο δεχτεί, είναι οριστική συμφωνία ανάμεσα σε εσάς και στο φαρμακείο.'),
 jsonb_build_object('t','Πληρώνετε το φαρμακείο απευθείας, στο τέλος κάθε μήνα προβολής, με τιμολόγιο του φαρμακείου. Οι τιμές είναι προ ΦΠΑ.'),
 jsonb_build_object('t','Παραδίδετε το υλικό έως τις 15 του προηγούμενου μήνα. Αν δεν το παραδώσετε, παίζει το βασικό πρόγραμμα του φαρμακείου και πληρώνετε κανονικά.'),
 jsonb_build_object('t','Το πλανόγραμμα του αιτήματος είναι μέρος της συμφωνίας. Φροντίζετε να υπάρχουν τα προϊόντα στο φαρμακείο πριν από την έναρξη.'),
 jsonb_build_object('t','Το φαρμακείο ανεβάζει φωτογραφία του στησίματος για κάθε μήνα προβολής. Η φωτογραφία είναι μέρος της συμφωνίας και το αποδεικτικό ότι η προβολή στήθηκε. Τη βλέπετε εδώ μόλις την εγκρίνει το φαρμακείο.'),
 jsonb_build_object('t','Μπορείτε να αποσύρετε το αίτημα όσο περιμένει απάντηση. Μετά την αποδοχή, ακύρωση γίνεται μόνο μέσω της Pharmaplus.'),
 jsonb_build_object('t','Η Pharmaplus είναι ενδιάμεσος και δεν είναι μέρος της συμφωνίας.'))
WHERE NOT EXISTS(SELECT 1 FROM scl_private.mk_terms WHERE side='company' AND version=3);
INSERT INTO scl_private.mk_terms(side,version,items)
SELECT 'pharmacy',3,jsonb_build_array(
 jsonb_build_object('t','Δίνεις την οθόνη της θέσης μαζί με όλα τα ράφια της στον προμηθευτή, για τους μήνες και στην τιμή που αναγράφονται.'),
 jsonb_build_object('t','Η αποδοχή είναι οριστική συμφωνία. Ακύρωση γίνεται μόνο μέσω των Κεντρικών.'),
 jsonb_build_object('t','Τιμολογείς τον προμηθευτή στο τέλος κάθε μήνα προβολής και εισπράττεις απευθείας από αυτόν.'),
 jsonb_build_object('t','Στήνεις τα ράφια της θέσης με το πλανόγραμμα του αιτήματος που ταιριάζει στη θέση σου, για όλη τη διάρκεια.'),
 jsonb_build_object('t','Για κάθε μήνα προβολής ανεβάζεις φωτογραφία του στησίματος: από κοντά, μόνο η οθόνη και τα ράφια της. Η φωτογραφία είναι μέρος της συμφωνίας. Την ελέγχεις και την εγκρίνεις εσύ, και τότε τη βλέπει ο προμηθευτής. Αν δεν ανεβάσεις φωτογραφία, ο προμηθευτής μπορεί να τη ζητήσει πριν πληρώσει.'),
 jsonb_build_object('t','Απαντάς σε 7 ημέρες, το αργότερο έως τις 15 του προηγούμενου μήνα. Αλλιώς το αίτημα λήγει.'),
 jsonb_build_object('t','Χρεώνεσαι από την Pharmaplus 30 € ανά θέμα για τη συμφωνία και 10 € ανά θέμα επειδή έκλεισε μέσω Market.','audience','pharmacy'))
WHERE NOT EXISTS(SELECT 1 FROM scl_private.mk_terms WHERE side='pharmacy' AND version=3);

REVOKE ALL ON FUNCTION public.scl380_ph_brand_search(text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl380_ph_supplier_brands(text,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl380_ph_supplier_code(text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl380_ph_reserve(text,integer,text,text,jsonb,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl380_ph_mark_sent(text,integer,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl380_ph_materials(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl380_hq_materials(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl380_hq_pending(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl380_hq_pending_resolve(text,uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl380_ph_brand_search(text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl380_ph_supplier_brands(text,uuid) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl380_ph_supplier_code(text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl380_ph_reserve(text,integer,text,text,jsonb,jsonb) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl380_ph_mark_sent(text,integer,text,text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl380_ph_materials(text,integer) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl380_hq_materials(text,integer) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl380_hq_pending(text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl380_hq_pending_resolve(text,uuid,text,text,text) TO anon,authenticated;
