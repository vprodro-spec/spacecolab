-- HQ overview metadata; operational tasks and charges retain their existing sources.
CREATE TABLE scl_private.initial_deadlines (
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 year integer NOT NULL CHECK(year BETWEEN 2000 AND 2200),position_id text NOT NULL,
 due_on date NOT NULL,revision bigint NOT NULL DEFAULT 1,updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(pharmacy_id,year,position_id)
);
CREATE TABLE scl_private.initial_deadline_history (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 year integer NOT NULL,position_id text NOT NULL,before_date date,after_date date NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE scl_private.initial_deadlines ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.initial_deadline_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.initial_deadlines,scl_private.initial_deadline_history FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.scl302_overview(p_hq_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN jsonb_build_object('today',scl_private.today(),
 'deadlines',(SELECT coalesce(jsonb_agg(to_jsonb(d)),'[]') FROM scl_private.initial_deadlines d JOIN public.scl290_registry r ON r.pharmacy_id=d.pharmacy_id),
 'requests',(SELECT coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('pharmacy_name',r.name) ORDER BY q.requested_at DESC),'[]') FROM public.scl292_reset_requests q JOIN public.scl290_registry r ON r.pharmacy_id=q.pharmacy_id));
END $$;

CREATE FUNCTION public.scl302_set_initial_deadline(p_hq_key text,p_pharmacy_id uuid,p_year integer,p_position_id text,p_due_on date,p_expected_revision bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pos jsonb;old scl_private.initial_deadlines;result scl_private.initial_deadlines;st jsonb;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_year IS NULL OR p_year NOT BETWEEN extract(year FROM scl_private.today()) AND 2200 OR p_due_on IS NULL OR p_due_on<scl_private.today() OR extract(year FROM p_due_on)<>p_year THEN RAISE EXCEPTION 'Ορίστε μελλοντική προθεσμία μέσα στο έτος του προγράμματος';END IF;
 PERFORM 1 FROM public.scl290_registry WHERE pharmacy_id=p_pharmacy_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Το φαρμακείο δεν είναι ενεργό';END IF;
 SELECT p INTO pos FROM public.scl290_installations i CROSS JOIN LATERAL jsonb_array_elements(i.positions) p WHERE i.pharmacy_id=p_pharmacy_id AND p->>'id'=p_position_id AND p->>'type'<>'hq'
 AND coalesce(nullif(p->>'startsOn','')::date,make_date(p_year,1,1))<=make_date(p_year,12,31) AND coalesce(nullif(p->>'stopsOn','')::date,make_date(p_year+1,1,1))>make_date(p_year,1,1);
 IF pos IS NULL THEN RAISE EXCEPTION 'Δεν απαιτείται αρχικό πρόγραμμα για αυτή τη θέση';END IF;
 SELECT state_json INTO st FROM public.scl290_snapshots WHERE pharmacy_id=p_pharmacy_id AND year=p_year;
 IF st IS NULL THEN SELECT state_json INTO st FROM public.pharmacy_state WHERE pharmacy_id=p_pharmacy_id AND year=p_year;END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(st->'cards','[]')) c WHERE c->>'id'=p_position_id AND c->>'initialPlanLocked'='true') THEN RAISE EXCEPTION 'Το αρχικό πρόγραμμα έχει ήδη οριστικοποιηθεί';END IF;
 SELECT * INTO old FROM scl_private.initial_deadlines WHERE pharmacy_id=p_pharmacy_id AND year=p_year AND position_id=p_position_id FOR UPDATE;
 IF coalesce(old.revision,0) IS DISTINCT FROM p_expected_revision THEN RAISE EXCEPTION 'Η προθεσμία άλλαξε. Ανανεώστε πριν αποθηκεύσετε.';END IF;
 INSERT INTO scl_private.initial_deadlines(pharmacy_id,year,position_id,due_on) VALUES(p_pharmacy_id,p_year,p_position_id,p_due_on)
 ON CONFLICT(pharmacy_id,year,position_id) DO UPDATE SET due_on=excluded.due_on,revision=initial_deadlines.revision+1,updated_at=now() RETURNING * INTO result;
 INSERT INTO scl_private.initial_deadline_history(pharmacy_id,year,position_id,before_date,after_date) VALUES(p_pharmacy_id,p_year,p_position_id,old.due_on,p_due_on);
 RETURN to_jsonb(result);
END $$;
REVOKE ALL ON FUNCTION public.scl302_overview(text),public.scl302_set_initial_deadline(text,uuid,integer,text,date,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl302_overview(text),public.scl302_set_initial_deadline(text,uuid,integer,text,date,bigint) TO anon,authenticated;
NOTIFY pgrst,'reload schema';
