-- scl379 · Κ3β «Δέχομαι» και ακύρωση · Χρέωση Market 10 € · κωδικοί εταιρίας/Brand
-- 25/11/2026. Μόνο προσθήκες, εκτός από τις αλλαγές που σημειώνονται «ΑΛΛΑΓΗ».
-- Δεν αλλάζουν: scl290_save_program, blocks, snapshot_guard, deadline_guard, month_signature, financial_rows_v304.

-- 0. Αντίγραφο των συναρτήσεων που αλλάζουν
CREATE TABLE IF NOT EXISTS scl_private.backup_v379_functions(name text PRIMARY KEY, def text NOT NULL, saved_at timestamptz NOT NULL DEFAULT now());
INSERT INTO scl_private.backup_v379_functions(name,def)
SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p
WHERE p.oid IN ('scl_private.capture_charges(uuid,integer,jsonb,bigint)'::regprocedure,
 'scl_private.financial_rows(uuid,integer)'::regprocedure,
 'scl_private.price_at(text,text,date)'::regprocedure,
 'public.scl3284_price_list(text,text)'::regprocedure,
 'public.scl3284_set_prices(text,date,jsonb)'::regprocedure,
 'scl_private.mk_req_json(scl_private.mk_request,text)'::regprocedure,
 'scl_private.mk_request_guard()'::regprocedure,
 'public.scl374_hq_requests(text)'::regprocedure,
 'public.scl304_materials(text,integer)'::regprocedure)
ON CONFLICT(name) DO NOTHING;

-- 1. Τιμοκατάλογος: Χρέωση Market 10 €
ALTER TABLE scl_private.price_list DROP CONSTRAINT price_list_item_check;
ALTER TABLE scl_private.price_list ADD CONSTRAINT price_list_item_check
 CHECK (item = ANY (ARRAY['platform','base_program','extra_position','free_changes','extra_change','deal','market_fee']));
INSERT INTO scl_private.price_list(item,category,amount,valid_from)
SELECT 'market_fee',c,10,'2000-01-01' FROM unnest(ARRAY['ADV','PROMO','EXP']) c
WHERE NOT EXISTS(SELECT 1 FROM scl_private.price_list WHERE item='market_fee' AND category=c);

-- ΑΛΛΑΓΗ: προεπιλογή 10 για market_fee
CREATE OR REPLACE FUNCTION scl_private.price_at(p_item text, p_category text, p_on date)
 RETURNS numeric LANGUAGE sql STABLE SET search_path TO ''
AS $function$
 SELECT coalesce(
  (SELECT amount FROM scl_private.price_list WHERE item=p_item AND category IS NOT DISTINCT FROM p_category AND valid_from<=p_on ORDER BY valid_from DESC LIMIT 1),
  CASE p_item WHEN 'platform' THEN 365 WHEN 'base_program' THEN 120 WHEN 'extra_position' THEN 8 WHEN 'free_changes' THEN 3 WHEN 'extra_change' THEN 15 WHEN 'deal' THEN 30 WHEN 'market_fee' THEN 10 END);
$function$;

-- ΑΛΛΑΓΗ: η τρέχουσα τιμή market_fee στην απάντηση
CREATE OR REPLACE FUNCTION public.scl3284_price_list(p_token text DEFAULT NULL::text, p_hq_key text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE td date:=scl_private.today(); cur jsonb; items jsonb;
BEGIN
 IF p_hq_key IS NOT NULL THEN PERFORM public.scl290_assert_hq(p_hq_key); ELSE PERFORM public.scl290_token_id(p_token); END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'item',item,'category',category,'amount',amount,'valid_from',valid_from)
   ORDER BY CASE item WHEN 'platform' THEN 1 WHEN 'base_program' THEN 2 WHEN 'extra_position' THEN 3 WHEN 'free_changes' THEN 4 WHEN 'extra_change' THEN 5 WHEN 'deal' THEN 6 ELSE 7 END, category NULLS FIRST, valid_from),'[]') INTO items FROM scl_private.price_list;
 cur:=jsonb_build_object(
  'platform',scl_private.price_at('platform',NULL,td),
  'base_program',scl_private.price_at('base_program',NULL,td),
  'ADV',jsonb_build_object('extra_position',scl_private.price_at('extra_position','ADV',td),'free_changes',scl_private.price_at('free_changes','ADV',td),'extra_change',scl_private.price_at('extra_change','ADV',td),'deal',scl_private.price_at('deal','ADV',td),'market_fee',scl_private.price_at('market_fee','ADV',td)),
  'PROMO',jsonb_build_object('extra_position',scl_private.price_at('extra_position','PROMO',td),'free_changes',scl_private.price_at('free_changes','PROMO',td),'extra_change',scl_private.price_at('extra_change','PROMO',td),'deal',scl_private.price_at('deal','PROMO',td),'market_fee',scl_private.price_at('market_fee','PROMO',td)),
  'EXP',jsonb_build_object('extra_position',scl_private.price_at('extra_position','EXP',td),'free_changes',scl_private.price_at('free_changes','EXP',td),'extra_change',scl_private.price_at('extra_change','EXP',td),'deal',scl_private.price_at('deal','EXP',td),'market_fee',scl_private.price_at('market_fee','EXP',td)));
 RETURN jsonb_build_object('as_of',td,'first_selectable',scl_private.price_first_selectable(),'current',cur,'items',items);
END $function$;

-- ΑΛΛΑΓΗ: τα Κεντρικά αλλάζουν και τη Χρέωση Market
CREATE OR REPLACE FUNCTION public.scl3284_set_prices(p_hq_key text, p_from date, p_items jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE it jsonb; v_item text; v_cat text; v_amt numeric; v_first date; cnt integer:=0; cur numeric; ex uuid;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 PERFORM pg_advisory_xact_lock(hashtext('scl3284_prices'));
 v_first:=scl_private.price_first_selectable();
 IF p_from IS NULL OR extract(day FROM p_from)<>1 THEN RAISE EXCEPTION 'Επίλεξε μήνα έναρξης ισχύος'; END IF;
 IF p_from<v_first THEN RAISE EXCEPTION 'Η νέα τιμή μπορεί να ισχύσει μόνο από μήνα που δεν έχει χρεωθεί ακόμα (από % και μετά)',to_char(v_first,'MM/YYYY'); END IF;
 IF p_from>v_first+interval '5 years' THEN RAISE EXCEPTION 'Η ημερομηνία έναρξης είναι πολύ μακριά'; END IF;
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 OR jsonb_array_length(p_items)>24 THEN RAISE EXCEPTION 'Δεν υπάρχουν τιμές για αποθήκευση'; END IF;
 FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  IF jsonb_typeof(it)<>'object' THEN RAISE EXCEPTION 'Μη έγκυρη τιμή'; END IF;
  v_item:=it->>'item'; v_cat:=nullif(it->>'category','');
  IF v_item IS NULL OR v_item NOT IN ('platform','base_program','extra_position','free_changes','extra_change','deal','market_fee') THEN RAISE EXCEPTION 'Άγνωστο είδος τιμής'; END IF;
  IF v_item IN ('platform','base_program') THEN
   IF v_cat IS NOT NULL THEN RAISE EXCEPTION 'Το πάγιο δεν έχει κατηγορία'; END IF;
  ELSE
   IF v_cat IS NULL OR v_cat NOT IN ('ADV','PROMO','EXP') THEN RAISE EXCEPTION 'Ορίστε κατηγορία ADV, PROMO ή EXP'; END IF;
   IF v_cat='EXP' AND v_item IN ('free_changes','extra_change') THEN RAISE EXCEPTION 'Το EXP δεν έχει αλλαγές εξατομίκευσης'; END IF;
  END IF;
  IF jsonb_typeof(it->'amount')<>'number' THEN RAISE EXCEPTION 'Ορίστε αριθμητική τιμή'; END IF;
  v_amt:=(it->>'amount')::numeric;
  IF v_amt<0 OR v_amt>100000 OR v_amt<>round(v_amt,2) THEN RAISE EXCEPTION 'Η τιμή πρέπει να είναι από 0 έως 100000 με έως 2 δεκαδικά'; END IF;
  IF v_item='free_changes' AND (v_amt<>trunc(v_amt) OR v_amt>12) THEN RAISE EXCEPTION 'Οι δωρεάν αλλαγές είναι ακέραιος αριθμός από 0 έως 12'; END IF;
  SELECT id INTO ex FROM scl_private.price_list WHERE item=v_item AND category IS NOT DISTINCT FROM v_cat AND valid_from=p_from;
  IF ex IS NOT NULL THEN
   UPDATE scl_private.price_list SET amount=v_amt WHERE id=ex; cnt:=cnt+1;
  ELSE
   cur:=scl_private.price_at(v_item,v_cat,p_from);
   IF cur IS DISTINCT FROM v_amt THEN
    INSERT INTO scl_private.price_list(item,category,amount,valid_from) VALUES(v_item,v_cat,v_amt,p_from); cnt:=cnt+1;
   END IF;
  END IF;
 END LOOP;
 RETURN public.scl3284_price_list(NULL,p_hq_key)||jsonb_build_object('saved',cnt);
END $function$;

-- 2. Χρεώσεις Market: ίδια κομμάτια με τα 30 €, κλειδί 'market:'+κλειδί κομματιού, κατηγορία 'market'
ALTER TABLE public.scl292_charge_events DROP CONSTRAINT scl292_charge_events_category_check;
ALTER TABLE public.scl292_charge_events ADD CONSTRAINT scl292_charge_events_category_check
 CHECK (category = ANY (ARRAY['custom','deal','report','market']));

-- Τα κομμάτια χρέωσης των συμφωνιών Market (ίδιο κλειδί με τη scl_private.blocks)
CREATE OR REPLACE FUNCTION scl_private.market_blocks(p_year integer, p_state jsonb)
 RETURNS TABLE(position_id text, position_name text, category text, start_month integer, end_month integer, description text, event_key text)
 LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $function$
 SELECT b.* FROM scl_private.blocks(p_year,jsonb_build_object('cards',(
  SELECT coalesce(jsonb_agg(c||jsonb_build_object('simpleConfirmed',false,'negotiation','{}'::jsonb,'confirmedDeals',
   coalesce((SELECT jsonb_agg(d) FROM jsonb_array_elements(CASE WHEN jsonb_typeof(c->'confirmedDeals')='array' THEN c->'confirmedDeals' ELSE '[]'::jsonb END) d
             WHERE jsonb_typeof(d->'market')='object' AND nullif(d->>'id','') IS NOT NULL),'[]'::jsonb))),'[]'::jsonb)
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state->'cards')='array' THEN p_state->'cards' ELSE '[]'::jsonb END) c))) b
 WHERE b.category='deal';
$function$;

CREATE OR REPLACE FUNCTION scl_private.capture_market_charges(p_pid uuid, p_year integer, p_state jsonb, p_revision bigint)
 RETURNS void LANGUAGE plpgsql SET search_path TO ''
AS $function$
DECLARE b record; d date; cat text;
BEGIN
 FOR b IN SELECT * FROM scl_private.market_blocks(p_year,p_state) ORDER BY position_id,start_month LOOP
  IF scl_private.today()<=scl_private.cutoff(p_year,b.start_month) THEN CONTINUE; END IF;
  d:=make_date(p_year,b.start_month+1,1);
  cat:=CASE WHEN b.position_id LIKE 'promo-%' THEN 'PROMO' WHEN b.position_id LIKE 'exp-%' THEN 'EXP' ELSE 'ADV' END;
  INSERT INTO public.scl292_charge_events(pharmacy_id,year,position_id,position_name,category,event_key,start_month,end_month,description,amount,quota_index,source_revision)
  VALUES(p_pid,p_year,b.position_id,b.position_name,'market','market:'||b.event_key,b.start_month,b.end_month,'Χρέωση Market · '||b.description,
   scl_private.price_at('market_fee',cat,d),NULL,p_revision) ON CONFLICT DO NOTHING;
 END LOOP;
END $function$;

-- ΑΛΛΑΓΗ: μία γραμμή στο τέλος, γράφει και τα 10 € τη στιγμή που γράφονται τα 30 €
CREATE OR REPLACE FUNCTION scl_private.capture_charges(p_pid uuid, p_year integer, p_state jsonb, p_revision bigint)
 RETURNS void LANGUAGE plpgsql SET search_path TO ''
AS $function$
DECLARE b record; q integer; d date; cat text;
BEGIN
 FOR b IN SELECT * FROM scl_private.blocks(p_year,p_state) ORDER BY position_id,start_month,category LOOP
 IF scl_private.today()<=scl_private.cutoff(p_year,b.start_month) THEN CONTINUE; END IF;
 IF EXISTS(SELECT 1 FROM public.scl292_charge_events e WHERE e.pharmacy_id=p_pid AND e.year=p_year AND e.event_key=b.event_key) THEN CONTINUE; END IF;
 q:=NULL;
 IF b.category='custom' THEN SELECT coalesce(max(quota_index),0)+1 INTO q FROM public.scl292_charge_events WHERE pharmacy_id=p_pid AND year=p_year AND position_id=b.position_id AND category='custom'; END IF;
 d:=make_date(p_year,b.start_month+1,1);
 cat:=CASE WHEN b.position_id LIKE 'promo-%' THEN 'PROMO' WHEN b.position_id LIKE 'exp-%' THEN 'EXP' ELSE 'ADV' END;
 INSERT INTO public.scl292_charge_events(pharmacy_id,year,position_id,position_name,category,event_key,start_month,end_month,description,amount,quota_index,source_revision)
 VALUES(p_pid,p_year,b.position_id,b.position_name,b.category,b.event_key,b.start_month,b.end_month,b.description,
 CASE WHEN b.category='deal' THEN scl_private.price_at('deal',cat,d) WHEN q<=scl_private.price_at('free_changes',cat,d) THEN 0 ELSE scl_private.price_at('extra_change',cat,d) END,q,p_revision) ON CONFLICT DO NOTHING;
 END LOOP;
 PERFORM scl_private.capture_market_charges(p_pid,p_year,p_state,p_revision);
END $function$;

-- Προγραμματισμένες χρεώσεις Market (πριν τη 15η του προηγούμενου μήνα)
CREATE OR REPLACE FUNCTION scl_private.market_planned_rows(p_pid uuid, p_year integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO ''
AS $function$
DECLARE st jsonb; rows jsonb:='[]'; b record; bd date; cat text;
BEGIN
 SELECT s.state_json INTO st FROM public.scl290_snapshots s WHERE s.pharmacy_id=p_pid AND s.year=p_year;
 IF st IS NULL THEN RETURN rows; END IF;
 FOR b IN SELECT * FROM scl_private.market_blocks(p_year,st) ORDER BY position_id,start_month LOOP
  IF EXISTS(SELECT 1 FROM public.scl292_charge_events e WHERE e.pharmacy_id=p_pid AND e.year=p_year AND e.event_key='market:'||b.event_key) THEN CONTINUE; END IF;
  bd:=make_date(p_year,b.start_month+1,1);
  cat:=CASE WHEN b.position_id LIKE 'promo-%' THEN 'PROMO' WHEN b.position_id LIKE 'exp-%' THEN 'EXP' ELSE 'ADV' END;
  rows:=rows||jsonb_build_array(jsonb_build_object('id','planned:market:'||b.event_key,'pharmacy_id',p_pid,'year',p_year,
   'position_id',b.position_id,'position_name',b.position_name,'category','market','start_month',b.start_month,'end_month',b.end_month,
   'description','Χρέωση Market · '||b.description,'event_key','market:'||b.event_key,'month',b.start_month,'status','planned','quota_index',NULL,
   'amount',scl_private.price_at('market_fee',cat,bd)));
 END LOOP;
 RETURN rows;
END $function$;

-- ΑΛΛΑΓΗ: η πρώτη γραμμή γίνεται «υπάρχουσες γραμμές + προγραμματισμένες γραμμές Market»
CREATE OR REPLACE FUNCTION scl_private.financial_rows(p_pid uuid, p_year integer)
 RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''
AS $function$
DECLARE raw jsonb;out_rows jsonb:='[]';r jsonb;original jsonb;history jsonb;k text;seen text[]:='{}';a record;credited numeric;cancelled boolean;rev bigint;live_status text;
BEGIN
 raw:=scl_private.financial_rows_v304(p_pid,p_year)||scl_private.market_planned_rows(p_pid,p_year);
 -- Keep the original entry even if the programme later no longer produces it.
 FOR a IN SELECT DISTINCT ON(source_key) source_key,original_row FROM scl_private.charge_adjustments WHERE pharmacy_id=p_pid AND year=p_year ORDER BY source_key,revision LOOP
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(raw) v WHERE scl_private.charge_identity(v)=a.source_key) THEN raw:=raw||jsonb_build_array(a.original_row);END IF;
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements(raw) LOOP
  live_status:=r->>'status';k:=scl_private.charge_identity(r);IF k=ANY(seen) THEN CONTINUE;END IF;seen:=array_append(seen,k);
  SELECT original_row INTO original FROM scl_private.charge_adjustments WHERE pharmacy_id=p_pid AND year=p_year AND source_key=k ORDER BY revision LIMIT 1;
  IF original IS NOT NULL THEN r:=original;END IF;
  SELECT coalesce(sum(amount) FILTER(WHERE kind='credit'),0),coalesce(bool_or(kind='cancel'),false),coalesce(max(revision),0),coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'amount',amount,'reason',reason,'created_at',created_at) ORDER BY revision),'[]')
   INTO credited,cancelled,rev,history FROM scl_private.charge_adjustments WHERE pharmacy_id=p_pid AND year=p_year AND source_key=k;
  r:=r||jsonb_build_object('source_key',k,'source_status',live_status,'entry_type','charge','original_status',r->>'status','status',CASE WHEN cancelled THEN 'cancelled' ELSE r->>'status' END,'adjustment_revision',rev,'credited_amount',credited,'remaining_credit',greatest(0,(r->>'amount')::numeric-credited),'adjustments',history);
  out_rows:=out_rows||jsonb_build_array(r);
  FOR a IN SELECT * FROM scl_private.charge_adjustments WHERE pharmacy_id=p_pid AND year=p_year AND source_key=k AND kind='credit' ORDER BY revision LOOP
   out_rows:=out_rows||jsonb_build_array((r-'adjustments')||jsonb_build_object('id','credit:'||a.id,'entry_type','credit','source_id',r->>'id','amount',-a.amount,'description','Πίστωση: '||a.reason,'status','finalized','quota_index',NULL,'created_at',a.created_at,'remaining_credit',0));
  END LOOP;
 END LOOP;
 RETURN out_rows;
END $function$;

-- 3. Κωδικοί εταιρίας και Brand (για το όνομα αρχείου 2027_04_ΕΤΑΙΡΙΑ_BRAND_01_PORTRAIT)
CREATE OR REPLACE FUNCTION scl_private.mk_code_from(p text)
 RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $function$
 SELECT left(regexp_replace(translate(
  replace(replace(replace(replace(replace(replace(upper(coalesce(p,'')),'Θ','TH'),'Χ','CH'),'Ψ','PS'),'Ξ','KS'),'&','AND'),'+','PLUS'),
  'ΑΆΒΓΔΕΈΖΗΉΙΊΪΐΚΛΜΝΟΌΠΡΣΤΥΎΫΰΦΩΏÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÇÑ',
  'AABGDEEZIIIIIIKLMNOOPRSTYYYYFOOAAAAAEEEEIIIIOOOOOUUUUCN'),'[^A-Z0-9]','','g'),20);
$function$;

ALTER TABLE scl_private.mk_company ADD COLUMN IF NOT EXISTS code text;
ALTER TABLE scl_private.mk_brand ADD COLUMN IF NOT EXISTS code text;

CREATE OR REPLACE FUNCTION scl_private.mk_code_unique(p_kind text, p_name text, p_self text DEFAULT NULL)
 RETURNS text LANGUAGE plpgsql STABLE SET search_path TO ''
AS $function$
DECLARE base text:=scl_private.mk_code_from(p_name); c text; n integer:=1;
BEGIN
 IF base IS NULL OR length(base)<2 THEN base:=CASE WHEN p_kind='company' THEN 'CO' ELSE 'BR' END||coalesce(base,''); END IF;
 c:=base;
 LOOP
  IF p_kind='company' AND NOT EXISTS(SELECT 1 FROM scl_private.mk_company x WHERE x.code=c AND x.id::text IS DISTINCT FROM p_self) THEN RETURN c; END IF;
  IF p_kind='brand' AND NOT EXISTS(SELECT 1 FROM scl_private.mk_brand x WHERE x.code=c AND x.id::text IS DISTINCT FROM p_self) THEN RETURN c; END IF;
  n:=n+1; c:=left(base,20-length(n::text))||n;
 END LOOP;
END $function$;

DO $do$
DECLARE r record;
BEGIN
 FOR r IN SELECT id,name FROM scl_private.mk_company WHERE code IS NULL ORDER BY created_at,id LOOP
  UPDATE scl_private.mk_company SET code=scl_private.mk_code_unique('company',r.name,r.id::text) WHERE id=r.id;
 END LOOP;
 FOR r IN SELECT id,name FROM scl_private.mk_brand WHERE code IS NULL ORDER BY id LOOP
  UPDATE scl_private.mk_brand SET code=scl_private.mk_code_unique('brand',r.name,r.id::text) WHERE id=r.id;
 END LOOP;
END $do$;

ALTER TABLE scl_private.mk_company ALTER COLUMN code SET NOT NULL;
ALTER TABLE scl_private.mk_brand ALTER COLUMN code SET NOT NULL;
ALTER TABLE scl_private.mk_company ADD CONSTRAINT mk_company_code_key UNIQUE(code);
ALTER TABLE scl_private.mk_brand ADD CONSTRAINT mk_brand_code_key UNIQUE(code);
ALTER TABLE scl_private.mk_company ADD CONSTRAINT mk_company_code_check CHECK (code ~ '^[A-Z0-9]{2,20}$');
ALTER TABLE scl_private.mk_brand ADD CONSTRAINT mk_brand_code_check CHECK (code ~ '^[A-Z0-9]{2,20}$');

CREATE OR REPLACE FUNCTION scl_private.mk_code_default()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
 IF NEW.code IS NULL OR NEW.code='' THEN
  NEW.code:=scl_private.mk_code_unique(CASE TG_TABLE_NAME WHEN 'mk_company' THEN 'company' ELSE 'brand' END,NEW.name,NEW.id::text);
 END IF;
 RETURN NEW;
END $function$;
CREATE TRIGGER mk_company_code BEFORE INSERT ON scl_private.mk_company FOR EACH ROW EXECUTE FUNCTION scl_private.mk_code_default();
CREATE TRIGGER mk_brand_code BEFORE INSERT ON scl_private.mk_brand FOR EACH ROW EXECUTE FUNCTION scl_private.mk_code_default();

-- Τα Κεντρικά βλέπουν και διορθώνουν τους κωδικούς
CREATE OR REPLACE FUNCTION public.scl379_hq_codes(p_hq_key text, p_company_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN jsonb_build_object('company',(SELECT jsonb_build_object('id',c.id,'name',c.name,'code',c.code) FROM scl_private.mk_company c WHERE c.id=p_company_id),
  'brands',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'code',b.code) ORDER BY b.name),'[]'::jsonb)
            FROM scl_private.mk_brand b JOIN scl_private.mk_company_brand cb ON cb.brand_id=b.id WHERE cb.company_id=p_company_id));
END $function$;

CREATE OR REPLACE FUNCTION public.scl379_hq_set_code(p_hq_key text, p_kind text, p_id text, p_code text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v text:=upper(btrim(coalesce(p_code,''))); n integer;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF v !~ '^[A-Z0-9]{2,20}$' THEN RAISE EXCEPTION 'MARKET_CODE:format' USING ERRCODE='22023'; END IF;
 IF p_kind='company' THEN
  IF EXISTS(SELECT 1 FROM scl_private.mk_company WHERE code=v AND id::text<>p_id) THEN RAISE EXCEPTION 'MARKET_CODE:taken' USING ERRCODE='23505'; END IF;
  UPDATE scl_private.mk_company SET code=v,updated_at=now() WHERE id::text=p_id; GET DIAGNOSTICS n=ROW_COUNT;
 ELSIF p_kind='brand' THEN
  IF EXISTS(SELECT 1 FROM scl_private.mk_brand WHERE code=v AND id::text<>p_id) THEN RAISE EXCEPTION 'MARKET_CODE:taken' USING ERRCODE='23505'; END IF;
  UPDATE scl_private.mk_brand SET code=v WHERE id::text=p_id; GET DIAGNOSTICS n=ROW_COUNT;
 ELSE RAISE EXCEPTION 'MARKET_CODE:kind' USING ERRCODE='22023'; END IF;
 IF n=0 THEN RAISE EXCEPTION 'MARKET_CODE:not_found' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('ok',true,'code',v);
END $function$;

-- 4. Αίτημα: συνεχόμενοι μήνες, Δέχομαι, ακύρωση, «η εταιρία ζητά ακύρωση»
ALTER TABLE scl_private.mk_request
 ADD COLUMN IF NOT EXISTS accepted_by text,
 ADD COLUMN IF NOT EXISTS deal_id text,
 ADD COLUMN IF NOT EXISTS prior_months jsonb,
 ADD COLUMN IF NOT EXISTS cancelled_months integer[],
 ADD COLUMN IF NOT EXISTS cancelled_by text,
 ADD COLUMN IF NOT EXISTS cancel_asked_at timestamptz,
 ADD COLUMN IF NOT EXISTS cancel_ask_note text,
 ADD COLUMN IF NOT EXISTS cancel_ask_by text;
ALTER TABLE scl_private.mk_request ADD CONSTRAINT mk_request_cancel_ask_note_check CHECK (cancel_ask_note IS NULL OR length(cancel_ask_note)<=300);

ALTER TABLE scl_private.mk_request_log DROP CONSTRAINT mk_request_log_action_check;
ALTER TABLE scl_private.mk_request_log ADD CONSTRAINT mk_request_log_action_check CHECK (action = ANY (ARRAY['sent','seen','declined','expired','withdrawn','cancelled','answer_seen','accepted','partly_cancelled','cancel_asked','cancel_ask_declined']));

-- Ένα αίτημα = συνεχόμενοι μήνες (απόφαση 24/11)
CREATE OR REPLACE FUNCTION scl_private.mk_request_months_guard()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
 IF (SELECT max(m)-min(m)+1 FROM unnest(NEW.months) m)<>(SELECT count(DISTINCT m) FROM unnest(NEW.months) m)
    OR (SELECT count(*) FROM unnest(NEW.months) m)<>(SELECT count(DISTINCT m) FROM unnest(NEW.months) m) THEN
  RAISE EXCEPTION 'MARKET_REQ:months_gap' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END $function$;
CREATE TRIGGER mk_request_months BEFORE INSERT ON scl_private.mk_request FOR EACH ROW EXECUTE FUNCTION scl_private.mk_request_months_guard();

-- ΑΛΛΑΓΗ: «Δέχτηκε» → «Ακυρώθηκε» επιτρέπεται (μόνο από τα Κεντρικά, μέσω scl379_hq_deal_cancel)
CREATE OR REPLACE FUNCTION scl_private.mk_request_guard()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
 IF TG_OP='DELETE' THEN
  IF NOT OLD.is_test THEN RAISE EXCEPTION 'MARKET_REQ:immutable' USING ERRCODE='42501'; END IF;
  RETURN OLD;
 END IF;
 IF (NEW.id,NEW.no,NEW.company_id,NEW.company_name,NEW.person_name,NEW.registry_id,NEW.pharmacy_name,NEW.position_id,NEW.position_title,NEW.format,NEW.year,
     NEW.months,NEW.brand_ids,NEW.brand_names,NEW.categories,NEW.subcategories,NEW.theme,NEW.same_theme,NEW.message,NEW.price_month,NEW.plans,NEW.terms_company,NEW.terms_pharmacy,NEW.fee_deal,NEW.fee_market,NEW.answer_by,NEW.is_test,NEW.created_at)
    IS DISTINCT FROM
    (OLD.id,OLD.no,OLD.company_id,OLD.company_name,OLD.person_name,OLD.registry_id,OLD.pharmacy_name,OLD.position_id,OLD.position_title,OLD.format,OLD.year,
     OLD.months,OLD.brand_ids,OLD.brand_names,OLD.categories,OLD.subcategories,OLD.theme,OLD.same_theme,OLD.message,OLD.price_month,OLD.plans,OLD.terms_company,OLD.terms_pharmacy,OLD.fee_deal,OLD.fee_market,OLD.answer_by,OLD.is_test,OLD.created_at)
 THEN RAISE EXCEPTION 'MARKET_REQ:immutable' USING ERRCODE='42501'; END IF;
 IF OLD.status<>'pending' AND NEW.status IS DISTINCT FROM OLD.status
    AND NOT (OLD.status='accepted' AND NEW.status='cancelled' AND current_setting('scl379.market_write',true)='yes') THEN
  RAISE EXCEPTION 'MARKET_REQ:immutable' USING ERRCODE='42501'; END IF;
 IF (NEW.accepted_by,NEW.deal_id,NEW.prior_months) IS DISTINCT FROM (OLD.accepted_by,OLD.deal_id,OLD.prior_months)
    AND current_setting('scl379.market_write',true) IS DISTINCT FROM 'yes' THEN
  RAISE EXCEPTION 'MARKET_REQ:immutable' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $function$;

-- Ο αριθμός θεμάτων = κομμάτια χρέωσης (ίδιο θέμα = 1, αλλιώς κάθε αλλαγή πλανογράμματος σε συνεχόμενους μήνες)
CREATE OR REPLACE FUNCTION scl_private.mk_plan_index(p_plans jsonb, p_month integer)
 RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $function$
 SELECT min(i::integer)-1 FROM jsonb_array_elements(coalesce(p_plans,'[]')) WITH ORDINALITY a(e,i) WHERE (e->'months') @> to_jsonb(p_month);
$function$;

CREATE OR REPLACE FUNCTION scl_private.mk_req_themes(r scl_private.mk_request)
 RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $function$
 SELECT CASE WHEN r.same_theme THEN 1 ELSE (
  SELECT count(*)::integer FROM (SELECT m,scl_private.mk_plan_index(r.plans,m) p,lag(scl_private.mk_plan_index(r.plans,m)) OVER (ORDER BY m) lp,lag(m) OVER (ORDER BY m) lm FROM unnest(r.months) m) x
  WHERE lp IS NULL OR lp<>p OR lm<>m-1) END;
$function$;

-- ΑΛΛΑΓΗ: χρέωση από τον τιμοκατάλογο (30 + 10 του πρώτου μήνα), θέματα όπως τα κομμάτια χρέωσης,
-- κωδικοί για το όνομα αρχείου, ποιος δέχτηκε, ακύρωση και αίτημα ακύρωσης.
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
   -- η εταιρία βλέπει και τι αναλαμβάνει το φαρμακείο, ΧΩΡΙΣ τον όρο της χρέωσής του (audience=pharmacy)
   'terms',jsonb_build_object('version',r.terms_company,'company',scl_private.mk_terms_items('company',r.terms_company,false),
     'pharmacy_version',r.terms_pharmacy,'pharmacy',scl_private.mk_terms_items('pharmacy',r.terms_pharmacy,false)),
   'created_at',r.created_at,'answer_by',r.answer_by,'days_left',CASE WHEN r.status='pending' THEN r.answer_by-scl_private.today() END,
   'closed_at',r.closed_at,'is_test',r.is_test,
   'codes',jsonb_build_object('company',(SELECT c.code FROM scl_private.mk_company c WHERE c.id=r.company_id),
     'brand',(SELECT b.code FROM scl_private.mk_brand b WHERE b.id=r.brand_ids[1])),
   'accepted_by',r.accepted_by,'cancelled_months',to_jsonb(r.cancelled_months),
   'cancel_ask',CASE WHEN r.cancel_asked_at IS NOT NULL THEN jsonb_build_object('at',r.cancel_asked_at,'note',r.cancel_ask_note,'by',r.cancel_ask_by) END,
   'locked_months',(SELECT coalesce(jsonb_agg(m ORDER BY m),'[]'::jsonb) FROM unnest(r.months) m WHERE scl_private.today()>scl_private.cutoff(r.year,m)))
  -- Απόφαση 24/11: η εταιρία ΔΕΝ μαθαίνει αν το φαρμακείο άνοιξε το αίτημα.
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

-- Συμφωνίες Market: μόνο τα «Δέχομαι» και η ακύρωση των Κεντρικών τις προσθέτουν, αλλάζουν ή αφαιρούν.
CREATE OR REPLACE FUNCTION scl_private.market_deal_sig(d jsonb)
 RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $function$
 SELECT jsonb_build_object('id',d->'id','startMonth',d->'startMonth','duration',d->'duration','supplier',d->'supplier','brand',d->'brand','subline',d->'subline',
  'products',d->'products','soldMonthlyPrice',d->'soldMonthlyPrice','confirmed',d->'confirmed','monthlyContentChanges',d->'monthlyContentChanges',
  'schedule',d->'schedule','monthlySublines',d->'monthlySublines','monthlyProducts',d->'monthlyProducts','market',d->'market');
$function$;

CREATE OR REPLACE FUNCTION scl_private.market_deals(p_state jsonb)
 RETURNS TABLE(position_id text, deal jsonb) LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $function$
 SELECT c->>'id',d FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state->'cards')='array' THEN p_state->'cards' ELSE '[]'::jsonb END) c
 CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(c->'confirmedDeals')='array' THEN c->'confirmedDeals' ELSE '[]'::jsonb END) d
 WHERE jsonb_typeof(d)='object' AND jsonb_typeof(d->'market')='object';
$function$;

CREATE OR REPLACE FUNCTION scl_private.market_guard()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE a jsonb; b jsonb; prev jsonb;
BEGIN
 IF current_setting('scl379.market_write',true)='yes' THEN RETURN NEW; END IF;
 -- INSERT … ON CONFLICT DO UPDATE περνά πρώτα από το BEFORE INSERT: συγκρίνουμε με τη γραμμή που υπάρχει ήδη.
 IF TG_OP='UPDATE' THEN prev:=OLD.state_json;
 ELSE SELECT s.state_json INTO prev FROM public.scl290_snapshots s WHERE s.pharmacy_id=NEW.pharmacy_id AND s.year=NEW.year; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('p',position_id,'d',scl_private.market_deal_sig(deal)) ORDER BY position_id,deal->>'id'),'[]') INTO a
  FROM scl_private.market_deals(coalesce(prev,'{}'::jsonb));
 SELECT coalesce(jsonb_agg(jsonb_build_object('p',position_id,'d',scl_private.market_deal_sig(deal)) ORDER BY position_id,deal->>'id'),'[]') INTO b
  FROM scl_private.market_deals(NEW.state_json);
 IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'MARKET_DEAL_LOCKED: Η συμφωνία μέσω Market αλλάζει ή ακυρώνεται μόνο από τα Κεντρικά'; END IF;
 RETURN NEW;
END $function$;
CREATE TRIGGER scl379_market_guard BEFORE INSERT OR UPDATE ON public.scl290_snapshots FOR EACH ROW EXECUTE FUNCTION scl_private.market_guard();

-- 4α. «Δέχομαι»: μία συναλλαγή = αποθήκευση προγράμματος (υπάρχουσα scl290_save_program) + «Δέχτηκε»
CREATE OR REPLACE FUNCTION public.scl379_ph_request_accept(p_token text, p_id uuid, p_year integer, p_installation_version bigint, p_snapshot_revision bigint,
  p_state jsonb, p_months jsonb, p_deals jsonb, p_person text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token); rid uuid; nm text; r scl_private.mk_request%ROWTYPE; snap public.scl290_snapshots;
 card_old jsonb; card_new jsonb; d jsonb; n integer; m integer; mn integer; mx integer; who text:=nullif(btrim(coalesce(p_person,'')),''); saved jsonb; prv jsonb;
BEGIN
 SELECT g.id,g.name INTO rid,nm FROM public.scl290_registry g WHERE g.pharmacy_id=pid;
 PERFORM scl_private.mk_req_sweep(NULL,rid);
 SELECT * INTO r FROM scl_private.mk_request WHERE id=p_id AND registry_id=rid FOR UPDATE;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 IF r.status<>'pending' THEN RAISE EXCEPTION 'MARKET_REQ:answered' USING ERRCODE='22023'; END IF;
 IF p_year IS DISTINCT FROM r.year THEN RAISE EXCEPTION 'MARKET_REQ:bad_request' USING ERRCODE='22023'; END IF;
 IF who IS NULL OR length(who)>160 THEN RAISE EXCEPTION 'MARKET_REQ:person' USING ERRCODE='22023'; END IF;
 SELECT min(x),max(x) INTO mn,mx FROM unnest(r.months) x;
 IF mx-mn+1<>cardinality(r.months) THEN RAISE EXCEPTION 'MARKET_REQ:months_gap' USING ERRCODE='22023'; END IF;
 FOREACH m IN ARRAY r.months LOOP
  IF scl_private.today()>scl_private.cutoff(r.year,m) THEN RAISE EXCEPTION 'MARKET_REQ:month_closed' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF scl_private.mk_req_block(r.registry_id,r.position_id,r.year,r.months) IS NOT NULL THEN RAISE EXCEPTION 'MARKET_REQ:month_taken' USING ERRCODE='22023'; END IF;
 SELECT * INTO snap FROM public.scl290_snapshots WHERE pharmacy_id=pid AND year=r.year;
 SELECT c INTO card_old FROM jsonb_array_elements(snap.state_json->'cards') c WHERE c->>'id'=r.position_id;
 IF coalesce(card_old->>'screenFormat','') IS DISTINCT FROM r.format THEN RAISE EXCEPTION 'MARKET_REQ:format_changed' USING ERRCODE='22023'; END IF;
 -- Η μόνη διαφορά στις οριστικές συμφωνίες: η νέα συμφωνία αυτού του αιτήματος, με τα στοιχεία του αιτήματος.
 SELECT c INTO card_new FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state->'cards')='array' THEN p_state->'cards' ELSE '[]'::jsonb END) c WHERE c->>'id'=r.position_id;
 SELECT count(*) INTO n FROM jsonb_array_elements(CASE WHEN jsonb_typeof(card_new->'confirmedDeals')='array' THEN card_new->'confirmedDeals' ELSE '[]'::jsonb END) x WHERE x#>>'{market,request_id}'=r.id::text;
 IF n<>1 THEN RAISE EXCEPTION 'MARKET_REQ:deal_mismatch' USING ERRCODE='22023'; END IF;
 SELECT x INTO d FROM jsonb_array_elements(card_new->'confirmedDeals') x WHERE x#>>'{market,request_id}'=r.id::text;
 IF nullif(d->>'id','') IS NULL OR d->>'confirmed' IS DISTINCT FROM 'true'
    OR (d->>'startMonth')::integer IS DISTINCT FROM mn OR (d->>'duration')::integer IS DISTINCT FROM cardinality(r.months)
    OR (d->>'soldMonthlyPrice')::numeric IS DISTINCT FROM r.price_month
    OR coalesce(d->>'supplier','') IS DISTINCT FROM r.company_name
    OR coalesce(d->>'brand','') IS DISTINCT FROM array_to_string(r.brand_names,' + ')
    OR coalesce(d->>'subline','') IS DISTINCT FROM coalesce(r.theme,'')
    OR (r.same_theme AND d->>'monthlyContentChanges' IS DISTINCT FROM 'false')
    OR (NOT r.same_theme AND d->>'monthlyContentChanges' IS DISTINCT FROM 'true')
    OR EXISTS(SELECT 1 FROM unnest(r.months) x WHERE NOT r.same_theme AND coalesce(d->'schedule'->>x,'') IS DISTINCT FROM 'Πλανόγραμμα '||(scl_private.mk_plan_index(r.plans,x)+1)) THEN
  RAISE EXCEPTION 'MARKET_REQ:deal_mismatch' USING ERRCODE='22023';
 END IF;
 IF (SELECT coalesce(jsonb_agg(scl_private.market_deal_sig(x) ORDER BY x->>'id'),'[]') FROM jsonb_array_elements(CASE WHEN jsonb_typeof(card_old->'confirmedDeals')='array' THEN card_old->'confirmedDeals' ELSE '[]'::jsonb END) x WHERE x->>'confirmed'='true')
    IS DISTINCT FROM
    (SELECT coalesce(jsonb_agg(scl_private.market_deal_sig(x) ORDER BY x->>'id'),'[]') FROM jsonb_array_elements(card_new->'confirmedDeals') x WHERE x->>'confirmed'='true' AND x#>>'{market,request_id}' IS DISTINCT FROM r.id::text) THEN
  RAISE EXCEPTION 'MARKET_REQ:deal_mismatch' USING ERRCODE='22023';
 END IF;
 -- Οι γραμμές μηνών πριν το «Δέχομαι» (για την ακύρωση).
 SELECT coalesce(jsonb_agg(x),'[]') INTO prv FROM jsonb_array_elements(coalesce(snap.months_json,'[]')) x WHERE x->>'position_id'=r.position_id AND (x->>'month')::integer=ANY(r.months);
 PERFORM set_config('scl379.market_write','yes',true);
 saved:=public.scl290_save_program(p_token,p_year,p_installation_version,p_snapshot_revision,p_state,p_months,p_deals);
 UPDATE scl_private.mk_request SET status='accepted',reason=NULL,closed_at=now(),seen_pharmacy_at=coalesce(seen_pharmacy_at,now()),accepted_by=who,deal_id=d->>'id',prior_months=prv WHERE id=r.id RETURNING * INTO r;
 PERFORM set_config('scl379.market_write','no',true);
 PERFORM scl_private.mk_req_log(r.id,'pharmacy',who||' · '||nm,'accepted',jsonb_build_object('deal_id',r.deal_id,'person',who));
 -- τα άλλα αιτήματα για τους ίδιους μήνες λήγουν («Ο μήνας κλείστηκε»)
 PERFORM scl_private.mk_req_sweep(NULL,rid);
 RETURN saved||jsonb_build_object('ok',true,'request',scl_private.mk_req_json(r,'pharmacy'));
END $function$;

-- 4β. Ακύρωση από τα Κεντρικά: όλη η συμφωνία ή μόνο οι ανοιχτοί μήνες. Επανέρχεται ό,τι έπαιζε πριν.
CREATE OR REPLACE FUNCTION scl_private.k3b_set12(arr jsonb, m integer, v jsonb)
 RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $function$
 SELECT jsonb_agg(CASE WHEN i=m THEN v ELSE coalesce(CASE WHEN jsonb_typeof(arr)='array' THEN arr->i END,'""'::jsonb) END ORDER BY i) FROM generate_series(0,11) i;
$function$;

CREATE OR REPLACE FUNCTION public.scl379_hq_deal_cancel(p_hq_key text, p_id uuid, p_reason text, p_person text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r scl_private.mk_request%ROWTYPE; v text:=nullif(btrim(coalesce(p_reason,'')),''); who text:=coalesce(nullif(btrim(coalesce(p_person,'')),''),'Κεντρικά Pharmaplus');
 pid uuid; snap public.scl290_snapshots; st jsonb; cards jsonb:='[]'; c jsonb; d jsonb; deals jsonb; nd jsonb; m integer; locked integer[]:='{}'; opn integer[]:='{}';
 pr jsonb; mm jsonb; dj jsonb; full_cancel boolean;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF v IS NULL OR length(v)>300 THEN RAISE EXCEPTION 'MARKET_REQ:reason' USING ERRCODE='22023'; END IF;
 SELECT * INTO r FROM scl_private.mk_request WHERE id=p_id FOR UPDATE;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 IF r.status<>'accepted' OR r.deal_id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_accepted' USING ERRCODE='22023'; END IF;
 SELECT pharmacy_id INTO pid FROM public.scl290_registry WHERE id=r.registry_id;
 SELECT * INTO snap FROM public.scl290_snapshots WHERE pharmacy_id=pid AND year=r.year FOR UPDATE;
 IF snap.pharmacy_id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 st:=snap.state_json;
 FOR c IN SELECT value FROM jsonb_array_elements(st->'cards') LOOP
  IF c->>'id'=r.position_id THEN
   SELECT x INTO d FROM jsonb_array_elements(coalesce(c->'confirmedDeals','[]')) x WHERE x->>'id'=r.deal_id;
   IF d IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:deal_missing' USING ERRCODE='P0002'; END IF;
   FOR m IN SELECT generate_series((d->>'startMonth')::integer,(d->>'startMonth')::integer+(d->>'duration')::integer-1) LOOP
    IF scl_private.today()>scl_private.cutoff(r.year,m) THEN locked:=locked||m; ELSE opn:=opn||m; END IF;
   END LOOP;
   IF cardinality(opn)=0 THEN RAISE EXCEPTION 'MARKET_REQ:all_locked' USING ERRCODE='22023'; END IF;
   full_cancel:=cardinality(locked)=0;
   SELECT coalesce(jsonb_agg(CASE WHEN x->>'id'=r.deal_id THEN x||jsonb_build_object('duration',cardinality(locked)) ELSE x END),'[]') INTO deals
    FROM jsonb_array_elements(c->'confirmedDeals') x WHERE NOT (full_cancel AND x->>'id'=r.deal_id);
   c:=c||jsonb_build_object('confirmedDeals',deals);
   -- Επαναφορά της Εξατομίκευσης που είχε αντικαταστήσει η συμφωνία, αν το Βασικό του μήνα δεν άλλαξε στο μεταξύ.
   FOREACH m IN ARRAY opn LOOP
    pr:=d->'prior'->(m::text);
    IF jsonb_typeof(pr)='object' AND coalesce(c->'basicSchedule'->>m,'')=coalesce(pr->>'basic','') AND coalesce(pr->>'simple','')<>'' THEN
     c:=c||jsonb_build_object('simpleConfirmed',true,
      'simpleSchedule',scl_private.k3b_set12(c->'simpleSchedule',m,to_jsonb(pr->>'simple')),
      'pendingSimpleSchedule',scl_private.k3b_set12(c->'pendingSimpleSchedule',m,to_jsonb(pr->>'simple')),
      'simpleMechanism',scl_private.k3b_set12(c->'simpleMechanism',m,to_jsonb(coalesce(nullif(pr->>'mechanism',''),'Χωρίς μηχανισμό'))),
      'pendingSimpleMechanism',scl_private.k3b_set12(c->'pendingSimpleMechanism',m,to_jsonb(coalesce(nullif(pr->>'mechanism',''),'Χωρίς μηχανισμό'))));
    END IF;
   END LOOP;
  END IF;
  cards:=cards||jsonb_build_array(c);
 END LOOP;
 st:=st||jsonb_build_object('cards',cards);
 -- Γραμμές μηνών: οι ακυρωμένοι μήνες γυρίζουν στις γραμμές πριν το «Δέχομαι».
 SELECT coalesce(jsonb_agg(x),'[]') INTO mm FROM jsonb_array_elements(coalesce(snap.months_json,'[]')) x
  WHERE NOT (x->>'position_id'=r.position_id AND (x->>'month')::integer=ANY(opn));
 mm:=mm||coalesce((SELECT jsonb_agg(x) FROM jsonb_array_elements(coalesce(r.prior_months,'[]')) x WHERE (x->>'month')::integer=ANY(opn)),'[]');
 SELECT coalesce(jsonb_agg(CASE WHEN x->>'deal_uid'=r.deal_id THEN x||jsonb_build_object('end_month',locked[cardinality(locked)],'raw_json',(x->'raw_json')||jsonb_build_object('duration',cardinality(locked))) ELSE x END),'[]') INTO dj
  FROM jsonb_array_elements(coalesce(snap.deals_json,'[]')) x WHERE NOT (full_cancel AND x->>'deal_uid'=r.deal_id);
 PERFORM set_config('scl379.market_write','yes',true);
 UPDATE public.scl290_snapshots SET state_json=st,months_json=mm,deals_json=dj,revision=revision+1,updated_at=now() WHERE pharmacy_id=pid AND year=r.year;
 UPDATE public.scl292_program_history SET reason='Ακύρωση συμφωνίας Market από τα Κεντρικά · '||scl_private.mk_req_label(r.no,r.created_at)
  WHERE pharmacy_id=pid AND year=r.year AND revision=snap.revision;
 PERFORM set_config('scl290.authorized_write','yes',true);
 INSERT INTO public.pharmacy_state(pharmacy_id,year,state_json,updated_at) VALUES(pid,r.year,(SELECT s.state_json FROM public.scl290_snapshots s WHERE s.pharmacy_id=pid AND s.year=r.year),now())
  ON CONFLICT ON CONSTRAINT pharmacy_state_pharmacy_id_year_key DO UPDATE SET state_json=excluded.state_json,updated_at=now();
 PERFORM set_config('scl290.authorized_write','no',true);
 IF full_cancel THEN
  UPDATE scl_private.mk_request SET status='cancelled',reason='hq',hq_note=v,cancelled_months=opn,cancelled_by=who,cancel_asked_at=NULL,seen_company_at=NULL,seen_pharmacy_at=NULL WHERE id=r.id RETURNING * INTO r;
  PERFORM scl_private.mk_req_log(r.id,'hq',who,'cancelled',jsonb_build_object('reason','hq','note',v,'months',to_jsonb(opn)));
 ELSE
  UPDATE scl_private.mk_request SET hq_note=v,cancelled_months=opn,cancelled_by=who,cancel_asked_at=NULL,seen_company_at=NULL,seen_pharmacy_at=NULL WHERE id=r.id RETURNING * INTO r;
  PERFORM scl_private.mk_req_log(r.id,'hq',who,'partly_cancelled',jsonb_build_object('note',v,'months',to_jsonb(opn),'kept',to_jsonb(locked)));
 END IF;
 PERFORM set_config('scl379.market_write','no',true);
 RETURN jsonb_build_object('ok',true,'full',full_cancel,'cancelled_months',to_jsonb(opn),'kept_months',to_jsonb(locked),'request',scl_private.mk_req_json(r,'hq'));
END $function$;

-- 4γ. Η εταιρία ζητά ακύρωση (μόνο για «Δέχτηκε») · τα Κεντρικά την κρατούν ή ακυρώνουν
CREATE OR REPLACE FUNCTION public.scl379_mk_cancel_ask(p_key text, p_id uuid, p_note text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key); r scl_private.mk_request%ROWTYPE; v text:=nullif(btrim(coalesce(p_note,'')),'');
BEGIN
 IF v IS NOT NULL AND length(v)>300 THEN RAISE EXCEPTION 'MARKET_REQ:note_long' USING ERRCODE='22023'; END IF;
 SELECT * INTO r FROM scl_private.mk_request WHERE id=p_id AND company_id=me.company_id FOR UPDATE;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 IF r.status<>'accepted' OR r.cancel_asked_at IS NOT NULL
    OR NOT EXISTS(SELECT 1 FROM unnest(r.months) m WHERE scl_private.today()<=scl_private.cutoff(r.year,m) AND NOT (m=ANY(coalesce(r.cancelled_months,'{}')))) THEN
  RETURN jsonb_build_object('ok',false,'request',scl_private.mk_req_json(r,'company')); END IF;
 UPDATE scl_private.mk_request SET cancel_asked_at=now(),cancel_ask_note=v,cancel_ask_by=me.full_name WHERE id=r.id RETURNING * INTO r;
 PERFORM scl_private.mk_req_log(r.id,'company',me.full_name||' · '||r.company_name,'cancel_asked',jsonb_strip_nulls(jsonb_build_object('note',v)));
 RETURN jsonb_build_object('ok',true,'request',scl_private.mk_req_json(r,'company'));
END $function$;

CREATE OR REPLACE FUNCTION public.scl379_hq_cancel_ask_decline(p_hq_key text, p_id uuid, p_note text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r scl_private.mk_request%ROWTYPE; v text:=nullif(btrim(coalesce(p_note,'')),'');
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF v IS NULL OR length(v)>300 THEN RAISE EXCEPTION 'MARKET_REQ:reason' USING ERRCODE='22023'; END IF;
 SELECT * INTO r FROM scl_private.mk_request WHERE id=p_id FOR UPDATE;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 IF r.cancel_asked_at IS NULL THEN RETURN jsonb_build_object('ok',false,'request',scl_private.mk_req_json(r,'hq')); END IF;
 UPDATE scl_private.mk_request SET cancel_asked_at=NULL,seen_company_at=NULL WHERE id=r.id RETURNING * INTO r;
 PERFORM scl_private.mk_req_log(r.id,'hq','Κεντρικά Pharmaplus','cancel_ask_declined',jsonb_build_object('note',v));
 RETURN jsonb_build_object('ok',true,'request',scl_private.mk_req_json(r,'hq'));
END $function$;

-- ΑΛΛΑΓΗ: λίστα «Η εταιρία ζητά ακύρωση» στα Κεντρικά
CREATE OR REPLACE FUNCTION public.scl374_hq_requests(p_hq_key text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 PERFORM scl_private.mk_req_sweep(NULL,NULL);
 RETURN jsonb_build_object(
  'pending',(SELECT coalesce(jsonb_agg(scl_private.mk_req_json(r,'hq') ORDER BY r.answer_by,r.created_at),'[]'::jsonb) FROM scl_private.mk_request r WHERE r.status='pending'),
  'cancel_asks',(SELECT coalesce(jsonb_agg(scl_private.mk_req_json(r,'hq') ORDER BY r.cancel_asked_at),'[]'::jsonb) FROM scl_private.mk_request r WHERE r.status='accepted' AND r.cancel_asked_at IS NOT NULL),
  'unseen',(SELECT coalesce(jsonb_agg(scl_private.mk_req_json(r,'hq') ORDER BY r.closed_at),'[]'::jsonb) FROM scl_private.mk_request r WHERE r.status IN ('declined','expired','cancelled','accepted') AND r.seen_company_at IS NULL),
  'recent',(SELECT coalesce(jsonb_agg(j ORDER BY ca DESC),'[]'::jsonb) FROM (SELECT scl_private.mk_req_json(r,'hq') j,r.closed_at ca FROM scl_private.mk_request r WHERE r.status<>'pending' ORDER BY r.closed_at DESC LIMIT 100) h),
  'counts',jsonb_build_object(
   'pending',(SELECT count(*) FROM scl_private.mk_request r WHERE r.status='pending' AND NOT r.is_test),
   'urgent',(SELECT count(*) FROM scl_private.mk_request r WHERE r.status='pending' AND NOT r.is_test AND r.answer_by-scl_private.today()<=2),
   'cancel_asks',(SELECT count(*) FROM scl_private.mk_request r WHERE r.status='accepted' AND r.cancel_asked_at IS NOT NULL),
   'unseen',(SELECT count(*) FROM scl_private.mk_request r WHERE r.status IN ('declined','expired','cancelled','accepted') AND r.seen_company_at IS NULL AND NOT r.is_test AND r.closed_at<now()-interval '3 days')));
END $function$;

-- Δικαιώματα: όπως οι υπόλοιπες RPC (anon καλεί, ο έλεγχος γίνεται μέσα)
REVOKE ALL ON FUNCTION public.scl379_ph_request_accept(text,uuid,integer,bigint,bigint,jsonb,jsonb,jsonb,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl379_hq_deal_cancel(text,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl379_mk_cancel_ask(text,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl379_hq_cancel_ask_decline(text,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl379_hq_codes(text,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scl379_hq_set_code(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl379_ph_request_accept(text,uuid,integer,bigint,bigint,jsonb,jsonb,jsonb,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl379_hq_deal_cancel(text,uuid,text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl379_mk_cancel_ask(text,uuid,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl379_hq_cancel_ask_decline(text,uuid,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl379_hq_codes(text,uuid) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl379_hq_set_code(text,text,text,text) TO anon,authenticated;

-- 5. ΑΛΛΑΓΗ: προθεσμία υλικού = 15 του προηγούμενου μήνα, ίδια με το κλείδωμα (απόφαση 24/11· ήταν «1η του μήνα − 14 ημέρες»)
CREATE OR REPLACE FUNCTION public.scl304_materials(p_hq_key text, p_year integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος';END IF;
 RETURN jsonb_build_object('year',p_year,'items',(SELECT coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object(
 'pharmacy_id',s.pharmacy_id,'pharmacy_name',r.name,'year',s.year,'orientation',pos->>'screenFormat',
 'deadline',scl_private.cutoff(p_year,b.start_month),'filename',coalesce(a.filename,''),'status',coalesce(a.status,'awaiting'),'revision',coalesce(a.revision,0),'updated_at',a.updated_at)),'[]')
 FROM public.scl290_snapshots s JOIN public.scl290_registry r ON r.pharmacy_id=s.pharmacy_id
 JOIN public.scl290_installations i ON i.pharmacy_id=s.pharmacy_id
 CROSS JOIN LATERAL scl_private.blocks(s.year,s.state_json) b
 CROSS JOIN LATERAL jsonb_array_elements(i.positions) pos
 LEFT JOIN scl_private.agreement_materials a ON a.pharmacy_id=s.pharmacy_id AND a.year=s.year AND a.event_key=b.event_key AND a.orientation=pos->>'screenFormat'
 WHERE s.year=p_year AND b.category='deal' AND pos->>'id'=b.position_id
 AND coalesce(nullif(pos->>'startsOn','')::date,make_date(p_year,1,1))<=make_date(p_year,b.end_month+1,1)
 AND coalesce(nullif(pos->>'stopsOn','')::date,make_date(p_year+1,1,1))>make_date(p_year,b.start_month+1,1)));
END $function$;
