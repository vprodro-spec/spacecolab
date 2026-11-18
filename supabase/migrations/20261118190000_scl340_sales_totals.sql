-- scl340 (v332.0): τζίρος BI και αποδείξεις ανά φαρμακείο (κοστολόγηση θέσης και «επισκέψεις»).
-- ΑΝΑΘΕΩΡΗΣΗ 18/11 βράδυ: ΧΩΡΙΣ τζίρο override. Ο «ενεργός» τζίρος παραμένει αποκλειστικά το state_json.turnover
-- του έτους (scl290_snapshots), που αλλάζει μόνο από τη σημερινή ροή «Αλλαγή τζίρου» του φαρμακείου.
-- Εδώ: μηνιαίοι τζίροι/αποδείξεις του BI (μόνο για προβολή/πρόταση), αποδείξεις που μπορεί να διορθώσει
-- το φαρμακείο ή τα Κεντρικά, ρυθμίσεις, ιστορικό αλλαγών αποδείξεων, και RPC για τον κωδικό BI στο μητρώο.
-- ΕΦΑΡΜΟΣΤΗΚΕ 18/11/2026 (~22:15) μετά από ρητό «ναι». Μετά την εφαρμογή: 0 από 101 υπάρχοντες ορισμούς συναρτήσεων άλλαξαν.
-- Στην ίδια συνεδρία (χωριστό «ναι»): ορίστηκαν οι 3 εκκρεμείς κωδικοί BI του scl3319 (117471, 105303, 106296) και
-- φορτώθηκαν 81 φαρμακεία × 24 μήνες (1.944 γραμμές) από τα αρχεία BI· έλεγχος αθροισμάτων ανά φαρμακείο: 0 διαφορές.
-- Τα δεδομένα ΔΕΝ βρίσκονται στο repo.
-- Αποκλειστικά ΠΡΟΣΘΗΚΕΣ: νέοι πίνακες και νέες συναρτήσεις. Καμία υπάρχουσα συνάρτηση, πίνακας, trigger ή γραμμή δεν αλλάζει.
-- Το scl340 ΔΙΑΒΑΖΕΙ το scl290_snapshots αλλά ΔΕΝ γράφει ποτέ σε scl290_snapshots / pharmacy_state.
-- Η scl340_hq_set_pharmacy_code γράφει ΜΟΝΟ τη στήλη pharmacy_code του μητρώου (όχι revision/updated_at).
-- Τα ΔΕΔΟΜΕΝΑ δεν βρίσκονται εδώ (το repo είναι δημόσιο). Φορτώνονται με scl_private.sales_import() και μένουν μόνο στη βάση.
-- Rollback: supabase/rollback/20261118190000_scl340_sales_totals_rollback.sql

-- 0. Αντίγραφο ασφαλείας: ο ορισμός κάθε υπάρχουσας public/scl_private συνάρτησης πριν από οποιαδήποτε αλλαγή.
CREATE TABLE scl_private.backup_v340_functions AS
 SELECT n.nspname::text AS schema_name, p.proname::text AS fn, pg_get_function_identity_arguments(p.oid) AS args,
        pg_get_functiondef(p.oid) AS definition, now() AS taken_at
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','scl_private') AND p.prokind='f';
ALTER TABLE scl_private.backup_v340_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v340_functions FROM PUBLIC,anon,authenticated;

-- 1. Πίνακες (ιδιωτικό σχήμα, RLS χωρίς πολιτικές, REVOKE: καμία άμεση πρόσβαση από τον browser).
CREATE TABLE scl_private.sales_batches(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 label text NOT NULL CHECK(length(btrim(label)) BETWEEN 1 AND 120),
 rows_count integer NOT NULL DEFAULT 0 CHECK(rows_count>=0),
 pharmacies_count integer NOT NULL DEFAULT 0 CHECK(pharmacies_count>=0),
 first_month date,
 last_month date,
 created_at timestamptz NOT NULL DEFAULT now()
);

-- Μηνιαία σύνολα όπως ήρθαν από το BI. Κλειδί: η γραμμή του μητρώου.
CREATE TABLE scl_private.pharmacy_month_totals(
 registry_id uuid NOT NULL REFERENCES public.scl290_registry(id) ON DELETE CASCADE,
 month date NOT NULL CHECK(month=date_trunc('month',month)::date),
 turnover numeric(14,2) NOT NULL CHECK(turnover>=0),
 receipts numeric(12,1) NOT NULL CHECK(receipts>=0),
 is_forecast boolean NOT NULL DEFAULT false,
 batch_id uuid NOT NULL REFERENCES scl_private.sales_batches(id),
 PRIMARY KEY(registry_id,month)
);
CREATE INDEX pharmacy_month_totals_batch ON scl_private.pharmacy_month_totals(batch_id);

-- Ετήσιες αποδείξεις που όρισε το φαρμακείο ή τα Κεντρικά. Υπερισχύουν του BI. Χωρίς γραμμή = τιμή BI.
CREATE TABLE scl_private.pharmacy_receipts_override(
 registry_id uuid NOT NULL REFERENCES public.scl290_registry(id) ON DELETE CASCADE,
 year integer NOT NULL CHECK(year BETWEEN 2000 AND 2200),
 receipts numeric(12,1) NOT NULL CHECK(receipts>0),
 set_by text NOT NULL CHECK(set_by IN ('pharmacy','hq')),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(registry_id,year)
);

-- Ιστορικό αλλαγών αποδείξεων. new_value NULL = επαναφορά στην τιμή του BI.
CREATE TABLE scl_private.pharmacy_receipts_changes(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 registry_id uuid NOT NULL REFERENCES public.scl290_registry(id) ON DELETE CASCADE,
 year integer NOT NULL,
 bi_value numeric,
 old_value numeric,
 new_value numeric,
 set_by text NOT NULL CHECK(set_by IN ('pharmacy','hq')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX pharmacy_receipts_changes_recent ON scl_private.pharmacy_receipts_changes(created_at DESC);
CREATE INDEX pharmacy_receipts_changes_pharmacy ON scl_private.pharmacy_receipts_changes(registry_id,created_at DESC);

-- Ρυθμίσεις (μία γραμμή): επισκέψεις ανά απόδειξη, αν το φαρμακείο μπορεί να αλλάζει αποδείξεις.
CREATE TABLE scl_private.sales_settings(
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 visitors_per_receipt numeric(4,2) NOT NULL DEFAULT 1.5 CHECK(visitors_per_receipt BETWEEN 1 AND 5),
 pharmacy_can_edit boolean NOT NULL DEFAULT true,
 updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO scl_private.sales_settings DEFAULT VALUES;

ALTER TABLE scl_private.sales_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.pharmacy_month_totals ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.pharmacy_receipts_override ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.pharmacy_receipts_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.sales_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.sales_batches,scl_private.pharmacy_month_totals,scl_private.pharmacy_receipts_override,scl_private.pharmacy_receipts_changes,scl_private.sales_settings FROM PUBLIC,anon,authenticated;

-- 2. Εσωτερικές συναρτήσεις (όχι για anon/authenticated).
-- Τρέχων τζίρος προγράμματος (ΜΟΝΟ ΑΝΑΓΝΩΣΗ) από scl290_snapshots: το ζητούμενο έτος, αλλιώς το πιο πρόσφατο προηγούμενο
-- (όπως η scl290_get_pharmacy αντιγράφει το προηγούμενο state_json στο νέο έτος). Μη αριθμητική τιμή => NULL.
CREATE FUNCTION scl_private.sales_program_turnover(p_rid uuid,p_year integer) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('turnover',CASE WHEN jsonb_typeof(s.state_json->'turnover')='number' THEN (s.state_json->>'turnover')::numeric END,'year',s.year)
 FROM public.scl290_registry r JOIN public.scl290_snapshots s ON s.pharmacy_id=r.pharmacy_id
 WHERE r.id=p_rid AND s.year<=p_year
 ORDER BY s.year DESC LIMIT 1
$$;

-- Τιμές ενός φαρμακείου για ένα έτος:
--  • Έτος δεδομένων BI = το ζητούμενο, αν έχει μήνες· αλλιώς το πιο πρόσφατο προηγούμενο με δεδομένα.
--  • bi.turnover = ετήσιος τζίρος BI (πρόταση, ΔΕΝ είναι ο τζίρος τιμολόγησης). program.turnover = ο τζίρος τιμολόγησης.
--  • Αποδείξεις: override φαρμακείου/Κεντρικών αν υπάρχει, αλλιώς BI. Επισκέψεις = αποδείξεις × επισκέψεις ανά απόδειξη.
CREATE FUNCTION scl_private.sales_effective(p_rid uuid,p_year integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE vpr numeric;dy integer;n integer:=0;nf integer:=0;bi_t numeric;bi_r numeric;months jsonb:='[]'::jsonb;
 ov scl_private.pharmacy_receipts_override;er numeric;sr text;
BEGIN
 SELECT visitors_per_receipt INTO vpr FROM scl_private.sales_settings;
 IF EXISTS(SELECT 1 FROM scl_private.pharmacy_month_totals WHERE registry_id=p_rid AND month>=make_date(p_year,1,1) AND month<make_date(p_year+1,1,1)) THEN
  dy:=p_year;
 ELSE
  SELECT max(extract(year FROM month))::integer INTO dy FROM scl_private.pharmacy_month_totals WHERE registry_id=p_rid AND month<make_date(p_year,1,1);
 END IF;
 IF dy IS NOT NULL THEN
  SELECT count(*),count(*) FILTER(WHERE is_forecast),sum(turnover),sum(receipts),
         coalesce(jsonb_agg(jsonb_build_object('month',to_char(month,'YYYY-MM'),'turnover',turnover,'receipts',receipts,'forecast',is_forecast) ORDER BY month),'[]'::jsonb)
  INTO n,nf,bi_t,bi_r,months
  FROM scl_private.pharmacy_month_totals WHERE registry_id=p_rid AND month>=make_date(dy,1,1) AND month<make_date(dy+1,1,1);
 END IF;
 SELECT * INTO ov FROM scl_private.pharmacy_receipts_override WHERE registry_id=p_rid AND year=p_year;
 er:=coalesce(ov.receipts,bi_r);
 sr:=CASE WHEN ov.receipts IS NOT NULL THEN ov.set_by WHEN bi_r IS NOT NULL THEN 'bi' END;
 RETURN jsonb_build_object(
  'year',p_year,'data_year',dy,'visitors_per_receipt',vpr,
  'program',scl_private.sales_program_turnover(p_rid,p_year),
  'bi',CASE WHEN dy IS NULL THEN NULL ELSE jsonb_build_object('turnover',bi_t,'receipts',bi_r,'months_count',n,'forecast_months',nf,
       'turnover_monthly',CASE WHEN n>0 THEN round(bi_t/n) END,'months',months) END,
  'receipts_override',CASE WHEN ov.set_by IS NULL THEN NULL ELSE jsonb_build_object('receipts',ov.receipts,'set_by',ov.set_by,'updated_at',ov.updated_at) END,
  'effective',jsonb_build_object('receipts',er,'receipts_source',sr,
   'receipts_monthly',CASE WHEN er IS NULL THEN NULL ELSE round(er/12) END,
   'visits',CASE WHEN er IS NULL THEN NULL ELSE round(er*vpr) END,
   'visits_monthly',CASE WHEN er IS NULL THEN NULL ELSE round(er*vpr/12) END));
END $$;

-- Ορισμός αποδείξεων (NULL = επαναφορά στο BI). Κάθε αλλαγή καταγράφεται.
CREATE FUNCTION scl_private.sales_set_receipts(p_rid uuid,p_year integer,p_receipts numeric,p_by text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old scl_private.pharmacy_receipts_override;bi_r numeric;
BEGIN
 IF p_by IS NULL OR p_by NOT IN ('pharmacy','hq') THEN RAISE EXCEPTION 'Μη έγκυρος χρήστης αλλαγής';END IF;
 IF p_rid IS NULL OR NOT EXISTS(SELECT 1 FROM public.scl290_registry WHERE id=p_rid) THEN RAISE EXCEPTION 'Δεν βρέθηκε το φαρμακείο στο μητρώο';END IF;
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος';END IF;
 IF p_receipts IS NOT NULL AND (p_receipts='NaN' OR p_receipts<=0 OR p_receipts>10000000) THEN RAISE EXCEPTION 'Οι αποδείξεις πρέπει να είναι θετικός αριθμός.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('scl340:'||p_rid::text,0));
 SELECT * INTO old FROM scl_private.pharmacy_receipts_override WHERE registry_id=p_rid AND year=p_year;
 bi_r:=nullif(scl_private.sales_effective(p_rid,p_year)#>>'{bi,receipts}','')::numeric;
 IF p_receipts IS NULL THEN
  DELETE FROM scl_private.pharmacy_receipts_override WHERE registry_id=p_rid AND year=p_year;
 ELSE
  INSERT INTO scl_private.pharmacy_receipts_override(registry_id,year,receipts,set_by) VALUES(p_rid,p_year,p_receipts,p_by)
  ON CONFLICT(registry_id,year) DO UPDATE SET receipts=EXCLUDED.receipts,set_by=EXCLUDED.set_by,updated_at=now();
 END IF;
 IF old.receipts IS DISTINCT FROM p_receipts THEN
  INSERT INTO scl_private.pharmacy_receipts_changes(registry_id,year,bi_value,old_value,new_value,set_by) VALUES(p_rid,p_year,bi_r,old.receipts,p_receipts,p_by);
 END IF;
END $$;

-- Εισαγωγή από το BI. rows: [{code,month:'YYYY-MM',turnover,receipts,forecast}]. code = pharmacy_code του μητρώου.
-- Όλα ή τίποτα: άγνωστος κωδικός ή διπλός μήνας ακυρώνει όλη την εισαγωγή. Νεότερη εισαγωγή αντικαθιστά τον ίδιο μήνα.
-- Δεν αγγίζει αποδείξεις φαρμακείου/Κεντρικών ούτε τον τζίρο προγράμματος.
CREATE FUNCTION scl_private.sales_import(p_label text,p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE bid uuid;total integer;ins integer;bad text;np integer;fm date;lm date;
BEGIN
 IF p_rows IS NULL OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows)=0 THEN RAISE EXCEPTION 'Η εισαγωγή δεν έχει γραμμές';END IF;
 IF octet_length(p_rows::text)>4000000 THEN RAISE EXCEPTION 'Η εισαγωγή είναι υπερβολικά μεγάλη· σπάστε την σε δύο μέρη';END IF;
 total:=jsonb_array_length(p_rows);
 PERFORM pg_advisory_xact_lock(hashtextextended('scl340:import',0));
 INSERT INTO scl_private.sales_batches(label) VALUES(p_label) RETURNING id INTO bid;
 BEGIN
  INSERT INTO scl_private.pharmacy_month_totals(registry_id,month,turnover,receipts,is_forecast,batch_id)
  SELECT g.id,(s.value->>'month'||'-01')::date,(s.value->>'turnover')::numeric,(s.value->>'receipts')::numeric,coalesce((s.value->>'forecast')::boolean,false),bid
  FROM jsonb_array_elements(p_rows) s(value) JOIN public.scl290_registry g ON g.pharmacy_code=s.value->>'code'
  ON CONFLICT(registry_id,month) DO UPDATE SET turnover=EXCLUDED.turnover,receipts=EXCLUDED.receipts,is_forecast=EXCLUDED.is_forecast,batch_id=EXCLUDED.batch_id;
  GET DIAGNOSTICS ins=ROW_COUNT;
 EXCEPTION WHEN cardinality_violation THEN
  RAISE EXCEPTION 'Η εισαγωγή ακυρώθηκε: ο ίδιος μήνας του ίδιου φαρμακείου υπάρχει δύο φορές στα αρχεία.';
 END;
 IF ins<>total THEN
  SELECT string_agg(DISTINCT s.value->>'code',', ') INTO bad FROM jsonb_array_elements(p_rows) s(value) WHERE NOT EXISTS(SELECT 1 FROM public.scl290_registry g WHERE g.pharmacy_code=s.value->>'code');
  RAISE EXCEPTION 'Η εισαγωγή ακυρώθηκε: % από % γραμμές δεν αντιστοιχούν σε φαρμακείο. Άγνωστοι κωδικοί: %',total-ins,total,coalesce(bad,'—');
 END IF;
 SELECT count(DISTINCT registry_id),min(month),max(month) INTO np,fm,lm FROM scl_private.pharmacy_month_totals WHERE batch_id=bid;
 UPDATE scl_private.sales_batches SET rows_count=ins,pharmacies_count=np,first_month=fm,last_month=lm WHERE id=bid;
 RETURN jsonb_build_object('batch_id',bid,'rows',ins,'pharmacies',np,'first_month',fm,'last_month',lm);
END $$;

REVOKE ALL ON FUNCTION scl_private.sales_program_turnover(uuid,integer),scl_private.sales_effective(uuid,integer),scl_private.sales_set_receipts(uuid,integer,numeric,text),scl_private.sales_import(text,jsonb) FROM PUBLIC,anon,authenticated;

-- 3. Συναρτήσεις προς τον browser.
-- Φαρμακείο: τζίρος BI (πρόταση), τρέχων τζίρος προγράμματος (ανάγνωση), αποδείξεις, επισκέψεις.
CREATE FUNCTION public.scl340_sales_get(p_token text,p_year integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token);rid uuid;
BEGIN
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος';END IF;
 SELECT id INTO rid FROM public.scl290_registry WHERE pharmacy_id=pid;
 RETURN scl_private.sales_effective(rid,p_year)||jsonb_build_object(
  'can_edit',(SELECT pharmacy_can_edit FROM scl_private.sales_settings) AND p_year>=extract(year FROM scl_private.today())::integer);
END $$;

-- Φαρμακείο: αλλαγή ΜΟΝΟ αποδείξεων (NULL = επαναφορά στο BI). Προηγούμενα έτη κλειδωμένα, όπως στο πρόγραμμα.
CREATE FUNCTION public.scl340_sales_save(p_token text,p_year integer,p_receipts numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token);rid uuid;
BEGIN
 IF NOT (SELECT pharmacy_can_edit FROM scl_private.sales_settings) THEN RAISE EXCEPTION 'Η αλλαγή αποδείξεων γίνεται από τα Κεντρικά.';END IF;
 IF p_year IS NULL OR p_year<extract(year FROM scl_private.today()) THEN RAISE EXCEPTION 'HISTORY_LOCKED: Το προηγούμενο έτος είναι μόνο για προβολή';END IF;
 SELECT id INTO rid FROM public.scl290_registry WHERE pharmacy_id=pid;
 PERFORM scl_private.sales_set_receipts(rid,p_year,p_receipts,'pharmacy');
 RETURN public.scl340_sales_get(p_token,p_year);
END $$;

-- Κεντρικά: λίστα φαρμακείων (τζίρος BI, τζίρος προγράμματος, αποδείξεις, επισκέψεις), ρυθμίσεις, 100 πιο πρόσφατες αλλαγές.
CREATE FUNCTION public.scl340_hq_sales_data(p_hq_key text,p_year integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος';END IF;
 RETURN jsonb_build_object(
  'year',p_year,
  'settings',(SELECT jsonb_build_object('visitors_per_receipt',visitors_per_receipt,'pharmacy_can_edit',pharmacy_can_edit) FROM scl_private.sales_settings),
  'pharmacies',(SELECT coalesce(jsonb_agg(jsonb_build_object('registry_id',r.id,'pharmacy_code',r.pharmacy_code,'billing_code',r.billing_code,'name',r.name,
     'data_year',x.e->'data_year','forecast_months',x.e#>'{bi,forecast_months}','months_count',x.e#>'{bi,months_count}',
     'bi_turnover',x.e#>'{bi,turnover}','bi_receipts',x.e#>'{bi,receipts}','program_turnover',x.e#>'{program,turnover}','program_year',x.e#>'{program,year}',
     'receipts_override',x.e->'receipts_override','effective',x.e->'effective') ORDER BY r.billing_code),'[]'::jsonb)
   FROM public.scl290_registry r CROSS JOIN LATERAL (SELECT scl_private.sales_effective(r.id,p_year) AS e) x
   WHERE EXISTS(SELECT 1 FROM scl_private.pharmacy_month_totals t WHERE t.registry_id=r.id) OR EXISTS(SELECT 1 FROM scl_private.pharmacy_receipts_override o WHERE o.registry_id=r.id)),
  'changes',(SELECT coalesce(jsonb_agg(jsonb_build_object('registry_id',c.registry_id,'year',c.year,'bi_value',c.bi_value,'old_value',c.old_value,'new_value',c.new_value,'set_by',c.set_by,'created_at',c.created_at) ORDER BY c.created_at DESC,c.id DESC),'[]'::jsonb)
   FROM (SELECT * FROM scl_private.pharmacy_receipts_changes ORDER BY created_at DESC,id DESC LIMIT 100) c));
END $$;

-- Κεντρικά: αποδείξεις για ένα φαρμακείο (NULL = επαναφορά στο BI). Χωρίς κλείδωμα έτους (διόρθωση λάθους BI).
CREATE FUNCTION public.scl340_hq_sales_set(p_hq_key text,p_registry_id uuid,p_year integer,p_receipts numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 PERFORM scl_private.sales_set_receipts(p_registry_id,p_year,p_receipts,'hq');
 RETURN scl_private.sales_effective(p_registry_id,p_year);
END $$;

-- Κεντρικά: ρυθμίσεις.
CREATE FUNCTION public.scl340_hq_sales_settings(p_hq_key text,p_visitors_per_receipt numeric,p_pharmacy_can_edit boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_visitors_per_receipt IS NULL OR p_visitors_per_receipt='NaN' OR p_visitors_per_receipt NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'Οι επισκέψεις ανά απόδειξη πρέπει να είναι από 1 έως 5.';END IF;
 IF p_pharmacy_can_edit IS NULL THEN RAISE EXCEPTION 'Μη έγκυρη ρύθμιση';END IF;
 UPDATE scl_private.sales_settings SET visitors_per_receipt=p_visitors_per_receipt,pharmacy_can_edit=p_pharmacy_can_edit,updated_at=now();
 RETURN (SELECT jsonb_build_object('visitors_per_receipt',visitors_per_receipt,'pharmacy_can_edit',pharmacy_can_edit) FROM scl_private.sales_settings);
END $$;

-- Κεντρικά: κωδικός BI μιας γραμμής μητρώου. Κενό/NULL = καθαρισμός. Μοναδικός (φιλικό μήνυμα + το partial unique index).
-- Γράφει ΜΟΝΟ pharmacy_code· δεν αλλάζει revision/updated_at, άρα δεν επηρεάζει την scl290_hq_registry_save.
-- Τα ήδη φορτωμένα στοιχεία δένονται με registry_id, άρα αλλαγή κωδικού δεν τα μετακινεί.
CREATE FUNCTION public.scl340_hq_set_pharmacy_code(p_hq_key text,p_registry_id uuid,p_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c text:=nullif(btrim(coalesce(p_code,'')),'');other text;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_registry_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.scl290_registry WHERE id=p_registry_id) THEN RAISE EXCEPTION 'Δεν βρέθηκε το φαρμακείο στο μητρώο';END IF;
 IF c IS NOT NULL AND c !~ '^[0-9A-Za-z_-]{1,40}$' THEN RAISE EXCEPTION 'Ο κωδικός BI δέχεται μόνο ψηφία/λατινικά γράμματα (έως 40).';END IF;
 IF c IS NOT NULL THEN
  SELECT coalesce(nullif(name,''),billing_code) INTO other FROM public.scl290_registry WHERE pharmacy_code=c AND id<>p_registry_id;
  IF FOUND THEN RAISE EXCEPTION 'Ο κωδικός BI % χρησιμοποιείται ήδη από: %',c,other;END IF;
 END IF;
 UPDATE public.scl290_registry SET pharmacy_code=c WHERE id=p_registry_id;
 RETURN jsonb_build_object('registry_id',p_registry_id,'pharmacy_code',c);
EXCEPTION WHEN unique_violation THEN
 RAISE EXCEPTION 'Ο κωδικός BI % χρησιμοποιείται ήδη',c;
END $$;

REVOKE ALL ON FUNCTION public.scl340_sales_get(text,integer),public.scl340_sales_save(text,integer,numeric),public.scl340_hq_sales_data(text,integer),public.scl340_hq_sales_set(text,uuid,integer,numeric),public.scl340_hq_sales_settings(text,numeric,boolean),public.scl340_hq_set_pharmacy_code(text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl340_sales_get(text,integer),public.scl340_sales_save(text,integer,numeric),public.scl340_hq_sales_data(text,integer),public.scl340_hq_sales_set(text,uuid,integer,numeric),public.scl340_hq_sales_settings(text,numeric,boolean),public.scl340_hq_set_pharmacy_code(text,uuid,text) TO anon,authenticated;
