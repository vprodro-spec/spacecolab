-- Append-only monetary corrections. Programme, completion and free-change usage stay intact.
CREATE TABLE scl_private.charge_adjustments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL UNIQUE,
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 year integer NOT NULL CHECK(year BETWEEN 2000 AND 2200),source_key text NOT NULL,
 revision bigint NOT NULL,kind text NOT NULL CHECK(kind IN ('cancel','credit')),
 amount numeric(12,2) NOT NULL CHECK(amount>=0),reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 2000),
 original_row jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(pharmacy_id,year,source_key,revision)
);
ALTER TABLE scl_private.charge_adjustments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.charge_adjustments FROM PUBLIC,anon,authenticated;
CREATE FUNCTION scl_private.charge_identity(r jsonb) RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN nullif(r->>'event_key','') IS NOT NULL THEN 'event:'||(r->>'event_key') ELSE r->>'id' END;
$$;
ALTER FUNCTION scl_private.financial_rows(uuid,integer) RENAME TO financial_rows_v304;
CREATE FUNCTION scl_private.financial_rows(p_pid uuid,p_year integer) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE raw jsonb;out_rows jsonb:='[]';r jsonb;original jsonb;history jsonb;k text;seen text[]:='{}';a record;credited numeric;cancelled boolean;rev bigint;live_status text;
BEGIN
 raw:=scl_private.financial_rows_v304(p_pid,p_year);
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
END $$;

CREATE FUNCTION public.scl305_adjust_charge(p_hq_key text,p_pharmacy_id uuid,p_year integer,p_row_id text,p_kind text,p_amount numeric,p_reason text,p_revision bigint,p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r jsonb;k text;a scl_private.charge_adjustments;original jsonb;credit numeric;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 OR p_request_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('cancel','credit') OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Συμπληρώστε έγκυρη ενέργεια και αιτιολογία';END IF;
 PERFORM 1 FROM public.scl290_installations WHERE pharmacy_id=p_pharmacy_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Το φαρμακείο δεν είναι ενεργό';END IF;
 SELECT * INTO a FROM scl_private.charge_adjustments WHERE request_id=p_request_id;
 IF FOUND THEN
  IF a.pharmacy_id IS DISTINCT FROM p_pharmacy_id OR a.year<>p_year OR a.original_row->>'id' IS DISTINCT FROM p_row_id OR a.kind<>p_kind OR a.reason<>btrim(p_reason) OR a.amount IS DISTINCT FROM p_amount THEN RAISE EXCEPTION 'Το αίτημα έχει ήδη χρησιμοποιηθεί για άλλη διόρθωση';END IF;
  RETURN jsonb_build_object('id',a.id,'saved',true);
 END IF;
 SELECT v INTO r FROM jsonb_array_elements(scl_private.financial_rows(p_pharmacy_id,p_year)) v WHERE v->>'id'=p_row_id;
 IF r IS NULL OR r->>'entry_type'<>'charge' THEN RAISE EXCEPTION 'Η αρχική χρέωση δεν είναι διαθέσιμη. Ανανεώστε τη λίστα.';END IF;
 IF (r->>'adjustment_revision')::bigint IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Η χρέωση άλλαξε. Ανανεώστε πριν καταχωρίσετε τη διόρθωση.';END IF;
 IF p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<>round(p_amount,2) THEN RAISE EXCEPTION 'Συμπληρώστε έγκυρο ποσό με έως δύο δεκαδικά';END IF;
 IF p_kind='cancel' THEN
  IF r->>'status'<>'planned' OR p_amount<>(r->>'amount')::numeric THEN RAISE EXCEPTION 'Ακυρώνεται μόνο προγραμματισμένη χρέωση. Για οριστικοποιημένη χρέωση χρησιμοποιήστε πίστωση.';END IF;
 ELSE
  IF r->>'status'<>'finalized' OR p_amount<=0 OR p_amount>(r->>'remaining_credit')::numeric THEN RAISE EXCEPTION 'Η πίστωση πρέπει να είναι θετική και να μην υπερβαίνει το υπόλοιπο της οριστικοποιημένης χρέωσης';END IF;
 END IF;
 k:=r->>'source_key';
 SELECT original_row INTO original FROM scl_private.charge_adjustments WHERE pharmacy_id=p_pharmacy_id AND year=p_year AND source_key=k ORDER BY revision LIMIT 1;
 IF original IS NULL THEN original:=r-'adjustments'-'adjustment_revision'-'credited_amount'-'remaining_credit';END IF;
 INSERT INTO scl_private.charge_adjustments(request_id,pharmacy_id,year,source_key,revision,kind,amount,reason,original_row)
 VALUES(p_request_id,p_pharmacy_id,p_year,k,p_revision+1,p_kind,p_amount,btrim(p_reason),original) RETURNING * INTO a;
 RETURN jsonb_build_object('id',a.id,'saved',true);
END $$;
REVOKE ALL ON FUNCTION scl_private.charge_identity(jsonb),scl_private.financial_rows(uuid,integer),scl_private.financial_rows_v304(uuid,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.scl305_adjust_charge(text,uuid,integer,text,text,numeric,text,bigint,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl305_adjust_charge(text,uuid,integer,text,text,numeric,text,bigint,uuid) TO anon,authenticated;
NOTIFY pgrst,'reload schema';
