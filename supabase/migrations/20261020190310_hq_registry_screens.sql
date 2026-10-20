-- v294: HQ registry and installation lifecycle. No existing pharmacy is removed.
CREATE TABLE public.scl294_installation_history(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 kind text NOT NULL,previous jsonb,current jsonb,created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.scl294_installation_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.scl294_installation_history FROM PUBLIC,anon,authenticated;
CREATE FUNCTION scl_private.position_active(p jsonb,y integer,m integer) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT (nullif(coalesce(p->>'startsOn',p->>'installationStart'),'') IS NULL OR coalesce(p->>'startsOn',p->>'installationStart')::date<=make_date(y,m+1,1))
 AND (nullif(p->>'stopsOn','') IS NULL OR (p->>'stopsOn')::date>make_date(y,m+1,1));
$$;
CREATE FUNCTION scl_private.position_at(p jsonb,y integer,m integer) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT coalesce((SELECT h-'until' FROM jsonb_array_elements(coalesce(p->'configurationHistory','[]')) h
 WHERE (h->>'until')::date>make_date(y,m+1,1) ORDER BY h->>'until' LIMIT 1),jsonb_build_object('screenFormat',p->>'screenFormat','playerCode',p->>'playerCode','contentCode',p->>'contentCode'));
$$;
REVOKE ALL ON FUNCTION scl_private.position_active(jsonb,integer,integer),scl_private.position_at(jsonb,integer,integer) FROM PUBLIC,anon,authenticated;
-- Existing v290 normalization functions; no credentials or pharmacy data.
CREATE OR REPLACE FUNCTION public.scl290_merge_state(p_pid uuid,p_year integer,p_state jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE cfg public.scl290_installations; pos jsonb; card jsonb; result jsonb:='[]'; st jsonb:=coalesce(p_state,'{}'); fmt text;
BEGIN
  SELECT * INTO cfg FROM public.scl290_installations WHERE pharmacy_id=p_pid;
  IF NOT FOUND THEN RETURN st; END IF;
  FOR pos IN SELECT value FROM jsonb_array_elements(cfg.positions) LOOP
    IF nullif(pos->>'startsOn','')::date > make_date(p_year,12,31) THEN CONTINUE; END IF;
    SELECT value INTO card FROM jsonb_array_elements(coalesce(st->'cards','[]')) WHERE value->>'id'=pos->>'id' LIMIT 1;
    card:=coalesce(card,jsonb_build_object('initialPlanLocked',pos->>'type'='hq','basicSchedule','[]'::jsonb,
      'simpleSchedule','[]'::jsonb,'pendingSimpleSchedule','[]'::jsonb,'pendingInitialSchedule','[]'::jsonb,
      'confirmedDeals','[]'::jsonb,'preagreements','[]'::jsonb,'sponsoredShelves','[]'::jsonb));
    -- Preserve historical years' existing format. Installation is authoritative from its setup year.
    fmt:=pos->>'screenFormat';
    IF p_year < coalesce((pos->>'configuredYear')::integer,p_year) AND nullif(card->>'screenFormat','') IS NOT NULL THEN fmt:=card->>'screenFormat'; END IF;
    card:=card||jsonb_build_object('id',pos->>'id','type',pos->>'type','title',pos->>'title',
      'screenFormat',fmt,'pendingScreenFormat',fmt,'playerCode',pos->>'playerCode','contentCode',pos->>'contentCode',
      'installationStart',pos->'startsOn','stopsOn',pos->'stopsOn','configurationHistory',coalesce(pos->'configurationHistory','[]'),'installationManaged',true);
    result:=result||jsonb_build_array(card);
  END LOOP;
  RETURN st||jsonb_build_object('cards',result,'totalCounters',jsonb_array_length(result),'setupLocked',true,
    '_scl290InstallationVersion',cfg.version,'_scl290ServiceFrom',cfg.service_from);
END $$;

CREATE OR REPLACE FUNCTION public.scl290_clean_months(p_pid uuid,p_year integer,p_state jsonb,p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE row jsonb; card jsonb; result jsonb:='[]'; m integer; nm text;
BEGIN
  SELECT name INTO nm FROM public.scl290_registry WHERE pharmacy_id=p_pid;
  FOR row IN SELECT value FROM jsonb_array_elements(coalesce(p_rows,'[]')) LOOP
    m:=(row->>'month')::integer;
    IF m NOT BETWEEN 0 AND 11 THEN CONTINUE; END IF;
    SELECT value INTO card FROM jsonb_array_elements(coalesce(p_state->'cards','[]'))
      WHERE value->>'id'=row->>'position_id' OR (value->>'type'='hq' AND row->>'position_id'='pharmaplus') LIMIT 1;
    IF card IS NULL OR (card->>'type'<>'hq' AND coalesce((card->>'initialPlanLocked')::boolean,false)=false) THEN CONTINUE; END IF;
    IF NOT scl_private.position_active(card,p_year,m) THEN CONTINUE; END IF;
    card:=card||scl_private.position_at(card,p_year,m);
    result:=result||jsonb_build_array(row||jsonb_build_object('pharmacy_id',p_pid,'pharmacy_name',nm,'year',p_year,
      'position_id',card->>'id','position_name',card->>'title',
      'position_type',CASE card->>'type' WHEN 'hq' THEN 'pharmaplus' WHEN 'extra' THEN 'extra' ELSE 'pharmacy' END,
      'position_orientation',card->>'screenFormat','player_code',card->>'playerCode','content_code',card->>'contentCode'));
  END LOOP;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.scl290_clean_deals(p_pid uuid,p_year integer,p_state jsonb,p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE row jsonb; card jsonb; result jsonb:='[]'; m integer; nm text;
BEGIN
  SELECT name INTO nm FROM public.scl290_registry WHERE pharmacy_id=p_pid;
  FOR row IN SELECT value FROM jsonb_array_elements(coalesce(p_rows,'[]')) LOOP
    SELECT value INTO card FROM jsonb_array_elements(coalesce(p_state->'cards','[]')) WHERE value->>'id'=row->>'position_id' LIMIT 1;
    IF card IS NULL OR card->>'type'='hq' OR coalesce((card->>'initialPlanLocked')::boolean,false)=false THEN CONTINUE; END IF;
    m:=(row->>'start_month')::integer;
    IF m NOT BETWEEN 0 AND 11 OR nullif(card->>'installationStart','')::date>make_date(p_year,m+1,1) THEN
      RAISE EXCEPTION 'Η συμφωνία ξεκινά πριν από τη λειτουργία της θέσης';
    END IF;
    result:=result||jsonb_build_array(row||jsonb_build_object('pharmacy_id',p_pid,'pharmacy_name',nm,'year',p_year,
      'position_id',card->>'id','position_name',card->>'title','position_type',CASE card->>'type' WHEN 'extra' THEN 'extra' ELSE 'pharmacy' END));
  END LOOP;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION scl_private.blocks(p_year integer,p_state jsonb)
RETURNS TABLE(position_id text,position_name text,category text,start_month integer,end_month integer,description text,event_key text)
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
WITH cards AS (
 SELECT c FROM jsonb_array_elements(coalesce(p_state->'cards','[]')) c
 WHERE c->>'type'<>'hq' AND coalesce((c->>'initialPlanLocked')::boolean,false)
), deals AS (
 SELECT c,d,ord FROM cards CROSS JOIN LATERAL jsonb_array_elements(
 CASE WHEN jsonb_array_length(coalesce(c->'confirmedDeals','[]'))>0 THEN c->'confirmedDeals'
 WHEN c->'negotiation'->>'confirmed'='true' THEN jsonb_build_array(c->'negotiation') ELSE '[]'::jsonb END) WITH ORDINALITY a(d,ord)
 WHERE d->>'confirmed'='true'
), cells AS (
 SELECT c->>'id' pid,c->>'title' pname,'custom'::text kind,m,
 btrim(coalesce(c->'simpleSchedule'->>m,c->'basicSchedule'->>m,'')) label,
 lower(btrim(coalesce(c->'simpleSchedule'->>m,''))) content_key,''::text deal_key
 FROM cards CROSS JOIN generate_series(0,11) m
 WHERE c->>'simpleConfirmed'='true'
 AND btrim(coalesce(c->'simpleSchedule'->>m,''))<>''
 AND btrim(coalesce(c->'simpleSchedule'->>m,''))<>btrim(coalesce(c->'basicSchedule'->>m,''))
 AND scl_private.position_active(c,p_year,m)
 AND NOT EXISTS(SELECT 1 FROM deals WHERE deals.c->>'id'=cards.c->>'id'
 AND m>=coalesce((d->>'startMonth')::integer,0) AND m<coalesce((d->>'startMonth')::integer,0)+greatest(1,coalesce((d->>'duration')::integer,1)))
 UNION ALL
 SELECT c->>'id',c->>'title','deal',m,
 concat_ws(' / ',nullif(d->>'supplier',''),nullif(d->>'brand',''),nullif(d->>'subline',''),nullif(d->>'products',''),
 CASE WHEN d->>'monthlyContentChanges' IS DISTINCT FROM 'false' THEN nullif(d->'monthlySublines'->>m,'') END,
 CASE WHEN d->>'monthlyContentChanges' IS DISTINCT FROM 'false' THEN nullif(d->'monthlyProducts'->>m,'') END),
 lower(concat_ws('|',d->>'supplier',d->>'brand',d->>'subline',d->>'products',
 CASE WHEN d->>'monthlyContentChanges' IS DISTINCT FROM 'false' THEN concat_ws('|',d->'schedule'->>m,d->'monthlySublines'->>m,d->'monthlyProducts'->>m) END)),
 coalesce(d->>'id',d->>'deal_uid',ord::text)
 FROM deals CROSS JOIN LATERAL generate_series(greatest(0,coalesce((d->>'startMonth')::integer,0)),
 least(11,coalesce((d->>'startMonth')::integer,0)+greatest(1,coalesce((d->>'duration')::integer,1))-1)) m
 WHERE scl_private.position_active(c,p_year,m)
), flagged AS (
 SELECT *,CASE WHEN lag(m) OVER w=m-1 AND lag(content_key) OVER w=content_key THEN 0 ELSE 1 END new_group
 FROM cells WINDOW w AS(PARTITION BY pid,kind,deal_key ORDER BY m)
), grouped AS (
 SELECT *,sum(new_group) OVER(PARTITION BY pid,kind,deal_key ORDER BY m) grp FROM flagged
)
SELECT pid,coalesce(pname,pid),kind,min(m),max(m),min(label),
 md5(concat_ws('|',pid,kind,p_year,min(m),content_key,deal_key))
FROM grouped GROUP BY pid,pname,kind,deal_key,content_key,grp ORDER BY pid,min(m),kind;
$$;
CREATE OR REPLACE FUNCTION scl_private.snapshot_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE oldcard jsonb; newcard jsonb; arr jsonb:='[]'; req public.scl292_reset_requests; m integer;
BEGIN
 FOR newcard IN SELECT value FROM jsonb_array_elements(NEW.state_json->'cards') LOOP
  oldcard:=NULL;
  IF TG_OP='UPDATE' THEN SELECT value INTO oldcard FROM jsonb_array_elements(OLD.state_json->'cards') WHERE value->>'id'=newcard->>'id'; END IF;
  IF newcard->>'type'<>'hq' AND newcard->>'initialPlanLocked'='true' AND (oldcard IS NULL OR oldcard->>'initialPlanLocked' IS DISTINCT FROM 'true' OR oldcard->'basicSchedule' IS DISTINCT FROM newcard->'basicSchedule') THEN
   FOR m IN 0..11 LOOP
    IF scl_private.position_active(newcard,NEW.year,m) AND btrim(coalesce(newcard->'basicSchedule'->>m,''))='' THEN RAISE EXCEPTION 'INCOMPLETE_PROGRAM: Συμπληρώστε όλους τους μήνες λειτουργίας της θέσης'; END IF;
   END LOOP;
  END IF;
 END LOOP;
 IF TG_OP='UPDATE' THEN
  PERFORM scl_private.capture_charges(OLD.pharmacy_id,OLD.year,OLD.state_json,OLD.revision);
  IF current_setting('scl292.hq_approval',true) IS DISTINCT FROM 'yes' THEN
   FOR newcard IN SELECT value FROM jsonb_array_elements(NEW.state_json->'cards') LOOP
    SELECT value INTO oldcard FROM jsonb_array_elements(OLD.state_json->'cards') WHERE value->>'id'=newcard->>'id';
    IF oldcard->>'type'<>'hq' AND oldcard->>'initialPlanLocked'='true' THEN
     IF newcard->>'initialPlanLocked' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'HQ_APPROVAL_REQUIRED: Η επαναφορά απαιτεί έγκριση από τα κεντρικά'; END IF;
     IF oldcard->'basicSchedule' IS DISTINCT FROM newcard->'basicSchedule' OR (oldcard ? '_scl292Reset' AND newcard ? '_scl292ResetApplied') THEN
      SELECT * INTO req FROM public.scl292_reset_requests WHERE id::text=oldcard->'_scl292Reset'->>'id'
       AND id::text=newcard->>'_scl292ResetApplied' AND pharmacy_id=OLD.pharmacy_id AND year=OLD.year
       AND position_id=newcard->>'id' AND status='approved' FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'HQ_APPROVAL_REQUIRED: Το Βασικό πρόγραμμα αλλάζει μόνο μετά από έγκριση HQ'; END IF;
      FOR m IN 0..req.from_month-1 LOOP
       IF oldcard->'basicSchedule'->m IS DISTINCT FROM newcard->'basicSchedule'->m
        OR oldcard->'simpleSchedule'->m IS DISTINCT FROM newcard->'simpleSchedule'->m THEN
        RAISE EXCEPTION 'HISTORY_LOCKED: Οι προηγούμενοι μήνες διατηρούνται';
       END IF;
      END LOOP;
      IF oldcard->'confirmedDeals' IS DISTINCT FROM newcard->'confirmedDeals' THEN RAISE EXCEPTION 'Οι υπάρχουσες Συμφωνίες διατηρούνται κατά την επαναφορά'; END IF;
      UPDATE public.scl292_reset_requests SET status='applied',applied_at=now() WHERE id=req.id;
      newcard:=newcard-'_scl292Reset'-'_scl292ResetApplied';
     ELSE
      newcard:=newcard-'_scl292Reset'-'_scl292ResetApplied';
      IF oldcard ? '_scl292Reset' THEN newcard:=newcard||jsonb_build_object('_scl292Reset',oldcard->'_scl292Reset'); END IF;
     END IF;
    ELSE newcard:=newcard-'_scl292Reset'-'_scl292ResetApplied';
    END IF;
    arr:=arr||jsonb_build_array(newcard);
   END LOOP;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(OLD.state_json->'cards') c WHERE c->>'initialPlanLocked'='true' AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(arr) n WHERE n->>'id'=c->>'id')) THEN RAISE EXCEPTION 'HQ_APPROVAL_REQUIRED: Δεν αφαιρούνται οριστικοποιημένες θέσεις'; END IF;
   NEW.state_json:=jsonb_set(NEW.state_json,'{cards}',arr);
  END IF;
  IF OLD.state_json IS DISTINCT FROM NEW.state_json THEN
   INSERT INTO public.scl292_program_history(pharmacy_id,year,revision,state_json,months_json,deals_json,reason)
   VALUES(OLD.pharmacy_id,OLD.year,OLD.revision,OLD.state_json,OLD.months_json,OLD.deals_json,
    CASE WHEN current_setting('scl292.hq_approval',true)='yes' THEN 'Έγκριση επαναφοράς HQ' WHEN req.id IS NOT NULL THEN 'Οριστικοποίηση μετά από έγκριση HQ' ELSE 'Αποθήκευση προγράμματος' END);
  END IF;
 END IF;
 PERFORM scl_private.capture_charges(NEW.pharmacy_id,NEW.year,NEW.state_json,NEW.revision);
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.scl290_hq_install(p_hq_key text, p_registry_id uuid, p_expected_version bigint, p_year integer, p_prefix text, p_service_from date, p_positions jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r public.scl290_registry; old public.scl290_installations; cfg public.scl290_installations;
  pos jsonb; previous jsonb; arr jsonb:='[]'; n integer:=0; pid text; typ text; nm text; fmt text; startdate date; stopdate date;
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
    pid:=CASE WHEN n=0 THEN 'hq' WHEN n<=2 THEN 'base-'||n ELSE 'extra-'||(n-2) END;
    typ:=CASE WHEN n=0 THEN 'hq' WHEN n<=2 THEN 'base' ELSE 'extra' END;
    nm:=CASE WHEN n=0 THEN 'Pharmaplus' ELSE 'Θέση '||n END;
    fmt:=pos->>'screenFormat';startdate:=nullif(pos->>'startsOn','')::date;previous:=old.positions->n;
    IF fmt NOT IN ('horizontal','vertical') OR fmt IS NULL THEN RAISE EXCEPTION 'Ορίστε orientation για κάθε θέση'; END IF;
    IF pos->>'id' IS DISTINCT FROM pid OR (pos->>'ordinal')::integer IS DISTINCT FROM n THEN RAISE EXCEPTION 'Η αρίθμηση των θέσεων πρέπει να παραμένει σταθερή'; END IF;
    IF previous IS NOT NULL THEN
      IF previous->>'id'<>pid OR previous->>'screenFormat'<>fmt OR nullif(previous->>'startsOn','')::date IS DISTINCT FROM startdate THEN
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
  INSERT INTO public.scl294_installation_history(pharmacy_id,kind,previous,current) VALUES(r.pharmacy_id,'installation',to_jsonb(old),to_jsonb(cfg));
  RETURN to_jsonb(cfg);
END $function$;

-- Explicit correction, separate from ordinary adding/pausing positions.
CREATE FUNCTION public.scl294_correct_installation(p_hq_key text,p_registry_id uuid,p_expected_version bigint,p_prefix text,p_formats jsonb,p_from date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.scl290_registry; cfg public.scl290_installations; oldcfg jsonb; p jsonb; a jsonb:='[]'; f text; code text; hist jsonb; s public.scl290_snapshots; st jsonb; tok text;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 PERFORM pg_advisory_xact_lock(hashtext('scl294_players'));
 SELECT * INTO r FROM public.scl290_registry WHERE id=p_registry_id FOR UPDATE;
 IF r.pharmacy_id IS NULL THEN RAISE EXCEPTION 'Δεν υπάρχει ενεργό φαρμακείο'; END IF;
 SELECT * INTO cfg FROM public.scl290_installations WHERE pharmacy_id=r.pharmacy_id FOR UPDATE;
 IF cfg.version IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION 'INSTALLATION_CHANGED: Ανανεώστε τις οθόνες'; END IF;
 IF p_from IS NULL OR extract(day FROM p_from)<>1 OR p_from<>date_trunc('month',scl_private.today())::date THEN RAISE EXCEPTION 'Η διόρθωση εγκατάστασης ισχύει από τον τρέχοντα μήνα'; END IF;
 IF coalesce(p_prefix,'')!~'^[A-Z][A-Z0-9_]{1,59}$' THEN RAISE EXCEPTION 'Μη έγκυρο πρόθεμα player'; END IF;
 IF EXISTS(SELECT 1 FROM public.scl290_registry WHERE id<>r.id AND pharmacy_id IS NOT NULL AND player_prefix=p_prefix) THEN RAISE EXCEPTION 'Το πρόθεμα χρησιμοποιείται ήδη. Προσθέστε περιοχή ή κωδικό τιμολόγησης'; END IF;
 oldcfg:=to_jsonb(cfg);
 FOR p IN SELECT value FROM jsonb_array_elements(cfg.positions) LOOP
  f:=p_formats->>(p->>'id');
  IF f IS NULL OR f NOT IN ('vertical','horizontal') THEN RAISE EXCEPTION 'Ορίστε προσανατολισμό σε κάθε θέση'; END IF;
  code:=p_prefix||'_ADV'||(p->>'ordinal')||'_'||CASE f WHEN 'vertical' THEN 'P' ELSE 'L' END;
  IF p->>'screenFormat' IS DISTINCT FROM f OR p->>'playerCode' IS DISTINCT FROM code THEN
   hist:=coalesce(p->'configurationHistory','[]');
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(hist) h WHERE h->>'until'=p_from::text) THEN
    hist:=hist||jsonb_build_array(jsonb_build_object('until',p_from,'screenFormat',p->>'screenFormat','playerCode',p->>'playerCode','contentCode',p->>'contentCode'));
   END IF;
   p:=p||jsonb_build_object('configurationHistory',hist,'screenFormat',f,'playerCode',code,'contentCode',code);
  END IF;
  a:=a||jsonb_build_array(p);
 END LOOP;
 UPDATE public.scl290_registry SET player_prefix=p_prefix,revision=revision+1,updated_at=now() WHERE id=r.id;
 UPDATE public.scl290_installations SET positions=a,version=version+1,updated_at=now() WHERE pharmacy_id=r.pharmacy_id RETURNING * INTO cfg;
 SELECT token::text INTO tok FROM public.pharmacies WHERE id=r.pharmacy_id;
 FOR s IN SELECT * FROM public.scl290_snapshots WHERE pharmacy_id=r.pharmacy_id FOR UPDATE LOOP
  st:=public.scl290_merge_state(r.pharmacy_id,s.year,s.state_json);
  UPDATE public.scl290_snapshots SET state_json=st,months_json=public.scl290_clean_months(r.pharmacy_id,s.year,st,s.months_json),revision=revision+1,updated_at=now() WHERE pharmacy_id=r.pharmacy_id AND year=s.year;
  PERFORM set_config('scl290.authorized_write','yes',true);
  PERFORM public.upsert_pharmacy_state_by_token(tok,s.year,st);
  PERFORM set_config('scl290.authorized_write','no',true);
 END LOOP;
 INSERT INTO public.scl294_installation_history(pharmacy_id,kind,previous,current) VALUES(r.pharmacy_id,'correction',oldcfg,to_jsonb(cfg));
 RETURN to_jsonb(cfg);
END $$;

CREATE FUNCTION public.scl294_deactivate(p_hq_key text,p_registry_id uuid,p_expected_revision bigint,p_confirmation text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.scl290_registry; pid uuid;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT * INTO r FROM public.scl290_registry WHERE id=p_registry_id FOR UPDATE;
 IF NOT FOUND OR r.pharmacy_id IS NULL OR r.revision IS DISTINCT FROM p_expected_revision THEN RAISE EXCEPTION 'REGISTRY_CHANGED: Ανανεώστε τη λίστα'; END IF;
 IF btrim(p_confirmation) IS DISTINCT FROM r.name THEN RAISE EXCEPTION 'Πληκτρολογήστε την επωνυμία για επιβεβαίωση'; END IF;
 pid:=r.pharmacy_id;
 -- Existing guarded deletion revokes the token and cascades all activation data.
 PERFORM public.hq_delete_pharmacy(p_hq_key,pid);
 DELETE FROM public.hq_changes_done WHERE position(pid::text in change_key)>0;
 DELETE FROM public.scl292_completion_history WHERE position(pid::text in change_key)>0;
 UPDATE public.scl290_registry SET pharmacy_id=NULL,player_prefix=NULL,legacy=false,revision=revision+1,updated_at=now() WHERE id=r.id RETURNING * INTO r;
 RETURN to_jsonb(r);
END $$;

-- An old browser cannot edit content for months after HQ paused its position.
CREATE FUNCTION scl_private.paused_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b jsonb; a jsonb; m integer;
BEGIN
 FOR b IN SELECT value FROM jsonb_array_elements(OLD.state_json->'cards') LOOP
  IF b->>'type'='hq' OR b->>'initialPlanLocked' IS DISTINCT FROM 'true' THEN CONTINUE; END IF;
  SELECT value INTO a FROM jsonb_array_elements(NEW.state_json->'cards') WHERE value->>'id'=b->>'id';
  FOR m IN 0..11 LOOP
   IF nullif(a->>'stopsOn','')::date<=make_date(NEW.year,m+1,1) AND scl_private.month_signature(b,m) IS DISTINCT FROM scl_private.month_signature(a,m) THEN RAISE EXCEPTION 'POSITION_PAUSED: Η θέση έχει παύσει για τον επιλεγμένο μήνα'; END IF;
  END LOOP;
 END LOOP;
 RETURN NEW;
END $$;
CREATE TRIGGER scl294_paused_guard BEFORE UPDATE ON public.scl290_snapshots FOR EACH ROW EXECUTE FUNCTION scl_private.paused_guard();
REVOKE ALL ON FUNCTION scl_private.paused_guard() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.scl294_correct_installation(text,uuid,bigint,text,jsonb,date),public.scl294_deactivate(text,uuid,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl294_correct_installation(text,uuid,bigint,text,jsonb,date),public.scl294_deactivate(text,uuid,bigint,text) TO anon,authenticated;
