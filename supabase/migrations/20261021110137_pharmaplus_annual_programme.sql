-- Pharmaplus annual programme: campaign identity spans years; month snapshots retain history.
CREATE TABLE scl_private.pp_meta(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),revision bigint NOT NULL DEFAULT 1);
INSERT INTO scl_private.pp_meta VALUES(true,1);
CREATE TABLE scl_private.pp_campaigns(id uuid PRIMARY KEY,starts_on date NOT NULL,ends_on date NOT NULL,CHECK(ends_on>=starts_on));
CREATE TABLE scl_private.pp_months(month_on date PRIMARY KEY CHECK(extract(day FROM month_on)=1),campaign_id uuid REFERENCES scl_private.pp_campaigns(id),campaign jsonb NOT NULL DEFAULT '{}',scope_override jsonb,thematic jsonb NOT NULL DEFAULT '{}',updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE scl_private.pp_history(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,revision bigint NOT NULL,action text NOT NULL,month_on date NOT NULL,before_data jsonb,after_data jsonb,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE scl_private.pp_legacy_archive(id uuid PRIMARY KEY,data jsonb NOT NULL);
ALTER TABLE scl_private.pp_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.pp_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.pp_months ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.pp_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.pp_legacy_archive ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.pp_meta,scl_private.pp_campaigns,scl_private.pp_months,scl_private.pp_history,scl_private.pp_legacy_archive FROM PUBLIC,anon,authenticated;

INSERT INTO scl_private.pp_legacy_archive SELECT id,to_jsonb(c) FROM public.pharmaplus_campaigns c;
INSERT INTO scl_private.pp_campaigns SELECT id,make_date(year,month+1,1),make_date(year,month+1,1) FROM public.pharmaplus_campaigns WHERE coalesce(nullif(title,''),nullif(supplier,''),nullif(campaign_type,''),nullif(company_benefit,''),nullif(products_text,''),nullif(shelf_instructions,''),nullif(shelf_1,''),nullif(shelf_2,''),nullif(shelf_3,''),nullif(shelf_4,'')) IS NOT NULL;
INSERT INTO scl_private.pp_months(month_on,campaign_id,campaign,thematic)
SELECT make_date(c.year,c.month+1,1),s.id,
 CASE WHEN s.id IS NOT NULL THEN jsonb_build_object('title',coalesce(nullif(c.title,''),nullif(c.supplier,''),'Καμπάνια Pharmaplus'),'supplier',coalesce(c.supplier,''),'company_benefit',coalesce(c.company_benefit,''),'products_text',coalesce(c.products_text,''),'shelf_1',coalesce(c.shelf_1,''),'shelf_2',coalesce(c.shelf_2,''),'shelf_3',coalesce(c.shelf_3,''),'shelf_4',coalesce(c.shelf_4,''),'files',jsonb_build_object('vertical','','horizontal',''),'scope',jsonb_build_object('mode',coalesce(c.scope_mode,'all'),'ids',coalesce((SELECT jsonb_agg(coalesce((SELECT r.id FROM public.scl290_registry r WHERE r.pharmacy_id=x LIMIT 1),x)::text) FROM unnest(c.scope_pharmacy_ids) x),'[]'::jsonb))) ELSE '{}'::jsonb END,
 CASE WHEN nullif(c.fallback_title,'') IS NOT NULL THEN jsonb_build_object('id','legacy-theme:'||c.id,'title',c.fallback_title,'files',jsonb_build_object('vertical','','horizontal','')) ELSE '{}'::jsonb END
FROM public.pharmaplus_campaigns c LEFT JOIN scl_private.pp_campaigns s ON s.id=c.id;

CREATE FUNCTION scl_private.pp_scope(s jsonb,pid uuid,rid uuid) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE coalesce(s->>'mode','all') WHEN 'all' THEN true WHEN 'only' THEN coalesce(s->'ids' ? pid::text,false) OR coalesce(s->'ids' ? rid::text,false) WHEN 'except' THEN NOT(coalesce(s->'ids' ? pid::text,false) OR coalesce(s->'ids' ? rid::text,false)) ELSE false END
$$;
CREATE FUNCTION scl_private.pp_validate_scope(s jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE x text;BEGIN
 IF jsonb_typeof(s) IS DISTINCT FROM 'object' OR coalesce(s->>'mode','') NOT IN ('all','only','except') OR jsonb_typeof(s->'ids') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Μη έγκυρη συμμετοχή φαρμακείων';END IF;
 FOR x IN SELECT jsonb_array_elements_text(s->'ids') LOOP
  IF NOT EXISTS(SELECT 1 FROM public.scl290_registry WHERE id::text=x OR pharmacy_id::text=x) THEN RAISE EXCEPTION 'Η λίστα φαρμακείων άλλαξε. Ανανεώστε την.';END IF;
 END LOOP;
 RETURN jsonb_build_object('mode',s->>'mode','ids',CASE WHEN s->>'mode'='all' THEN '[]'::jsonb ELSE (SELECT coalesce(jsonb_agg(v ORDER BY v),'[]') FROM(SELECT DISTINCT jsonb_array_elements_text(s->'ids') v)t) END);
END $$;

-- Pure resolver shared by previews, pharmacy delivery and HQ work instructions.
CREATE FUNCTION scl_private.pp_resolve(slot jsonb,pid uuid,rid uuid,fmt text) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE d jsonb;kind text;cid text;identity text;file text;BEGIN
 IF nullif(slot->>'campaign_id','') IS NOT NULL AND scl_private.pp_scope(coalesce(nullif(slot->'scope_override','null'::jsonb),slot->'campaign'->'scope'),pid,rid) THEN
  d:=slot->'campaign';kind:='main';cid:=slot->>'campaign_id';identity:='campaign:'||cid;
 ELSE d:=coalesce(slot->'thematic','{}'::jsonb);kind:='fallback';identity:='theme:'||coalesce(d->>'theme_id',d->>'title','');END IF;
 IF nullif(d->>'title','') IS NULL THEN RETURN jsonb_build_object('display_kind','empty','display_title','Προσεχώς','content_key','empty','file_name','');END IF;
 file:=coalesce(d->'files'->>fmt,'');
 RETURN jsonb_build_object('display_kind',kind,'display_title',d->>'title','campaign_id',cid,'theme_id',d->>'theme_id','file_name',file,'content_revision',coalesce(d->'media_revision'->>fmt,''),'content_key',identity||':'||md5(jsonb_build_array(d->>'title',CASE WHEN d ? 'theme_id' THEN coalesce(d->'media_revision'->>fmt,'') ELSE file END)::text))
 || CASE WHEN kind='main' THEN d-'scope'-'files' ELSE jsonb_build_object('fallback_title',d->>'title') END;
END $$;

CREATE FUNCTION scl_private.pp_pharmacies() RETURNS jsonb LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.pharmacy_id,'registry_id',r.id,'name',r.name,'billing_code',r.billing_code,'positions',coalesce(i.positions,'[]'),'service_from',i.service_from,'active',p.id IS NOT NULL) ORDER BY r.name),'[]') FROM public.scl290_registry r LEFT JOIN public.pharmacies p ON p.id=r.pharmacy_id LEFT JOIN public.scl290_installations i ON i.pharmacy_id=r.pharmacy_id
$$;
CREATE FUNCTION scl_private.pp_position(ph jsonb,m date) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT p FROM jsonb_array_elements(coalesce(ph->'positions','[]')) p WHERE coalesce((ph->>'active')::boolean,false) AND p->>'type'='hq' AND coalesce(nullif(p->>'startsOn','')::date,'1900-01-01'::date)<=m AND (nullif(p->>'stopsOn','') IS NULL OR (p->>'stopsOn')::date>m) LIMIT 1
$$;

CREATE FUNCTION public.scl300_pp_hq(p_hq_key text,p_year integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος';END IF;
 RETURN jsonb_build_object('year',p_year,'revision',(SELECT revision FROM scl_private.pp_meta),'today',scl_private.today(),'records',(SELECT coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('starts_on',c.starts_on,'ends_on',c.ends_on) ORDER BY month_on),'[]') FROM scl_private.pp_months m LEFT JOIN scl_private.pp_campaigns c ON c.id=m.campaign_id),'pharmacies',scl_private.pp_pharmacies(),'history',(SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY id DESC),'[]') FROM(SELECT * FROM scl_private.pp_history WHERE extract(year FROM month_on)=p_year ORDER BY id DESC LIMIT 100)h));
END $$;

-- Preview prepares the exact immutable month patches later committed by save.
CREATE FUNCTION scl_private.pp_plan(req jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE act text:=req->>'action'; m date;lastm date;cid uuid;rev bigint;duration integer;slot jsonb;after_slot jsonb;d jsonb;sc jsonb;theme jsonb;patches jsonb:='[]';conflicts jsonb:='[]';month_list date[];mode text:=coalesce(req->>'range','month');
BEGIN
 SELECT revision INTO rev FROM scl_private.pp_meta;
 IF jsonb_typeof(req) IS DISTINCT FROM 'object' OR act IS NULL OR act NOT IN ('create','edit','cancel','scope','theme') THEN RAISE EXCEPTION 'Μη έγκυρη ενέργεια';END IF;
 m:=(req->>'month_on')::date;
 IF m IS NULL OR extract(day FROM m)<>1 OR m<=date_trunc('month',scl_private.today())::date OR extract(year FROM m) NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Επιτρέπονται αλλαγές μόνο σε μελλοντικούς μήνες';END IF;
 IF mode NOT IN ('month','tail') THEN RAISE EXCEPTION 'Μη έγκυρη περίοδος επεξεργασίας';END IF;
 IF act='create' THEN
  duration:=(req->>'duration')::integer;IF duration IS NULL OR duration<1 OR duration>36 THEN RAISE EXCEPTION 'Η διάρκεια πρέπει να είναι από 1 έως 36 μήνες';END IF;
  lastm:=(m+(duration-1)*interval '1 month')::date;cid:=md5(req::text||rev::text)::uuid;
  month_list:=ARRAY(SELECT generate_series(m,lastm,'1 month')::date);
 ELSIF act IN ('edit','cancel','scope') THEN
  cid:=(req->>'campaign_id')::uuid;
  IF cid IS NULL OR NOT EXISTS(SELECT 1 FROM scl_private.pp_months WHERE month_on=m AND campaign_id=cid) THEN RAISE EXCEPTION 'Η καμπάνια άλλαξε. Ανανεώστε το πρόγραμμα.';END IF;
  SELECT ends_on INTO lastm FROM scl_private.pp_campaigns WHERE id=cid;
  month_list:=ARRAY(SELECT month_on FROM scl_private.pp_months WHERE campaign_id=cid AND month_on>=m AND (mode='tail' AND act<>'scope' OR month_on=m) ORDER BY month_on);
 ELSE month_list:=ARRAY[m];lastm:=m;END IF;
 IF act IN ('create','edit') THEN
  d:=req->'data';IF jsonb_typeof(d) IS DISTINCT FROM 'object' OR nullif(btrim(d->>'title'),'') IS NULL OR nullif(btrim(d->>'supplier'),'') IS NULL THEN RAISE EXCEPTION 'Συμπληρώστε τίτλο καμπάνιας και προμηθευτή';END IF;
  sc:=scl_private.pp_validate_scope(d->'scope');
  d:=jsonb_build_object('title',btrim(d->>'title'),'supplier',btrim(d->>'supplier'),'company_benefit',coalesce(d->>'company_benefit',''),'products_text',coalesce(d->>'products_text',''),'shelf_1',coalesce(d->>'shelf_1',''),'shelf_2',coalesce(d->>'shelf_2',''),'shelf_3',coalesce(d->>'shelf_3',''),'shelf_4',coalesce(d->>'shelf_4',''),'files',jsonb_build_object('vertical',btrim(coalesce(d->'files'->>'vertical','')),'horizontal',btrim(coalesce(d->'files'->>'horizontal',''))),'scope',sc);
 END IF;
 IF act='scope' AND NOT coalesce((req->>'inherit')::boolean,false) THEN sc:=scl_private.pp_validate_scope(req->'scope');END IF;
 IF act='theme' THEN
  d:=req->'data';
  IF nullif(d->>'theme_id','') IS NOT NULL THEN
   SELECT data INTO theme FROM public.scl293_themes WHERE id=d->>'theme_id';
   IF theme IS NULL OR theme->>'status'<>'available' AND NOT EXISTS(SELECT 1 FROM scl_private.pp_months WHERE month_on=m AND thematic->>'theme_id'=d->>'theme_id') THEN RAISE EXCEPTION 'Επιλέξτε διαθέσιμη θεματική βιβλιοθήκης';END IF;
   d:=jsonb_build_object('theme_id',d->>'theme_id','title',theme->>'title','files',theme->'files','media_revision',(SELECT coalesce(jsonb_object_agg(orientation,id::text),'{}') FROM(SELECT DISTINCT ON(orientation) orientation,id FROM public.scl293_media_events WHERE theme_id=d->>'theme_id' ORDER BY orientation,created_at DESC,id DESC)e));
  ELSE
   IF nullif(btrim(d->>'title'),'') IS NULL THEN RAISE EXCEPTION 'Συμπληρώστε τίτλο θεματικής';END IF;
   d:=jsonb_build_object('id',coalesce(nullif(d->>'id',''),'theme:'||md5(req::text||rev::text)),'title',btrim(d->>'title'),'files',jsonb_build_object('vertical',btrim(coalesce(d->'files'->>'vertical','')),'horizontal',btrim(coalesce(d->'files'->>'horizontal',''))));
  END IF;
 END IF;
 FOREACH m IN ARRAY month_list LOOP
  SELECT to_jsonb(s)-'updated_at' INTO slot FROM scl_private.pp_months s WHERE month_on=m;
  slot:=coalesce(slot,jsonb_build_object('month_on',m,'campaign_id',null,'campaign','{}'::jsonb,'scope_override',null,'thematic','{}'::jsonb));after_slot:=slot;
  IF act='create' THEN
   IF slot->>'campaign_id' IS NOT NULL THEN conflicts:=conflicts||jsonb_build_array(jsonb_build_object('month_on',m,'title',slot->'campaign'->>'title','campaign_id',slot->>'campaign_id'));END IF;
   after_slot:=slot||jsonb_build_object('campaign_id',cid,'campaign',d,'scope_override',null);
  ELSIF act='edit' THEN after_slot:=slot||jsonb_build_object('campaign',d);
  ELSIF act='cancel' THEN after_slot:=slot||jsonb_build_object('campaign_id',null,'campaign','{}'::jsonb,'scope_override',null);
  ELSIF act='scope' THEN after_slot:=slot||jsonb_build_object('scope_override',CASE WHEN coalesce((req->>'inherit')::boolean,false) THEN null ELSE sc END);
  ELSE after_slot:=slot||jsonb_build_object('thematic',d);END IF;
  IF after_slot IS DISTINCT FROM slot THEN patches:=patches||jsonb_build_array(jsonb_build_object('month_on',m,'before',slot,'after',after_slot));END IF;
 END LOOP;
 RETURN jsonb_build_object('revision',rev,'action',act,'campaign_id',cid,'starts_on',req->>'month_on','ends_on',lastm,'patches',patches,'conflicts',conflicts);
END $$;

CREATE FUNCTION scl_private.pp_preview(req jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE plan jsonb:=scl_private.pp_plan(req);phs jsonb:=scl_private.pp_pharmacies();p jsonb;ph jsonb;pos jsonb;b jsonb;a jsonb;items jsonb;months jsonb:='[]';impacted uuid[]:='{}';affected integer:=0;ops integer:=0;gaps integer:=0;row_ops integer;row_gaps integer;BEGIN
 FOR p IN SELECT value FROM jsonb_array_elements(plan->'patches') LOOP
  items:='[]';row_ops:=0;row_gaps:=0;
  FOR ph IN SELECT value FROM jsonb_array_elements(phs) LOOP
   pos:=scl_private.pp_position(ph,(p->>'month_on')::date);IF pos IS NULL THEN CONTINUE;END IF;
   b:=scl_private.pp_resolve(p->'before',(ph->>'id')::uuid,(ph->>'registry_id')::uuid,pos->>'screenFormat');a:=scl_private.pp_resolve(p->'after',(ph->>'id')::uuid,(ph->>'registry_id')::uuid,pos->>'screenFormat');
   IF b IS DISTINCT FROM a THEN
    impacted:=array_append(impacted,(ph->>'id')::uuid);affected:=affected+1;
    IF b->>'content_key' IS DISTINCT FROM a->>'content_key' THEN row_ops:=row_ops+1;END IF;
    IF a->>'display_kind'='empty' THEN row_gaps:=row_gaps+1;END IF;
    items:=items||jsonb_build_array(jsonb_build_object('id',ph->>'id','name',ph->>'name','player_code',pos->>'playerCode','before',b->>'display_title','after',a->>'display_title','before_kind',b->>'display_kind','after_kind',a->>'display_kind','content_changed',b->>'content_key' IS DISTINCT FROM a->>'content_key'));
   END IF;
  END LOOP;
  ops:=ops+row_ops;gaps:=gaps+row_gaps;
  months:=months||jsonb_build_array(jsonb_build_object('month_on',p->>'month_on','pharmacies',items,'affected',jsonb_array_length(items),'content_changes',row_ops,'missing_content',row_gaps,'campaign_before',p->'before'->'campaign'->>'title','campaign_after',p->'after'->'campaign'->>'title','thematic',p->'after'->'thematic'->>'title','scope_override',p->'after'->'scope_override'));
 END LOOP;
 RETURN plan||jsonb_build_object('months',months,'affected_pharmacies',(SELECT count(DISTINCT x) FROM unnest(impacted)x),'affected_months',affected,'content_changes',ops,'missing_content',gaps,'fingerprint',md5(jsonb_build_array(req,plan,months,phs)::text));
END $$;
CREATE FUNCTION public.scl300_pp_preview(p_hq_key text,p_request jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN PERFORM public.scl290_assert_hq(p_hq_key);RETURN scl_private.pp_preview(p_request);END $$;
CREATE FUNCTION public.scl300_pp_save(p_hq_key text,p_request jsonb,p_fingerprint text,p_replace boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE preview jsonb;p jsonb;a jsonb;rev bigint;BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);PERFORM pg_advisory_xact_lock(300,1);
 SELECT revision INTO rev FROM scl_private.pp_meta FOR UPDATE;
 preview:=scl_private.pp_preview(p_request);
 IF p_fingerprint IS NULL OR preview->>'fingerprint'<>p_fingerprint THEN RAISE EXCEPTION 'Η προεπισκόπηση άλλαξε. Ελέγξτε ξανά τους μήνες και τα φαρμακεία πριν αποθηκεύσετε.';END IF;
 IF jsonb_array_length(preview->'patches')=0 THEN RAISE EXCEPTION 'Δεν υπάρχουν αλλαγές για αποθήκευση';END IF;
 IF jsonb_array_length(preview->'conflicts')>0 AND NOT coalesce(p_replace,false) THEN RAISE EXCEPTION 'Απαιτείται ρητή επιβεβαίωση αντικατάστασης υπάρχουσας καμπάνιας';END IF;
 IF preview->>'action'='create' THEN INSERT INTO scl_private.pp_campaigns VALUES((preview->>'campaign_id')::uuid,(preview->>'starts_on')::date,(preview->>'ends_on')::date);END IF;
 FOR p IN SELECT value FROM jsonb_array_elements(preview->'patches') LOOP
  a:=p->'after';
  INSERT INTO scl_private.pp_history(revision,action,month_on,before_data,after_data) VALUES(rev+1,preview->>'action',(p->>'month_on')::date,p->'before',a);
  INSERT INTO scl_private.pp_months(month_on,campaign_id,campaign,scope_override,thematic) VALUES((a->>'month_on')::date,(a->>'campaign_id')::uuid,a->'campaign',nullif(a->'scope_override','null'::jsonb),a->'thematic') ON CONFLICT(month_on) DO UPDATE SET campaign_id=excluded.campaign_id,campaign=excluded.campaign,scope_override=excluded.scope_override,thematic=excluded.thematic,updated_at=now();
 END LOOP;
 UPDATE scl_private.pp_meta SET revision=rev+1;
 RETURN jsonb_build_object('revision',rev+1,'campaign_id',preview->>'campaign_id','months',preview->'months');
END $$;

CREATE FUNCTION public.scl300_pp_pharmacy(p_pharmacy_token text,p_year integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_pharmacy_token);rid uuid;ph jsonb;pos jsonb;m date;s jsonb;d jsonb;out jsonb:='[]';BEGIN
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος';END IF;
 SELECT r.id,jsonb_build_object('active',true,'positions',coalesce(i.positions,'[]')) INTO rid,ph FROM public.scl290_registry r LEFT JOIN public.scl290_installations i ON i.pharmacy_id=r.pharmacy_id WHERE r.pharmacy_id=pid LIMIT 1;
 FOR m IN SELECT generate_series(make_date(p_year,1,1),make_date(p_year,12,1),'1 month')::date LOOP
  pos:=scl_private.pp_position(ph,m);SELECT to_jsonb(x)||jsonb_build_object('starts_on',c.starts_on,'ends_on',c.ends_on) INTO s FROM scl_private.pp_months x LEFT JOIN scl_private.pp_campaigns c ON c.id=x.campaign_id WHERE x.month_on=m;
  d:=CASE WHEN pos IS NULL THEN jsonb_build_object('display_kind','inactive','display_title','Εκτός περιόδου λειτουργίας','content_key','inactive') ELSE scl_private.pp_resolve(coalesce(s,'{}'),pid,rid,pos->>'screenFormat') END;
  d:=d||jsonb_build_object('month',extract(month FROM m)::integer-1,'year',p_year,'month_on',m,'starts_on',CASE WHEN d->>'display_kind'='main' THEN s->>'starts_on' END,'ends_on',CASE WHEN d->>'display_kind'='main' THEN s->>'ends_on' END);
  out:=out||jsonb_build_array(d);
 END LOOP;RETURN out;
END $$;

-- Snapshot library titles/file references forward, never rewrite elapsed months.
CREATE FUNCTION scl_private.pp_library_sync() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE changed integer;BEGIN
 UPDATE scl_private.pp_months SET thematic=thematic||jsonb_build_object('title',NEW.data->>'title','files',NEW.data->'files'),updated_at=now() WHERE month_on>=date_trunc('month',scl_private.today())::date AND thematic->>'theme_id'=NEW.id AND (thematic->>'title' IS DISTINCT FROM NEW.data->>'title' OR thematic->'files' IS DISTINCT FROM NEW.data->'files');
 GET DIAGNOSTICS changed=ROW_COUNT;IF changed>0 THEN UPDATE scl_private.pp_meta SET revision=revision+1;END IF;RETURN NEW;
END $$;
CREATE TRIGGER scl300_pp_library_sync AFTER UPDATE ON public.scl293_themes FOR EACH ROW EXECUTE FUNCTION scl_private.pp_library_sync();
CREATE FUNCTION scl_private.pp_media_sync() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN UPDATE scl_private.pp_months SET thematic=jsonb_set(thematic,'{media_revision}',coalesce(thematic->'media_revision','{}')||jsonb_build_object(NEW.orientation,NEW.id::text)),updated_at=now() WHERE month_on>=date_trunc('month',scl_private.today())::date AND thematic->>'theme_id'=NEW.theme_id;UPDATE scl_private.pp_meta SET revision=revision+1;RETURN NEW;END $$;
CREATE TRIGGER scl300_pp_media_sync AFTER INSERT ON public.scl293_media_events FOR EACH ROW EXECUTE FUNCTION scl_private.pp_media_sync();

REVOKE ALL ON FUNCTION scl_private.pp_scope(jsonb,uuid,uuid),scl_private.pp_validate_scope(jsonb),scl_private.pp_resolve(jsonb,uuid,uuid,text),scl_private.pp_pharmacies(),scl_private.pp_position(jsonb,date),scl_private.pp_plan(jsonb),scl_private.pp_preview(jsonb),scl_private.pp_library_sync(),scl_private.pp_media_sync() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.scl300_pp_hq(text,integer),public.scl300_pp_preview(text,jsonb),public.scl300_pp_save(text,jsonb,text,boolean),public.scl300_pp_pharmacy(text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl300_pp_hq(text,integer),public.scl300_pp_preview(text,jsonb),public.scl300_pp_save(text,jsonb,text,boolean),public.scl300_pp_pharmacy(text,integer) TO anon,authenticated;

-- Existing read endpoints follow the canonical programme; old write routes are retired.
REVOKE ALL ON FUNCTION public.hq_delete_pharmaplus_campaign(text,integer,integer) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.hq_get_pharmaplus_campaigns(p_hq_key text, p_year integer)
 RETURNS TABLE(id uuid, year integer, month integer, campaign_type text, title text, supplier text, date_range text, company_benefit text, placement_dates text, products_text text, instore_materials text, digital_support text, shelf_instructions text, shelf_1 text, shelf_2 text, shelf_3 text, shelf_4 text, notes text, fallback_title text, fallback_description text, fallback_products_text text, fallback_instructions text, scope_mode text, scope_pharmacy_ids uuid[], pharmacy_billable boolean, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE records jsonb;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT coalesce(jsonb_agg(m.campaign||jsonb_build_object('id',coalesce(m.campaign_id,md5(m.month_on::text)::uuid),'year',extract(year FROM m.month_on)::integer,'month',extract(month FROM m.month_on)::integer-1,'fallback_title',m.thematic->>'title','scope_mode',coalesce(m.scope_override,m.campaign->'scope')->>'mode','scope_pharmacy_ids',(SELECT coalesce(jsonb_agg(coalesce((SELECT r.pharmacy_id FROM public.scl290_registry r WHERE r.id::text=x LIMIT 1)::text,x)),'[]') FROM jsonb_array_elements_text(coalesce(coalesce(m.scope_override,m.campaign->'scope')->'ids','[]')) x),'pharmacy_billable',false,'updated_at',m.updated_at) ORDER BY m.month_on),'[]') INTO records FROM scl_private.pp_months m WHERE extract(year FROM m.month_on)=p_year;
 RETURN QUERY SELECT x.* FROM jsonb_to_recordset(records) AS x(id uuid, year integer, month integer, campaign_type text, title text, supplier text, date_range text, company_benefit text, placement_dates text, products_text text, instore_materials text, digital_support text, shelf_instructions text, shelf_1 text, shelf_2 text, shelf_3 text, shelf_4 text, notes text, fallback_title text, fallback_description text, fallback_products_text text, fallback_instructions text, scope_mode text, scope_pharmacy_ids uuid[], pharmacy_billable boolean, updated_at timestamp with time zone);
END;
$function$;
REVOKE ALL ON FUNCTION public.hq_upsert_pharmaplus_campaign(text,integer,integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,uuid[],text,text,text,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.pharmacy_get_pharmaplus_campaigns(p_pharmacy_token text, p_year integer)
 RETURNS TABLE(month integer, display_kind text, display_title text, campaign_type text, title text, supplier text, date_range text, company_benefit text, placement_dates text, products_text text, instore_materials text, digital_support text, shelf_instructions text, shelf_1 text, shelf_2 text, shelf_3 text, shelf_4 text, notes text, fallback_title text, fallback_description text, fallback_products_text text, fallback_instructions text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN RETURN QUERY SELECT x.* FROM jsonb_to_recordset(public.scl300_pp_pharmacy(p_pharmacy_token,p_year)) AS x(month integer, display_kind text, display_title text, campaign_type text, title text, supplier text, date_range text, company_benefit text, placement_dates text, products_text text, instore_materials text, digital_support text, shelf_instructions text, shelf_1 text, shelf_2 text, shelf_3 text, shelf_4 text, notes text, fallback_title text, fallback_description text, fallback_products_text text, fallback_instructions text);END;
$function$;

