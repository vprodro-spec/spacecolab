CREATE OR REPLACE FUNCTION public.scl290_hq_activate(p_hq_key text, p_id uuid, p_existing_pharmacy_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r public.scl290_registry; old public.scl290_registry; pid uuid; created jsonb; ph jsonb;
BEGIN
  PERFORM public.scl290_assert_hq(p_hq_key);
  SELECT * INTO r FROM public.scl290_registry WHERE id=p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Δεν βρέθηκε εγγραφή'; END IF;
  IF r.pharmacy_id IS NOT NULL THEN
    SELECT to_jsonb(p) INTO ph FROM public.pharmacies p WHERE id=r.pharmacy_id; RETURN ph;
  END IF;
  IF r.billing_code IS NULL OR r.address='' OR r.area='' THEN RAISE EXCEPTION 'Συμπληρώστε πρώτα τα τέσσερα στοιχεία του φαρμακείου'; END IF;
  IF p_existing_pharmacy_id IS NOT NULL THEN
    SELECT * INTO old FROM public.scl290_registry WHERE pharmacy_id=p_existing_pharmacy_id FOR UPDATE;
    IF NOT FOUND OR NOT old.legacy OR old.billing_code IS NOT NULL THEN RAISE EXCEPTION 'Το υπάρχον φαρμακείο έχει ήδη αντιστοιχιστεί'; END IF;
    pid:=old.pharmacy_id;
    DELETE FROM public.scl290_registry WHERE id=old.id;
  ELSE
    SELECT to_jsonb(x) INTO created FROM public.create_pharmacy(r.name) x LIMIT 1;
    pid:=coalesce(created->>'id',created->>'pharmacy_id')::uuid;
    IF pid IS NULL THEN RAISE EXCEPTION 'Η δημιουργία δεν επέστρεψε αναγνωριστικό φαρμακείου'; END IF;
  END IF;
  UPDATE public.scl290_registry SET pharmacy_id=pid,legacy=(p_existing_pharmacy_id IS NOT NULL),player_prefix=old.player_prefix,revision=revision+1,updated_at=now() WHERE id=p_id;
  UPDATE public.pharmacies SET name=r.name WHERE id=pid;
  SELECT to_jsonb(p) INTO ph FROM public.pharmacies p WHERE id=pid;
  RETURN ph;
END $function$;

CREATE OR REPLACE FUNCTION public.scl290_hq_install(p_hq_key text, p_registry_id uuid, p_expected_version bigint, p_year integer, p_prefix text, p_service_from date, p_positions jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r public.scl290_registry; old public.scl290_installations; cfg public.scl290_installations;
  pos jsonb; previous jsonb; arr jsonb:='[]'; n integer:=0; pid text; typ text; nm text; fmt text; startdate date;
  legacy_ids jsonb; yy integer; st jsonb; oldrows jsonb; olddeals jsonb; mm jsonb; dd jsonb; tok text;
BEGIN
  PERFORM public.scl290_assert_hq(p_hq_key);
  IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος'; END IF;
  SELECT * INTO r FROM public.scl290_registry WHERE id=p_registry_id FOR UPDATE;
  IF NOT FOUND OR r.pharmacy_id IS NULL THEN RAISE EXCEPTION 'Ενεργοποιήστε πρώτα το φαρμακείο'; END IF;
  SELECT * INTO old FROM public.scl290_installations WHERE pharmacy_id=r.pharmacy_id FOR UPDATE;
  IF coalesce(old.version,0) IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION 'INSTALLATION_CHANGED: Ανανεώστε τη ρύθμιση θέσεων'; END IF;
  IF coalesce(p_prefix,'') !~ '^[A-Z][A-Z0-9_]{1,59}$' THEN RAISE EXCEPTION 'Χρησιμοποιήστε λατινικά κεφαλαία, αριθμούς και κάτω παύλα στο όνομα player'; END IF;
  IF old.pharmacy_id IS NOT NULL AND r.player_prefix IS DISTINCT FROM p_prefix THEN RAISE EXCEPTION 'Η ονομασία των ήδη ορισμένων players παραμένει σταθερή'; END IF;
  IF NOT r.legacy AND old.pharmacy_id IS NULL AND p_service_from IS NULL THEN RAISE EXCEPTION 'Ορίστε μήνα έναρξης λειτουργίας'; END IF;
  IF p_service_from IS NOT NULL AND extract(day FROM p_service_from)<>1 THEN RAISE EXCEPTION 'Η έναρξη ορίζεται ανά μήνα'; END IF;
  IF jsonb_typeof(p_positions) IS DISTINCT FROM 'array' OR jsonb_array_length(p_positions)<1 OR jsonb_array_length(p_positions)>51 THEN RAISE EXCEPTION 'Απαιτείται τουλάχιστον η θέση PharmaPlus'; END IF;
  IF old.pharmacy_id IS NOT NULL AND jsonb_array_length(p_positions)<jsonb_array_length(old.positions) THEN RAISE EXCEPTION 'Δεν αφαιρούνται υπάρχουσες θέσεις'; END IF;
  SELECT coalesce(jsonb_agg(DISTINCT c->>'id'),'[]') INTO legacy_ids FROM public.pharmacy_state s,
    LATERAL jsonb_array_elements(coalesce(s.state_json->'cards','[]')) c WHERE s.pharmacy_id=r.pharmacy_id;
  FOR pos IN SELECT value FROM jsonb_array_elements(p_positions) LOOP
    pid:=CASE WHEN n=0 THEN 'hq' WHEN n<=2 THEN 'base-'||n ELSE 'extra-'||(n-2) END;
    typ:=CASE WHEN n=0 THEN 'hq' WHEN n<=2 THEN 'base' ELSE 'extra' END;
    nm:=CASE WHEN n=0 THEN 'Pharmaplus' WHEN n<=2 THEN 'Θέση Φαρμακείου '||n ELSE 'Extra Θέση '||(n-2) END;
    fmt:=pos->>'screenFormat';startdate:=nullif(pos->>'startsOn','')::date;previous:=old.positions->n;
    IF fmt NOT IN ('horizontal','vertical') OR fmt IS NULL THEN RAISE EXCEPTION 'Ορίστε orientation για κάθε θέση'; END IF;
    IF previous IS NOT NULL THEN
      IF previous->>'id'<>pid OR previous->>'screenFormat'<>fmt OR nullif(previous->>'startsOn','')::date IS DISTINCT FROM startdate THEN
        RAISE EXCEPTION 'Οι ήδη αποθηκευμένες θέσεις παραμένουν σταθερές. Προσθέστε μόνο τις νέες';
      END IF;
      arr:=arr||jsonb_build_array(previous);
    ELSE
      IF startdate IS NULL AND NOT (r.legacy AND legacy_ids ? pid) THEN RAISE EXCEPTION 'Ορίστε μήνα έναρξης για κάθε νέα θέση'; END IF;
      IF startdate IS NOT NULL AND (extract(day FROM startdate)<>1 OR extract(year FROM startdate)<>p_year) THEN RAISE EXCEPTION 'Ο μήνας έναρξης πρέπει να ανήκει στο επιλεγμένο έτος'; END IF;
      IF NOT r.legacy AND startdate<coalesce(old.service_from,p_service_from) THEN RAISE EXCEPTION 'Η θέση δεν μπορεί να ξεκινά πριν από το φαρμακείο'; END IF;
      arr:=arr||jsonb_build_array(jsonb_build_object('id',pid,'ordinal',n,'type',typ,'title',nm,'screenFormat',fmt,
        'startsOn',startdate,'configuredYear',p_year,'playerCode',p_prefix||'_ADV'||n||'_'||CASE fmt WHEN 'vertical' THEN 'P' ELSE 'L' END,
        'contentCode',p_prefix||'_ADV'||n||'_'||CASE fmt WHEN 'vertical' THEN 'P' ELSE 'L' END));
    END IF;
    n:=n+1;
  END LOOP;
  -- Preserve every existing position from legacy annual snapshots; never silently discard data.
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(legacy_ids) x(value)
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(arr) a WHERE a->>'id'=x.value)) THEN
    RAISE EXCEPTION 'Υπάρχουν ήδη αποθηκευμένες θέσεις. Διατηρήστε όλες τις υπάρχουσες θέσεις';
  END IF;
  UPDATE public.scl290_registry SET player_prefix=p_prefix,revision=revision+1,updated_at=now() WHERE id=r.id;
  INSERT INTO public.scl290_installations(pharmacy_id,positions,service_from)
    VALUES(r.pharmacy_id,arr,CASE WHEN r.legacy THEN NULL ELSE p_service_from END)
    ON CONFLICT(pharmacy_id) DO UPDATE SET positions=excluded.positions,version=scl290_installations.version+1,updated_at=now()
    RETURNING * INTO cfg;
  SELECT token::text INTO tok FROM public.pharmacies WHERE id=r.pharmacy_id;
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO oldrows FROM public.hq_get_position_months(p_hq_key) x WHERE x.pharmacy_id=r.pharmacy_id;
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO olddeals FROM public.hq_get_deals(p_hq_key) x WHERE x.pharmacy_id=r.pharmacy_id;
  FOR yy IN SELECT DISTINCT y FROM (SELECT year y FROM public.pharmacy_state WHERE pharmacy_id=r.pharmacy_id UNION SELECT year FROM public.scl290_snapshots WHERE pharmacy_id=r.pharmacy_id UNION SELECT p_year) q LOOP
    SELECT state_json,months_json,deals_json INTO st,mm,dd FROM public.scl290_snapshots WHERE pharmacy_id=r.pharmacy_id AND year=yy;
    IF st IS NULL THEN SELECT state_json INTO st FROM public.pharmacy_state WHERE pharmacy_id=r.pharmacy_id AND year=yy; END IF;
    st:=public.scl290_merge_state(r.pharmacy_id,yy,coalesce(st,jsonb_build_object('turnover',0,'cards','[]'::jsonb)));
    IF mm IS NULL THEN SELECT coalesce(jsonb_agg(v),'[]') INTO mm FROM jsonb_array_elements(oldrows) v WHERE (v->>'year')::integer=yy; END IF;
    IF dd IS NULL THEN SELECT coalesce(jsonb_agg(v),'[]') INTO dd FROM jsonb_array_elements(olddeals) v WHERE (v->>'year')::integer=yy; END IF;
    mm:=public.scl290_clean_months(r.pharmacy_id,yy,st,mm);dd:=public.scl290_clean_deals(r.pharmacy_id,yy,st,dd);
    INSERT INTO public.scl290_snapshots(pharmacy_id,year,state_json,months_json,deals_json) VALUES(r.pharmacy_id,yy,st,mm,dd)
      ON CONFLICT(pharmacy_id,year) DO UPDATE SET state_json=excluded.state_json,months_json=excluded.months_json,deals_json=excluded.deals_json,revision=scl290_snapshots.revision+1,updated_at=now();
    PERFORM set_config('scl290.authorized_write','yes',true);
    PERFORM public.upsert_pharmacy_state_by_token(tok,yy,st);
    PERFORM set_config('scl290.authorized_write','no',true);
    st:=NULL;mm:=NULL;dd:=NULL;
  END LOOP;
  RETURN to_jsonb(cfg);
END $function$;

CREATE OR REPLACE FUNCTION public.scl290_hq_registry_save(p_hq_key text, p_id uuid, p_expected_revision bigint, p_record jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r public.scl290_registry; nm text:=btrim(p_record->>'name'); bc text:=nullif(btrim(p_record->>'billing_code'),'');
BEGIN
  PERFORM public.scl290_assert_hq(p_hq_key);
  IF coalesce(nm,'')='' OR bc IS NULL OR coalesce(btrim(p_record->>'address'),'')='' OR coalesce(btrim(p_record->>'area'),'')='' THEN
    RAISE EXCEPTION 'Συμπληρώστε επωνυμία, κωδικό τιμολόγησης, διεύθυνση και περιοχή';
  END IF;
  IF p_id IS NULL THEN
    INSERT INTO public.scl290_registry(name,billing_code,address,area) VALUES(nm,bc,btrim(p_record->>'address'),btrim(p_record->>'area')) RETURNING * INTO r;
  ELSE
    SELECT * INTO r FROM public.scl290_registry WHERE id=p_id FOR UPDATE;
    IF NOT FOUND OR r.revision IS DISTINCT FROM p_expected_revision THEN RAISE EXCEPTION 'REGISTRY_CHANGED: Ανανεώστε τη λίστα'; END IF;
    UPDATE public.scl290_registry SET name=nm,billing_code=bc,address=btrim(p_record->>'address'),area=btrim(p_record->>'area'),revision=revision+1,updated_at=now() WHERE id=p_id RETURNING * INTO r;
    IF r.pharmacy_id IS NOT NULL THEN UPDATE public.pharmacies SET name=nm WHERE id=r.pharmacy_id; END IF;
  END IF;
  RETURN to_jsonb(r);
END $function$;

