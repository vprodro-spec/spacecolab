-- v292: persistent financial events and HQ-approved reopening.
-- Existing token/HQ authorization is retained. No public table access is granted.
CREATE SCHEMA IF NOT EXISTS scl_private;
REVOKE ALL ON SCHEMA scl_private FROM PUBLIC,anon,authenticated;

CREATE TABLE public.scl292_charge_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 year integer NOT NULL CHECK(year BETWEEN 2000 AND 2200),
 position_id text NOT NULL, position_name text NOT NULL,
 category text NOT NULL CHECK(category IN ('custom','deal','report')),
 event_key text NOT NULL, start_month integer NOT NULL CHECK(start_month BETWEEN 0 AND 11),
 end_month integer NOT NULL CHECK(end_month BETWEEN start_month AND 11),
 description text NOT NULL, amount numeric(12,2) NOT NULL, quota_index integer,
 source_revision bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(pharmacy_id,year,event_key)
);
CREATE TABLE public.scl292_program_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 year integer NOT NULL, revision bigint NOT NULL,
 state_json jsonb NOT NULL, months_json jsonb NOT NULL, deals_json jsonb NOT NULL,
 reason text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.scl292_reset_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 year integer NOT NULL CHECK(year BETWEEN 2000 AND 2200), position_id text NOT NULL,
 from_month integer NOT NULL CHECK(from_month BETWEEN 0 AND 11),
 reason text NOT NULL CHECK(length(btrim(reason))>0),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','applied')),
 hq_note text NOT NULL DEFAULT '', requested_at timestamptz NOT NULL DEFAULT now(),
 decided_at timestamptz, applied_at timestamptz
);
CREATE UNIQUE INDEX scl292_one_open_request ON public.scl292_reset_requests(pharmacy_id,year,position_id) WHERE status IN ('pending','approved');
CREATE INDEX scl292_history_pharmacy_year ON public.scl292_program_history(pharmacy_id,year,created_at);
ALTER TABLE public.scl292_charge_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scl292_program_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scl292_reset_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.scl292_charge_events,public.scl292_program_history,public.scl292_reset_requests FROM PUBLIC,anon,authenticated;

CREATE FUNCTION scl_private.cutoff(p_year integer,p_month integer) RETURNS date
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT ((make_date(p_year,p_month+1,1)-interval '1 month')::date+14);
$$;
CREATE FUNCTION scl_private.today() RETURNS date LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT (now() AT TIME ZONE 'Europe/Athens')::date;
$$;

CREATE FUNCTION scl_private.blocks(p_year integer,p_state jsonb)
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
 AND (nullif(c->>'installationStart','') IS NULL OR (c->>'installationStart')::date<=make_date(p_year,m+1,1))
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
 WHERE nullif(c->>'installationStart','') IS NULL OR (c->>'installationStart')::date<=make_date(p_year,m+1,1)
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

CREATE FUNCTION scl_private.capture_charges(p_pid uuid,p_year integer,p_state jsonb,p_revision bigint) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE b record; q integer;
BEGIN
 FOR b IN SELECT * FROM scl_private.blocks(p_year,p_state) ORDER BY position_id,start_month,category LOOP
  IF scl_private.today()<=scl_private.cutoff(p_year,b.start_month) THEN CONTINUE; END IF;
  IF EXISTS(SELECT 1 FROM public.scl292_charge_events e WHERE e.pharmacy_id=p_pid AND e.year=p_year AND e.event_key=b.event_key) THEN CONTINUE; END IF;
  q:=NULL;
  IF b.category='custom' THEN SELECT coalesce(max(quota_index),0)+1 INTO q FROM public.scl292_charge_events WHERE pharmacy_id=p_pid AND year=p_year AND position_id=b.position_id AND category='custom'; END IF;
  INSERT INTO public.scl292_charge_events(pharmacy_id,year,position_id,position_name,category,event_key,start_month,end_month,description,amount,quota_index,source_revision)
  VALUES(p_pid,p_year,b.position_id,b.position_name,b.category,b.event_key,b.start_month,b.end_month,b.description,
   CASE WHEN b.category='deal' THEN 30 WHEN q<=3 THEN 0 ELSE 15 END,q,p_revision) ON CONFLICT DO NOTHING;
 END LOOP;
END $$;

CREATE FUNCTION scl_private.snapshot_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE oldcard jsonb; newcard jsonb; arr jsonb:='[]'; req public.scl292_reset_requests; m integer;
BEGIN
 FOR newcard IN SELECT value FROM jsonb_array_elements(NEW.state_json->'cards') LOOP
  oldcard:=NULL;
  IF TG_OP='UPDATE' THEN SELECT value INTO oldcard FROM jsonb_array_elements(OLD.state_json->'cards') WHERE value->>'id'=newcard->>'id'; END IF;
  IF newcard->>'type'<>'hq' AND newcard->>'initialPlanLocked'='true' AND (oldcard IS NULL OR oldcard->>'initialPlanLocked' IS DISTINCT FROM 'true' OR oldcard->'basicSchedule' IS DISTINCT FROM newcard->'basicSchedule') THEN
   FOR m IN 0..11 LOOP
    IF (nullif(newcard->>'installationStart','') IS NULL OR (newcard->>'installationStart')::date<=make_date(NEW.year,m+1,1)) AND btrim(coalesce(newcard->'basicSchedule'->>m,''))='' THEN RAISE EXCEPTION 'INCOMPLETE_PROGRAM: Συμπληρώστε όλους τους μήνες λειτουργίας της θέσης'; END IF;
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
CREATE TRIGGER scl292_snapshot_guard BEFORE INSERT OR UPDATE ON public.scl290_snapshots FOR EACH ROW EXECUTE FUNCTION scl_private.snapshot_guard();

CREATE FUNCTION public.scl292_request_reset(p_token text,p_year integer,p_position text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token); c jsonb; first_month integer; req public.scl292_reset_requests;
BEGIN
 PERFORM 1 FROM public.scl290_installations WHERE pharmacy_id=pid FOR UPDATE;
 SELECT c1 INTO c FROM public.scl290_snapshots s CROSS JOIN LATERAL jsonb_array_elements(s.state_json->'cards') c1 WHERE s.pharmacy_id=pid AND s.year=p_year AND c1->>'id'=p_position;
 IF c IS NULL OR c->>'type'='hq' OR c->>'initialPlanLocked' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Επιλέξτε οριστικοποιημένη τοπική θέση'; END IF;
 SELECT min(m) INTO first_month FROM generate_series(0,11) m WHERE scl_private.today()<=scl_private.cutoff(p_year,m)
 AND (nullif(c->>'installationStart','') IS NULL OR (c->>'installationStart')::date<=make_date(p_year,m+1,1));
 IF first_month IS NULL THEN RAISE EXCEPTION 'Δεν απομένουν μήνες για επαναφορά στο επιλεγμένο έτος'; END IF;
 IF length(btrim(coalesce(p_reason,'')))=0 THEN RAISE EXCEPTION 'Συμπληρώστε την αιτία του αιτήματος'; END IF;
 INSERT INTO public.scl292_reset_requests(pharmacy_id,year,position_id,from_month,reason)
 VALUES(pid,p_year,p_position,first_month,btrim(p_reason)) RETURNING * INTO req;
 RETURN to_jsonb(req);
END $$;

CREATE FUNCTION public.scl292_decide_reset(p_hq_key text,p_request_id uuid,p_approve boolean,p_note text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE req public.scl292_reset_requests; snap public.scl290_snapshots; c jsonb; arr jsonb:='[]'; fm integer;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT * INTO req FROM public.scl292_reset_requests WHERE id=p_request_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Δεν βρέθηκε το αίτημα'; END IF;
 PERFORM 1 FROM public.scl290_installations WHERE pharmacy_id=req.pharmacy_id FOR UPDATE;
 SELECT * INTO req FROM public.scl292_reset_requests WHERE id=p_request_id FOR UPDATE;
 IF req.status<>'pending' THEN RAISE EXCEPTION 'Το αίτημα έχει ήδη εξεταστεί'; END IF;
 IF NOT p_approve THEN UPDATE public.scl292_reset_requests SET status='rejected',hq_note=coalesce(p_note,''),decided_at=now() WHERE id=req.id RETURNING * INTO req; RETURN to_jsonb(req); END IF;
 SELECT min(m) INTO fm FROM generate_series(req.from_month,11) m WHERE scl_private.today()<=scl_private.cutoff(req.year,m);
 IF fm IS NULL THEN RAISE EXCEPTION 'Η προθεσμία των μηνών του αιτήματος έχει περάσει'; END IF;
 SELECT * INTO snap FROM public.scl290_snapshots WHERE pharmacy_id=req.pharmacy_id AND year=req.year FOR UPDATE;
 FOR c IN SELECT value FROM jsonb_array_elements(snap.state_json->'cards') LOOP
  IF c->>'id'=req.position_id THEN c:=c||jsonb_build_object('_scl292Reset',jsonb_build_object('id',req.id,'fromMonth',fm,'approvedAt',now())); END IF;
  arr:=arr||jsonb_build_array(c);
 END LOOP;
 PERFORM set_config('scl292.hq_approval','yes',true);
 UPDATE public.scl290_snapshots SET state_json=jsonb_set(state_json,'{cards}',arr),revision=revision+1,updated_at=now() WHERE pharmacy_id=req.pharmacy_id AND year=req.year;
 PERFORM set_config('scl292.hq_approval','no',true);
 UPDATE public.scl292_reset_requests SET status='approved',from_month=fm,hq_note=coalesce(p_note,''),decided_at=now() WHERE id=req.id RETURNING * INTO req;
 RETURN to_jsonb(req);
END $$;

CREATE FUNCTION scl_private.financial_rows(p_pid uuid,p_year integer) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE cfg public.scl290_installations; snap public.scl290_snapshots; rows jsonb:='[]'; b record; e record; n integer:=0; m integer; extra integer; q integer; amount numeric; planned_count jsonb:='{}'; k text;
BEGIN
 SELECT * INTO cfg FROM public.scl290_installations WHERE pharmacy_id=p_pid FOR UPDATE;
 IF NOT FOUND THEN RETURN rows; END IF;
 SELECT * INTO snap FROM public.scl290_snapshots WHERE pharmacy_id=p_pid AND year=p_year FOR UPDATE;
 IF snap.pharmacy_id IS NOT NULL THEN PERFORM scl_private.capture_charges(p_pid,p_year,snap.state_json,snap.revision); END IF;
 FOR m IN 0..11 LOOP
  IF cfg.service_from IS NOT NULL AND cfg.service_from>make_date(p_year,m+1,1) THEN CONTINUE; END IF;
  n:=n+1; amount:=(round(n*48500.0/12)-round((n-1)*48500.0/12))/100;
  rows:=rows||jsonb_build_array(jsonb_build_object('id','base:'||p_pid||':'||p_year||':'||m,'pharmacy_id',p_pid,'year',p_year,'month',m,'category','base','position_id','','position_name','',
   'description','485€/έτος · αναλογία από έναρξη υπηρεσίας','amount',amount,'status',CASE WHEN make_date(p_year,m+1,1)<=scl_private.today() THEN 'finalized' ELSE 'planned' END));
  SELECT greatest(0,count(*)-2) INTO extra FROM jsonb_array_elements(cfg.positions) p WHERE p->>'type'<>'hq'
   AND (nullif(p->>'startsOn','') IS NULL OR (p->>'startsOn')::date<=make_date(p_year,m+1,1))
   AND (nullif(p->>'stopsOn','') IS NULL OR (p->>'stopsOn')::date>make_date(p_year,m+1,1));
  IF extra>0 THEN rows:=rows||jsonb_build_array(jsonb_build_object('id','extra:'||p_pid||':'||p_year||':'||m,'pharmacy_id',p_pid,'year',p_year,'month',m,'category','extra','position_id','','position_name','',
   'description',extra||' επιπλέον οθόνες × 8€/μήνα','amount',extra*8,'status',CASE WHEN make_date(p_year,m+1,1)<=scl_private.today() THEN 'finalized' ELSE 'planned' END)); END IF;
 END LOOP;
 FOR e IN SELECT * FROM public.scl292_charge_events WHERE pharmacy_id=p_pid AND year=p_year ORDER BY position_id,start_month,created_at LOOP
  rows:=rows||jsonb_build_array(to_jsonb(e)||jsonb_build_object('month',e.start_month,'status','finalized'));
 END LOOP;
 FOR b IN SELECT * FROM scl_private.blocks(p_year,coalesce(snap.state_json,'{}')) ORDER BY position_id,start_month,category LOOP
  IF EXISTS(SELECT 1 FROM public.scl292_charge_events WHERE pharmacy_id=p_pid AND year=p_year AND event_key=b.event_key) THEN CONTINUE; END IF;
  q:=NULL;
  IF b.category='custom' THEN
   SELECT coalesce(max(quota_index),0) INTO q FROM public.scl292_charge_events WHERE pharmacy_id=p_pid AND year=p_year AND position_id=b.position_id AND category='custom';
   k:=b.position_id; q:=q+coalesce((planned_count->>k)::integer,0)+1;planned_count:=jsonb_set(planned_count,ARRAY[k],to_jsonb(coalesce((planned_count->>k)::integer,0)+1));
  END IF;
  rows:=rows||jsonb_build_array(to_jsonb(b)||jsonb_build_object('id','planned:'||b.event_key,'pharmacy_id',p_pid,'year',p_year,'month',b.start_month,'status','planned','quota_index',q,
   'amount',CASE WHEN b.category='deal' THEN 30 WHEN q<=3 THEN 0 ELSE 15 END));
 END LOOP;
 RETURN rows;
END $$;

CREATE FUNCTION public.scl292_finance(p_year integer,p_token text DEFAULT NULL,p_hq_key text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid; ph record; rows jsonb:='[]'; rr jsonb; reqs jsonb; hist jsonb;
BEGIN
 IF p_year NOT BETWEEN 2000 AND 2200 OR p_year IS NULL THEN RAISE EXCEPTION 'Μη έγκυρο έτος'; END IF;
 IF p_hq_key IS NOT NULL THEN PERFORM public.scl290_assert_hq(p_hq_key); ELSE pid:=public.scl290_token_id(p_token); END IF;
 FOR ph IN SELECT pharmacy_id,name,billing_code FROM public.scl290_registry WHERE pharmacy_id IS NOT NULL AND (pid IS NULL OR pharmacy_id=pid) ORDER BY pharmacy_id LOOP
  SELECT coalesce(jsonb_agg(v||jsonb_build_object('pharmacy_name',ph.name,'billing_code',ph.billing_code)),'[]') INTO rr FROM jsonb_array_elements(scl_private.financial_rows(ph.pharmacy_id,p_year)) v;
  rows:=rows||rr;
 END LOOP;
 SELECT coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('pharmacy_name',r.name) ORDER BY q.requested_at DESC),'[]') INTO reqs FROM public.scl292_reset_requests q JOIN public.scl290_registry r ON r.pharmacy_id=q.pharmacy_id WHERE q.year=p_year AND (pid IS NULL OR q.pharmacy_id=pid);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',h.id,'pharmacy_id',h.pharmacy_id,'pharmacy_name',r.name,'year',h.year,'revision',h.revision,'reason',h.reason,'created_at',h.created_at) ORDER BY h.created_at DESC),'[]') INTO hist FROM public.scl292_program_history h JOIN public.scl290_registry r ON r.pharmacy_id=h.pharmacy_id WHERE h.year=p_year AND (pid IS NULL OR h.pharmacy_id=pid);
 RETURN jsonb_build_object('year',p_year,'rows',rows,'requests',reqs,'history',hist,'as_of',scl_private.today());
END $$;

-- Preserve the currently observable confirmed charge history; no deleted past is invented.
-- Retired reports are imported once from existing confirmed records only.
WITH cards AS (
 SELECT s.pharmacy_id,s.year,s.revision,c
 FROM public.scl290_snapshots s CROSS JOIN LATERAL jsonb_array_elements(coalesce(s.state_json->'cards','[]')) c
 WHERE c->>'type'<>'hq'
), old_reports AS (
 SELECT pharmacy_id,year,revision,c,d,
 coalesce(nullif(d->>'reportMode',''),CASE WHEN d->>'reportEnabled'='true' THEN 'total' ELSE 'none' END) mode
 FROM cards CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_array_length(coalesce(c->'confirmedDeals','[]'))>0 THEN c->'confirmedDeals'
 WHEN c->'negotiation'->>'confirmed'='true' THEN jsonb_build_array(c->'negotiation') ELSE '[]'::jsonb END) d
 WHERE d->>'confirmed'='true'
), report_months AS (
 SELECT pharmacy_id,year,revision,c,d,m FROM old_reports CROSS JOIN LATERAL generate_series(
 greatest(0,coalesce((d->>'startMonth')::integer,0)),
 least(11,coalesce((d->>'startMonth')::integer,0)+CASE WHEN mode IN ('perBlock','monthly') AND d->>'monthlyContentChanges' IS DISTINCT FROM 'false'
 THEN greatest(1,coalesce((d->>'duration')::integer,1))-1 ELSE 0 END)) m WHERE mode<>'none'
 UNION ALL
 SELECT pharmacy_id,year,revision,c,d,coalesce((d->>'month')::integer,0) FROM cards
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(c->'sponsoredShelves','[]')) d
 WHERE d->>'status' IS DISTINCT FROM 'cancelled' AND (d->>'reportEnabled'='true' OR coalesce(d->>'reportMode','none')<>'none')
)
INSERT INTO public.scl292_charge_events(pharmacy_id,year,position_id,position_name,category,event_key,start_month,end_month,description,amount,source_revision)
SELECT pharmacy_id,year,c->>'id',coalesce(c->>'title',c->>'id'),'report',
 'legacy-report:'||md5(concat_ws('|',c->>'id',coalesce(d->>'id',d->>'deal_uid',d::text),m)),m,m,
 'Αναφορά αποτελεσμάτων — ιστορική χρέωση',60,revision FROM report_months
WHERE m BETWEEN 0 AND 11 AND scl_private.today()>scl_private.cutoff(year,m)
ON CONFLICT DO NOTHING;
DO $$ DECLARE s record; BEGIN FOR s IN SELECT * FROM public.scl290_snapshots LOOP
 PERFORM scl_private.capture_charges(s.pharmacy_id,s.year,s.state_json,s.revision);
END LOOP; END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA scl_private FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.scl292_finance(integer,text,text),public.scl292_request_reset(text,integer,text,text),public.scl292_decide_reset(text,uuid,boolean,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl292_finance(integer,text,text),public.scl292_request_reset(text,integer,text,text),public.scl292_decide_reset(text,uuid,boolean,text) TO anon,authenticated;
NOTIFY pgrst,'reload schema';

CREATE TABLE public.scl292_completion_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), change_key text NOT NULL,
 previous_done boolean NOT NULL, done boolean NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.scl292_completion_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.scl292_completion_history FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.scl292_get_done(p_hq_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(d)),'[]') FROM public.hq_changes_done d WHERE change_key LIKE 'v292|%');
END $$;
CREATE FUNCTION public.scl292_set_done(p_hq_key text,p_change_key text,p_done boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE previous boolean; rowdata jsonb;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_change_key NOT LIKE 'v292|%' OR length(p_change_key)>8000 THEN RAISE EXCEPTION 'Μη έγκυρη ταυτότητα εργασίας'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_change_key,292));
 SELECT done INTO previous FROM public.hq_changes_done WHERE change_key=p_change_key;
 IF coalesce(previous,false) IS DISTINCT FROM p_done THEN
  INSERT INTO public.scl292_completion_history(change_key,previous_done,done) VALUES(p_change_key,coalesce(previous,false),p_done);
 END IF;
 INSERT INTO public.hq_changes_done(change_key,done) VALUES(p_change_key,p_done)
 ON CONFLICT(change_key) DO UPDATE SET done=excluded.done,updated_at=now();
 SELECT to_jsonb(d) INTO rowdata FROM public.hq_changes_done d WHERE change_key=p_change_key;
 RETURN rowdata;
END $$;
REVOKE ALL ON FUNCTION public.scl292_get_done(text),public.scl292_set_done(text,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl292_get_done(text),public.scl292_set_done(text,text,boolean) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.scl290_save_program(p_token text, p_year integer, p_installation_version bigint, p_snapshot_revision bigint, p_state jsonb, p_months jsonb, p_deals jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token); cfg public.scl290_installations; snap public.scl290_snapshots;
  st jsonb; mm jsonb; dd jsonb;
BEGIN
  IF p_year < extract(year FROM scl_private.today()) THEN RAISE EXCEPTION 'HISTORY_LOCKED: Το προηγούμενο έτος είναι μόνο για προβολή'; END IF;
  IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος'; END IF;
  SELECT * INTO cfg FROM public.scl290_installations WHERE pharmacy_id=pid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Αναμονή ρύθμισης θέσεων από τα HQ'; END IF;
  IF cfg.version IS DISTINCT FROM p_installation_version THEN RAISE EXCEPTION 'INSTALLATION_CHANGED: Τα HQ ενημέρωσαν τις θέσεις. Ανανεώστε χωρίς να κλείσετε το πρόγραμμά σας'; END IF;
  SELECT * INTO snap FROM public.scl290_snapshots WHERE pharmacy_id=pid AND year=p_year FOR UPDATE;
  IF coalesce(snap.revision,0) IS DISTINCT FROM p_snapshot_revision THEN RAISE EXCEPTION 'PROGRAM_CHANGED: Το πρόγραμμα άλλαξε σε άλλη καρτέλα. Ανανεώστε πριν από αποθήκευση'; END IF;
  IF p_state IS NULL OR jsonb_typeof(p_state)<>'object' OR jsonb_typeof(p_state->'cards') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Μη έγκυρο πρόγραμμα'; END IF;
  st:=public.scl290_merge_state(pid,p_year,p_state);
  mm:=public.scl290_clean_months(pid,p_year,st,p_months);
  dd:=public.scl290_clean_deals(pid,p_year,st,p_deals);
  INSERT INTO public.scl290_snapshots(pharmacy_id,year,state_json,months_json,deals_json)
  VALUES(pid,p_year,st,mm,dd) ON CONFLICT(pharmacy_id,year) DO UPDATE SET
    revision=scl290_snapshots.revision+1,state_json=excluded.state_json,months_json=excluded.months_json,deals_json=excluded.deals_json,updated_at=now()
  RETURNING * INTO snap;
  st:=snap.state_json;
  PERFORM set_config('scl290.authorized_write','yes',true);
  PERFORM public.upsert_pharmacy_state_by_token(p_token,p_year,st);
  PERFORM set_config('scl290.authorized_write','no',true);
  RETURN jsonb_build_object('snapshot_revision',snap.revision,'installation_version',cfg.version,'saved_at',snap.updated_at);
END $function$;

CREATE OR REPLACE FUNCTION public.scl290_get_pharmacy(p_token text, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token); r public.scl290_registry; cfg public.scl290_installations; snap public.scl290_snapshots; st jsonb; prior jsonb;
BEGIN
  IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος'; END IF;
  SELECT * INTO r FROM public.scl290_registry WHERE pharmacy_id=pid;
  SELECT * INTO cfg FROM public.scl290_installations WHERE pharmacy_id=pid;
  SELECT * INTO snap FROM public.scl290_snapshots WHERE pharmacy_id=pid AND year=p_year;
  st:=snap.state_json;
  IF st IS NULL THEN SELECT state_json INTO st FROM public.pharmacy_state WHERE pharmacy_id=pid AND year=p_year; END IF;
  IF st IS NULL AND cfg.pharmacy_id IS NOT NULL THEN
    SELECT state_json INTO prior FROM public.scl290_snapshots WHERE pharmacy_id=pid AND year<p_year ORDER BY year DESC LIMIT 1;
    IF prior IS NOT NULL THEN
      SELECT jsonb_set(prior,'{cards}',coalesce(jsonb_agg((c-'_scl292Reset'-'_scl292ResetApplied')||jsonb_build_object(
       'initialPlanLocked',c->>'type'='hq','initialPlanType','','pendingInitialSchedule',coalesce(c->'basicSchedule','[]'),
       'simpleSchedule',coalesce(c->'basicSchedule','[]'),'pendingSimpleSchedule',coalesce(c->'basicSchedule','[]'),
       'simpleConfirmed',false,'confirmedDeals','[]'::jsonb,'preagreements','[]'::jsonb,'sponsoredShelves','[]'::jsonb,
       'negotiation','{}'::jsonb,'simpleMechanism','[]'::jsonb,'pendingSimpleMechanism','[]'::jsonb)),'[]'))
      INTO st FROM jsonb_array_elements(prior->'cards') c;
    END IF;
  END IF;
  IF cfg.pharmacy_id IS NOT NULL THEN st:=public.scl290_merge_state(pid,p_year,st); END IF;
  RETURN jsonb_build_object('pharmacy_id',pid,'pharmacy_name',r.name,'registry',to_jsonb(r)-'source_key',
    'installation',CASE WHEN cfg.pharmacy_id IS NULL THEN NULL ELSE to_jsonb(cfg) END,
    'available_years',(SELECT coalesce(jsonb_agg(y ORDER BY y),'[]') FROM (SELECT year y FROM public.scl290_snapshots WHERE pharmacy_id=pid UNION SELECT p_year) ys),
    'state_json',st,'snapshot_revision',coalesce(snap.revision,0),'had_saved_state',EXISTS(SELECT 1 FROM public.pharmacy_state WHERE pharmacy_id=pid AND year=p_year));
END $function$;


