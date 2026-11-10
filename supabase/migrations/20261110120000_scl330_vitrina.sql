-- v330.0 «Βιτρίνα»: αποκλειστικά ΠΡΟΣΘΗΚΕΣ. Καμία υπάρχουσα συνάρτηση, πίνακας ή γραμμή δεν αλλάζει.
-- Η Βιτρίνα είναι ιδιωτικό εργαλείο του φαρμακείου: δεν υπάρχει καμία συνάρτηση hq_* και το HQ δεν βλέπει τίποτα από αυτήν.

-- 0. Αντίγραφο ασφαλείας: ο ορισμός κάθε υπάρχουσας public συνάρτησης, πριν από οποιαδήποτε αλλαγή.
CREATE TABLE scl_private.backup_v330_functions AS
 SELECT p.proname::text AS fn, pg_get_functiondef(p.oid) AS definition, now() AS taken_at
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.prokind='f';
ALTER TABLE scl_private.backup_v330_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v330_functions FROM PUBLIC,anon,authenticated;

-- 1. Πίνακες (ιδιωτικό σχήμα, RLS ενεργό χωρίς πολιτικές: καμία άμεση πρόσβαση από τον browser).
CREATE TABLE scl_private.vitrina_settings(
 pharmacy_id uuid PRIMARY KEY REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 activated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE scl_private.vitrina_facades(
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 facade_no smallint NOT NULL CHECK(facade_no BETWEEN 1 AND 3),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 80),
 design jsonb NOT NULL CHECK(octet_length(design::text)<=200000),
 revision bigint NOT NULL DEFAULT 1,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(pharmacy_id,facade_no)
);

CREATE TABLE scl_private.vitrina_bookings(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 pharmacy_id uuid NOT NULL,
 facade_no smallint NOT NULL,
 position_id text NOT NULL CHECK(length(position_id) BETWEEN 1 AND 60),
 brand text NOT NULL CHECK(length(btrim(brand)) BETWEEN 1 AND 80),
 start_on date NOT NULL,
 end_on date NOT NULL CHECK(end_on>=start_on),
 status text NOT NULL CHECK(status IN ('discussion','closed')),
 amount numeric(12,2) CHECK(amount IS NULL OR (amount<>'NaN' AND amount>=0)),
 note text NOT NULL DEFAULT '' CHECK(length(note)<=300),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(pharmacy_id,facade_no) REFERENCES scl_private.vitrina_facades(pharmacy_id,facade_no) ON DELETE CASCADE
);
CREATE INDEX vitrina_bookings_lookup ON scl_private.vitrina_bookings(pharmacy_id,facade_no,position_id,start_on);

ALTER TABLE scl_private.vitrina_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.vitrina_facades ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.vitrina_bookings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.vitrina_settings,scl_private.vitrina_facades,scl_private.vitrina_bookings FROM PUBLIC,anon,authenticated;

-- 2. Εσωτερικές βοηθητικές συναρτήσεις (δεν δίνονται σε anon/authenticated).
-- Οι θέσεις μιας όψης: «κομμάτι.αύξων» (0,1,2…) για κάθε όνομα θέσης. Η επάνω σειρά μετράει μόνο όταν twoTier=true.
CREATE FUNCTION scl_private.vitrina_position_ids(p_design jsonb) RETURNS text[]
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT coalesce(array_agg((pc.v->>'id')||'.'||((n.i-1)::text)),'{}'::text[])
 FROM (
  SELECT v FROM jsonb_array_elements(p_design->'pieces') v
  UNION ALL
  SELECT v FROM jsonb_array_elements(CASE WHEN p_design->>'twoTier'='true' THEN p_design->'upPieces' ELSE '[]'::jsonb END) v
 ) pc, LATERAL generate_series(1,coalesce(jsonb_array_length(pc.v->'names'),0)) n(i);
$$;

-- Έλεγχος σχήματος της όψης (ό,τι στέλνει ο browser δεν εμπιστεύεται).
CREATE FUNCTION scl_private.vitrina_check_design(d jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE pc jsonb;nm jsonb;ids text[]:='{}';
BEGIN
 IF d IS NULL OR jsonb_typeof(d) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Μη έγκυρη όψη βιτρίνας';END IF;
 IF octet_length(d::text)>200000 THEN RAISE EXCEPTION 'Η όψη είναι υπερβολικά μεγάλη';END IF;
 IF jsonb_typeof(d->'pieces') IS DISTINCT FROM 'array' OR jsonb_typeof(d->'upPieces') IS DISTINCT FROM 'array' OR jsonb_typeof(d->'twoTier') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Μη έγκυρη όψη βιτρίνας';END IF;
 IF coalesce(d->>'signPos','') NOT IN ('top','mid') THEN RAISE EXCEPTION 'Μη έγκυρη όψη βιτρίνας';END IF;
 IF d ? 'meta' AND jsonb_typeof(d->'meta') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Μη έγκυρη όψη βιτρίνας';END IF;
 IF jsonb_array_length(d->'pieces') NOT BETWEEN 1 AND 200 OR jsonb_array_length(d->'upPieces')>200 THEN RAISE EXCEPTION 'Μη έγκυρος αριθμός κομματιών';END IF;
 FOR pc IN SELECT value FROM jsonb_array_elements(d->'pieces') UNION ALL SELECT value FROM jsonb_array_elements(d->'upPieces') LOOP
  IF jsonb_typeof(pc) IS DISTINCT FROM 'object' OR jsonb_typeof(pc->'id') IS DISTINCT FROM 'string' OR jsonb_typeof(pc->'w') IS DISTINCT FROM 'number' OR jsonb_typeof(pc->'names') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Μη έγκυρο κομμάτι όψης';END IF;
  IF length(pc->>'id') NOT BETWEEN 1 AND 20 OR coalesce(pc->>'type','') NOT IN ('glass','panel','column','door') OR (pc->>'id')=ANY(ids) THEN RAISE EXCEPTION 'Μη έγκυρο κομμάτι όψης';END IF;
  IF (pc->>'w')::numeric NOT BETWEEN 1 AND 100000 OR jsonb_array_length(pc->'names')>60 THEN RAISE EXCEPTION 'Μη έγκυρο κομμάτι όψης';END IF;
  ids:=ids||(pc->>'id');
  FOR nm IN SELECT value FROM jsonb_array_elements(pc->'names') LOOP
   IF jsonb_typeof(nm) IS DISTINCT FROM 'string' OR length(nm#>>'{}')>80 THEN RAISE EXCEPTION 'Μη έγκυρο όνομα θέσης';END IF;
  END LOOP;
 END LOOP;
END $$;

-- Περίοδος κράτησης: ολόκληροι μήνες (1η έως τελευταία του μήνα) ή ολόκληρες εβδομάδες (Δευτέρα έως Κυριακή).
CREATE FUNCTION scl_private.vitrina_period_ok(s date,e date) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT s IS NOT NULL AND e IS NOT NULL AND s<=e AND s>=DATE '2020-01-01' AND e<=DATE '2100-12-31' AND (e-s+1)<=400 AND (
  (extract(day FROM s)=1 AND e=((date_trunc('month',e)+interval '1 month')-interval '1 day')::date)
  OR (extract(isodow FROM s)=1 AND extract(isodow FROM e)=7 AND (e-s+1)%7=0)
 );
$$;

-- Κλείδωμα ανά φαρμακείο: όλες οι αλλαγές του ίδιου φαρμακείου γίνονται η μία μετά την άλλη. Απαιτεί ενεργοποιημένη Βιτρίνα.
CREATE FUNCTION scl_private.vitrina_lock(p_pid uuid) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM scl_private.vitrina_settings WHERE pharmacy_id=p_pid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Η Βιτρίνα δεν έχει ενεργοποιηθεί';END IF;
END $$;

-- Πλήρης κατάσταση που επιστρέφουν όλες οι συναρτήσεις.
CREATE FUNCTION scl_private.vitrina_state(p_pid uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT jsonb_build_object(
  'activated',EXISTS(SELECT 1 FROM scl_private.vitrina_settings WHERE pharmacy_id=p_pid),
  'today',to_char(scl_private.today(),'YYYY-MM-DD'),
  'facades',coalesce((SELECT jsonb_agg(jsonb_build_object('facade_no',facade_no,'name',name,'design',design,'revision',revision,'updated_at',updated_at) ORDER BY facade_no) FROM scl_private.vitrina_facades WHERE pharmacy_id=p_pid),'[]'::jsonb),
  'bookings',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'facade_no',facade_no,'position_id',position_id,'brand',brand,'start',to_char(start_on,'YYYY-MM-DD'),'end',to_char(end_on,'YYYY-MM-DD'),'status',status,'amount',amount,'note',note) ORDER BY facade_no,start_on,position_id) FROM scl_private.vitrina_bookings WHERE pharmacy_id=p_pid),'[]'::jsonb)
 );
$$;

REVOKE ALL ON FUNCTION scl_private.vitrina_position_ids(jsonb),scl_private.vitrina_check_design(jsonb),scl_private.vitrina_period_ok(date,date),scl_private.vitrina_lock(uuid),scl_private.vitrina_state(uuid) FROM PUBLIC,anon,authenticated;

-- 3. Συναρτήσεις του φαρμακείου (πρόσβαση με το token του φαρμακείου, όπως όλες οι υπόλοιπες).
CREATE FUNCTION public.scl330_vitrina_get(p_token text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 RETURN scl_private.vitrina_state(public.scl290_token_id(p_token));
END $$;

CREATE FUNCTION public.scl330_vitrina_activate(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token);
BEGIN
 INSERT INTO scl_private.vitrina_settings(pharmacy_id) VALUES(pid) ON CONFLICT DO NOTHING;
 RETURN scl_private.vitrina_state(pid);
END $$;

CREATE FUNCTION public.scl330_vitrina_save_facade(p_token text,p_facade_no integer,p_expected_revision bigint,p_name text,p_design jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token);cur bigint;nm text:=btrim(coalesce(p_name,''));blocked integer;
BEGIN
 PERFORM scl_private.vitrina_lock(pid);
 IF p_facade_no IS NULL OR p_facade_no NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'Μη έγκυρος αριθμός όψης (1 έως 3)';END IF;
 IF length(nm) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Γράψτε όνομα όψης (έως 80 χαρακτήρες)';END IF;
 PERFORM scl_private.vitrina_check_design(p_design);
 SELECT revision INTO cur FROM scl_private.vitrina_facades WHERE pharmacy_id=pid AND facade_no=p_facade_no FOR UPDATE;
 IF NOT FOUND THEN
  IF coalesce(p_expected_revision,0)<>0 THEN RAISE EXCEPTION 'Η όψη δεν υπάρχει πια. Ανανεώστε τη σελίδα.';END IF;
  INSERT INTO scl_private.vitrina_facades(pharmacy_id,facade_no,name,design) VALUES(pid,p_facade_no,nm,p_design);
 ELSE
  IF p_expected_revision IS DISTINCT FROM cur THEN RAISE EXCEPTION 'Η όψη άλλαξε από άλλη συσκευή. Ανανεώστε πριν αποθηκεύσετε.';END IF;
  SELECT count(*) INTO blocked FROM scl_private.vitrina_bookings WHERE pharmacy_id=pid AND facade_no=p_facade_no AND NOT (position_id=ANY(scl_private.vitrina_position_ids(p_design)));
  IF blocked>0 THEN RAISE EXCEPTION 'Η αλλαγή αφαιρεί θέσεις που έχουν κρατήσεις (% κρατήσεις). Διαγράψτε πρώτα τις κρατήσεις τους.',blocked;END IF;
  UPDATE scl_private.vitrina_facades SET name=nm,design=p_design,revision=revision+1,updated_at=now() WHERE pharmacy_id=pid AND facade_no=p_facade_no;
 END IF;
 RETURN scl_private.vitrina_state(pid);
END $$;

CREATE FUNCTION public.scl330_vitrina_delete_facade(p_token text,p_facade_no integer,p_expected_revision bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token);cur bigint;
BEGIN
 PERFORM scl_private.vitrina_lock(pid);
 SELECT revision INTO cur FROM scl_private.vitrina_facades WHERE pharmacy_id=pid AND facade_no=p_facade_no FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Η όψη δεν υπάρχει πια. Ανανεώστε τη σελίδα.';END IF;
 IF p_expected_revision IS DISTINCT FROM cur THEN RAISE EXCEPTION 'Η όψη άλλαξε από άλλη συσκευή. Ανανεώστε πριν τη διαγράψετε.';END IF;
 DELETE FROM scl_private.vitrina_facades WHERE pharmacy_id=pid AND facade_no=p_facade_no;
 RETURN scl_private.vitrina_state(pid);
END $$;

CREATE FUNCTION public.scl330_vitrina_add_booking(p_token text,p_facade_no integer,p_position_id text,p_brand text,p_start date,p_end date,p_status text,p_amount numeric,p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token);dsg jsonb;b text:=btrim(coalesce(p_brand,''));n text:=btrim(coalesce(p_note,''));clash record;
BEGIN
 PERFORM scl_private.vitrina_lock(pid);
 SELECT f.design INTO dsg FROM scl_private.vitrina_facades f WHERE f.pharmacy_id=pid AND f.facade_no=p_facade_no;
 IF NOT FOUND THEN RAISE EXCEPTION 'Η όψη δεν υπάρχει. Ανανεώστε τη σελίδα.';END IF;
 IF p_position_id IS NULL OR NOT (p_position_id=ANY(scl_private.vitrina_position_ids(dsg))) THEN RAISE EXCEPTION 'Η θέση δεν υπάρχει πια στην όψη. Ανανεώστε τη σελίδα.';END IF;
 IF length(b) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Γράψτε τον προμηθευτή ή τη μάρκα (έως 80 χαρακτήρες)';END IF;
 IF length(n)>300 THEN RAISE EXCEPTION 'Η σημείωση δεν μπορεί να ξεπερνά τους 300 χαρακτήρες';END IF;
 IF p_status IS NULL OR p_status NOT IN ('discussion','closed') THEN RAISE EXCEPTION 'Μη έγκυρη κατάσταση κράτησης';END IF;
 IF p_amount IS NOT NULL AND (p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<0 OR p_amount<>round(p_amount,2) OR p_amount>=10000000000) THEN RAISE EXCEPTION 'Το ποσό πρέπει να είναι αριθμός με έως δύο δεκαδικά';END IF;
 IF NOT scl_private.vitrina_period_ok(p_start,p_end) THEN RAISE EXCEPTION 'Η κράτηση γίνεται για ολόκληρους μήνες ή ολόκληρες εβδομάδες (Δευτέρα έως Κυριακή)';END IF;
 SELECT k.brand,k.start_on,k.end_on INTO clash FROM scl_private.vitrina_bookings k WHERE k.pharmacy_id=pid AND k.facade_no=p_facade_no AND k.position_id=p_position_id AND k.start_on<=p_end AND k.end_on>=p_start ORDER BY k.start_on LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Η θέση έχει ήδη κράτηση (%) στο διάστημα που διαλέξατε',clash.brand;END IF;
 IF (SELECT count(*) FROM scl_private.vitrina_bookings WHERE pharmacy_id=pid)>=1000 THEN RAISE EXCEPTION 'Έχετε φτάσει το όριο των 1000 κρατήσεων';END IF;
 INSERT INTO scl_private.vitrina_bookings(pharmacy_id,facade_no,position_id,brand,start_on,end_on,status,amount,note) VALUES(pid,p_facade_no,p_position_id,b,p_start,p_end,p_status,p_amount,n);
 RETURN scl_private.vitrina_state(pid);
END $$;

CREATE FUNCTION public.scl330_vitrina_delete_booking(p_token text,p_booking_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token);
BEGIN
 PERFORM scl_private.vitrina_lock(pid);
 DELETE FROM scl_private.vitrina_bookings WHERE id=p_booking_id AND pharmacy_id=pid;
 IF NOT FOUND THEN RAISE EXCEPTION 'Η κράτηση δεν βρέθηκε. Ανανεώστε τη σελίδα.';END IF;
 RETURN scl_private.vitrina_state(pid);
END $$;

REVOKE ALL ON FUNCTION public.scl330_vitrina_get(text),public.scl330_vitrina_activate(text),public.scl330_vitrina_save_facade(text,integer,bigint,text,jsonb),public.scl330_vitrina_delete_facade(text,integer,bigint),public.scl330_vitrina_add_booking(text,integer,text,text,date,date,text,numeric,text),public.scl330_vitrina_delete_booking(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl330_vitrina_get(text),public.scl330_vitrina_activate(text),public.scl330_vitrina_save_facade(text,integer,bigint,text,jsonb),public.scl330_vitrina_delete_facade(text,integer,bigint),public.scl330_vitrina_add_booking(text,integer,text,text,date,date,text,numeric,text),public.scl330_vitrina_delete_booking(text,uuid) TO anon,authenticated;
