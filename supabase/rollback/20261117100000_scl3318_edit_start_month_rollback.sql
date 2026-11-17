-- Rollback για scl3318: επαναφέρει τη λειτουργία scl290_hq_install όπως ήταν στη βάση πριν την αλλαγή (v331.7).
-- Το migration scl3318 εφαρμόστηκε στις 17/11/2026. Αυτό το αρχείο το αναιρεί (md5 ορισμού πριν: 843a2cfa360227f2a5043a401b88ebe1).
CREATE OR REPLACE FUNCTION public.scl290_hq_install(p_hq_key text, p_registry_id uuid, p_expected_version bigint, p_year integer, p_prefix text, p_service_from date, p_positions jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r public.scl290_registry; old public.scl290_installations; cfg public.scl290_installations;
  pos jsonb; previous jsonb; arr jsonb:='[]'; n integer:=0; np integer:=0; ne integer:=0; k integer; cat text; sh integer; pid text; typ text; nm text; fmt text; startdate date; stopdate date;
  legacy_ids jsonb; yy integer; st jsonb; oldrows jsonb; olddeals jsonb; mm jsonb; dd jsonb; tok text;
BEGIN
  PERFORM public.scl290_assert_hq(p_hq_key);
  IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('scl294_players'));
  SELECT * INTO r FROM public.scl290_registry WHERE id=p_registry_id FOR UPDATE;
  IF NOT FOUND OR r.pharmacy_id IS NULL THEN RAISE EXCEPTION 'Ενεργοποιήστε πρώτα το φαρμακείο'; END IF;
  SELECT * INTO old FROM public.scl290_installations WHERE pharmacy_id=r.pharmacy_id FOR UPDATE;
  IF coalesce(old.version,0) IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION 'INSTALLATION_CHANGED: Ανανεώστε τη ρύθμιση θέσεων'; END IF;
  IF coalesce(p_prefix,'') !~ '^[A-Z][A-Z0-9_]{1,59}$' THEN RAISE EXCEPTION 'Χρησιμοποιήστε λατινικά κεφαλαία, αριθμούς και κάτω παύλα στο όνομα player'; END IF;
  IF EXISTS(SELECT 1 FROM public.scl290_registry x WHERE x.id<>r.id AND x.pharmacy_id IS NOT NULL AND x.player_prefix=p_prefix) THEN RAISE EXCEPTION 'Το πρόθεμα χρησιμοποιείται ήδη. Προσθέστε περιοχή ή κωδικό τιμολόγησης'; END IF;
  IF old.pharmacy_id IS NOT NULL AND r.player_prefix IS DISTINCT FROM p_prefix THEN RAISE EXCEPTION 'Η ονομασία των ήδη ορισμένων players παραμένει σταθερή'; END IF;
  IF NOT r.legacy AND old.pharmacy_id IS NULL AND p_service_from IS NULL THEN RAISE EXCEPTION 'Ορίστε μήνα έναρξης λειτουργίας'; END IF;
  IF p_service_from IS NOT NULL AND extract(day FROM p_service_from)<>1 THEN RAISE EXCEPTION 'Η έναρξη ορίζεται ανά μήνα'; END IF;
  IF jsonb_typeof(p_positions) IS DISTINCT FROM 'array' OR jsonb_array_length(p_positions)<1 OR jsonb_array_length(p_positions)>51 THEN RAISE EXCEPTION 'Απαιτείται τουλάχιστον η θέση PharmaPlus'; END IF;
  IF old.pharmacy_id IS NOT NULL AND jsonb_array_length(p_positions)<jsonb_array_length(old.positions) THEN RAISE EXCEPTION 'Δεν αφαιρούνται υπάρχουσες θέσεις'; END IF;
  SELECT coalesce(jsonb_agg(DISTINCT c->>'id'),'[]') INTO legacy_ids FROM public.pharmacy_state s,
    LATERAL jsonb_array_elements(coalesce(s.state_json->'cards','[]')) c WHERE s.pharmacy_id=r.pharmacy_id;
  FOR pos IN SELECT value FROM jsonb_array_elements(p_positions) LOOP
    cat:=coalesce(nullif(pos->>'category',''),'ADV');
    IF cat NOT IN ('ADV','PROMO','EXP') THEN RAISE EXCEPTION 'Μη έγκυρο είδος θέσης'; END IF;
    IF cat='ADV' THEN
      IF np>0 OR ne>0 THEN RAISE EXCEPTION 'Οι θέσεις πάγκου καταχωρίζονται πριν από τα Promotion και τα Experience'; END IF;
      k:=n;
      pid:=CASE WHEN k=0 THEN 'hq' WHEN k<=2 THEN 'base-'||k ELSE 'extra-'||(k-2) END;
      typ:=CASE WHEN k=0 THEN 'hq' WHEN k<=2 THEN 'base' ELSE 'extra' END;
      nm:=CASE WHEN k=0 THEN 'Pharmaplus' ELSE 'Θέση '||k END;
      sh:=NULL;
    ELSIF cat='PROMO' THEN
      k:=np+1;
      pid:='promo-'||k; typ:='promo'; nm:='Promotion '||k;
      IF coalesce(pos->>'shelves','') !~ '^[0-9]{1,2}$' OR (pos->>'shelves')::integer>12 THEN RAISE EXCEPTION 'Ορίστε τον αριθμό των ραφιών (0 έως 12)'; END IF;
      sh:=(pos->>'shelves')::integer;
    ELSE
      k:=ne+1;
      pid:='exp-'||k; typ:='exp'; nm:='Experience '||k;
      IF coalesce(pos->>'shelves','') !~ '^[0-9]{1,2}$' OR (pos->>'shelves')::integer NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'Ορίστε τον αριθμό των ραφιών (1 έως 12)'; END IF;
      sh:=(pos->>'shelves')::integer;
    END IF;
    fmt:=pos->>'screenFormat';startdate:=nullif(pos->>'startsOn','')::date;
    previous:=NULL;
    SELECT v INTO previous FROM jsonb_array_elements(coalesce(old.positions,'[]'::jsonb)) v WHERE v->>'id'=pid LIMIT 1;
    IF fmt NOT IN ('horizontal','vertical') OR fmt IS NULL THEN RAISE EXCEPTION 'Ορίστε orientation για κάθε θέση'; END IF;
    IF pos->>'id' IS DISTINCT FROM pid OR (pos->>'ordinal')::integer IS DISTINCT FROM k THEN RAISE EXCEPTION 'Η αρίθμηση των θέσεων πρέπει να παραμένει σταθερή'; END IF;
    IF previous IS NOT NULL THEN
      IF previous->>'id'<>pid OR previous->>'screenFormat'<>fmt OR nullif(previous->>'startsOn','')::date IS DISTINCT FROM startdate
         OR (cat IN ('PROMO','EXP') AND (previous->>'shelves') IS DISTINCT FROM sh::text) THEN
        RAISE EXCEPTION 'Οι ήδη αποθηκευμένες θέσεις παραμένουν σταθερές. Προσθέστε μόνο τις νέες';
      END IF;
      stopdate:=coalesce(nullif(pos->>'stopsOn','')::date,nullif(previous->>'stopsOn','')::date);
      IF stopdate IS DISTINCT FROM nullif(previous->>'stopsOn','')::date THEN
        IF previous->>'stopsOn' IS NOT NULL THEN RAISE EXCEPTION 'Η παύση έχει ήδη καταχωριστεί'; END IF;
        IF extract(day FROM stopdate)<>1 OR stopdate<=date_trunc('month',scl_private.today())::date OR stopdate<=startdate THEN RAISE EXCEPTION 'Η παύση ορίζεται από μελλοντικό μήνα, μετά την έναρξη'; END IF;
        previous:=previous||jsonb_build_object('stopsOn',stopdate);
      END IF;
      arr:=arr||jsonb_build_array(previous||jsonb_build_object('title',nm));
    ELSE
      IF nullif(pos->>'stopsOn','') IS NOT NULL THEN RAISE EXCEPTION 'Αποθηκεύστε πρώτα τη νέα θέση'; END IF;
      IF startdate IS NULL AND NOT (r.legacy AND legacy_ids ? pid) THEN RAISE EXCEPTION 'Ορίστε μήνα έναρξης για κάθε νέα θέση'; END IF;
      IF startdate IS NOT NULL AND (extract(day FROM startdate)<>1 OR extract(year FROM startdate)<>p_year) THEN RAISE EXCEPTION 'Ο μήνας έναρξης πρέπει να ανήκει στο επιλεγμένο έτος'; END IF;
      IF NOT r.legacy AND startdate<coalesce(old.service_from,p_service_from) THEN RAISE EXCEPTION 'Η θέση δεν μπορεί να ξεκινά πριν από το φαρμακείο'; END IF;
      IF cat='ADV' THEN
        arr:=arr||jsonb_build_array(jsonb_build_object('id',pid,'ordinal',k,'type',typ,'title',nm,'screenFormat',fmt,
          'startsOn',startdate,'configuredYear',p_year,'playerCode',p_prefix||'_ADV'||k||'_'||CASE fmt WHEN 'vertical' THEN 'P' ELSE 'L' END,
          'contentCode',p_prefix||'_ADV'||k||'_'||CASE fmt WHEN 'vertical' THEN 'P' ELSE 'L' END));
      ELSE
        arr:=arr||jsonb_build_array(jsonb_build_object('id',pid,'ordinal',k,'type',typ,'category',cat,'shelves',sh,'title',nm,'screenFormat',fmt,
          'startsOn',startdate,'configuredYear',p_year,'playerCode',p_prefix||'_'||cat||k||'_'||CASE fmt WHEN 'vertical' THEN 'P' ELSE 'L' END,
          'contentCode',p_prefix||'_'||cat||k||'_'||CASE fmt WHEN 'vertical' THEN 'P' ELSE 'L' END));
      END IF;
    END IF;
    IF cat='ADV' THEN n:=n+1; ELSIF cat='PROMO' THEN np:=np+1; ELSE ne:=ne+1; END IF;
  END LOOP;
  IF n<1 THEN RAISE EXCEPTION 'Απαιτείται τουλάχιστον η θέση PharmaPlus'; END IF;
  IF old.pharmacy_id IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(old.positions) o
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(arr) a WHERE a->>'id'=o->>'id')) THEN
    RAISE EXCEPTION 'Δεν αφαιρούνται υπάρχουσες θέσεις';
  END IF;
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
  INSERT INTO public.scl294_installation_history(pharmacy_id,kind,previous,current) VALUES(r.pharmacy_id,'installation',to_jsonb(old),to_jsonb(cfg));
  RETURN to_jsonb(cfg);
END $function$;
