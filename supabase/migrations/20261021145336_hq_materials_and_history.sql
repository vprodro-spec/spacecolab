-- Material records are separate from pharmacy programmes and financial events.
CREATE TABLE scl_private.agreement_materials (
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 year integer NOT NULL,position_id text NOT NULL,event_key text NOT NULL,orientation text NOT NULL CHECK(orientation IN ('vertical','horizontal')),
 filename text NOT NULL DEFAULT '',status text NOT NULL CHECK(status IN ('awaiting','received','ready')),revision bigint NOT NULL DEFAULT 1,updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(pharmacy_id,year,event_key,orientation)
);
CREATE TABLE scl_private.material_history (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 year integer NOT NULL,position_id text NOT NULL,event_key text NOT NULL,orientation text NOT NULL,before_data jsonb,after_data jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE scl_private.agreement_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.material_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.agreement_materials,scl_private.material_history FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.scl304_materials(p_hq_key text,p_year integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 THEN RAISE EXCEPTION 'Μη έγκυρο έτος';END IF;
 RETURN jsonb_build_object('year',p_year,'items',(SELECT coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object(
 'pharmacy_id',s.pharmacy_id,'pharmacy_name',r.name,'year',s.year,'orientation',pos->>'screenFormat',
 'deadline',make_date(p_year,b.start_month+1,1)-14,'filename',coalesce(a.filename,''),'status',coalesce(a.status,'awaiting'),'revision',coalesce(a.revision,0),'updated_at',a.updated_at)),'[]')
 FROM public.scl290_snapshots s JOIN public.scl290_registry r ON r.pharmacy_id=s.pharmacy_id
 JOIN public.scl290_installations i ON i.pharmacy_id=s.pharmacy_id
 CROSS JOIN LATERAL scl_private.blocks(s.year,s.state_json) b
 CROSS JOIN LATERAL jsonb_array_elements(i.positions) pos
 LEFT JOIN scl_private.agreement_materials a ON a.pharmacy_id=s.pharmacy_id AND a.year=s.year AND a.event_key=b.event_key AND a.orientation=pos->>'screenFormat'
 WHERE s.year=p_year AND b.category='deal' AND pos->>'id'=b.position_id
 AND coalesce(nullif(pos->>'startsOn','')::date,make_date(p_year,1,1))<=make_date(p_year,b.end_month+1,1)
 AND coalesce(nullif(pos->>'stopsOn','')::date,make_date(p_year+1,1,1))>make_date(p_year,b.start_month+1,1)));
END $$;

CREATE FUNCTION public.scl304_save_material(p_hq_key text,p_pharmacy_id uuid,p_year integer,p_event_key text,p_orientation text,p_revision bigint,p_filename text,p_status text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item jsonb;old scl_private.agreement_materials;result scl_private.agreement_materials;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_status IS NULL OR p_status NOT IN ('awaiting','received','ready') OR p_orientation IS NULL OR p_orientation NOT IN ('vertical','horizontal') OR p_filename IS NULL OR length(p_filename)>255 OR p_filename~E'[\\n\\r/\\\\]' OR (p_status<>'awaiting' AND btrim(p_filename)='') THEN RAISE EXCEPTION 'Συμπληρώστε έγκυρο όνομα αρχείου και κατάσταση υλικού';END IF;
 PERFORM 1 FROM public.scl290_snapshots WHERE pharmacy_id=p_pharmacy_id AND year=p_year FOR UPDATE;
 SELECT v INTO item FROM jsonb_array_elements(public.scl304_materials(p_hq_key,p_year)->'items') v WHERE v->>'pharmacy_id'=p_pharmacy_id::text AND v->>'event_key'=p_event_key AND v->>'orientation'=p_orientation;
 IF item IS NULL THEN RAISE EXCEPTION 'Η συμφωνία ή ο προσανατολισμός άλλαξε. Ανανεώστε πριν αποθηκεύσετε.';END IF;
 IF make_date(p_year,(item->>'end_month')::integer+1,1)<date_trunc('month',scl_private.today())::date THEN RAISE EXCEPTION 'Το υλικό προηγούμενων μηνών διατηρείται στο ιστορικό';END IF;
 SELECT * INTO old FROM scl_private.agreement_materials WHERE pharmacy_id=p_pharmacy_id AND year=p_year AND event_key=p_event_key AND orientation=p_orientation FOR UPDATE;
 IF coalesce(old.revision,0) IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Τα στοιχεία υλικού άλλαξαν. Ανανεώστε πριν αποθηκεύσετε.';END IF;
 IF old.filename=btrim(p_filename) AND old.status=p_status THEN RETURN to_jsonb(old);END IF;
 INSERT INTO scl_private.agreement_materials(pharmacy_id,year,position_id,event_key,orientation,filename,status) VALUES(p_pharmacy_id,p_year,item->>'position_id',p_event_key,p_orientation,btrim(p_filename),p_status)
 ON CONFLICT(pharmacy_id,year,event_key,orientation) DO UPDATE SET filename=excluded.filename,status=excluded.status,revision=agreement_materials.revision+1,updated_at=now() RETURNING * INTO result;
 INSERT INTO scl_private.material_history(pharmacy_id,year,position_id,event_key,orientation,before_data,after_data) VALUES(p_pharmacy_id,p_year,result.position_id,p_event_key,p_orientation,CASE WHEN old.revision IS NULL THEN NULL ELSE to_jsonb(old) END,to_jsonb(result));
 RETURN to_jsonb(result);
END $$;

CREATE FUNCTION public.scl304_task_history(p_hq_key text,p_change_key text,p_pharmacy_id uuid,p_year integer,p_position_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN jsonb_build_object('completion',(SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY created_at DESC),'[]') FROM public.scl292_completion_history h WHERE change_key=p_change_key),
 'materials',(SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY created_at DESC),'[]') FROM scl_private.material_history h WHERE pharmacy_id=p_pharmacy_id AND year=p_year AND position_id=p_position_id));
END $$;

CREATE FUNCTION public.scl304_program_history(p_id uuid,p_token text DEFAULT NULL,p_hq_key text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE h public.scl292_program_history;pid uuid;n jsonb;
BEGIN
 IF p_hq_key IS NOT NULL THEN PERFORM public.scl290_assert_hq(p_hq_key);ELSE pid:=public.scl290_token_id(p_token);END IF;
 SELECT * INTO h FROM public.scl292_program_history WHERE id=p_id AND (pid IS NULL OR pharmacy_id=pid);
 IF h.id IS NULL THEN RAISE EXCEPTION 'Η καταχώριση ιστορικού δεν είναι διαθέσιμη';END IF;
 SELECT state_json INTO n FROM public.scl292_program_history WHERE pharmacy_id=h.pharmacy_id AND year=h.year AND revision>h.revision ORDER BY revision LIMIT 1;
 IF n IS NULL THEN SELECT state_json INTO n FROM public.scl290_snapshots WHERE pharmacy_id=h.pharmacy_id AND year=h.year;END IF;
 RETURN jsonb_build_object('year',h.year,'revision',h.revision,'created_at',h.created_at,'reason',h.reason,'before',h.state_json,'after',n);
END $$;

-- A filename correction never creates a new content task. Preserve the old media
-- identity, while keeping exact filenames in the single campaign/theme source.
CREATE FUNCTION public.scl304_pp_file(p_hq_key text,p_month_on date,p_kind text,p_orientation text,p_filename text,p_expected_revision bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old scl_private.pp_months;r scl_private.pp_months;d jsonb;nd jsonb;rev bigint;counted integer:=0;prop text;dates jsonb:='[]';
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF p_kind IS NULL OR p_kind NOT IN ('campaign','thematic') OR p_orientation IS NULL OR p_orientation NOT IN ('vertical','horizontal') OR p_filename IS NULL OR length(btrim(p_filename)) NOT BETWEEN 1 AND 255 OR p_filename~E'[\\n\\r/\\\\]' THEN RAISE EXCEPTION 'Συμπληρώστε έγκυρο όνομα αρχείου';END IF;
 IF p_month_on<date_trunc('month',scl_private.today())::date THEN RAISE EXCEPTION 'Τα αρχεία προηγούμενων μηνών παραμένουν στο ιστορικό';END IF;
 SELECT revision INTO rev FROM scl_private.pp_meta FOR UPDATE;
 IF rev IS DISTINCT FROM p_expected_revision THEN RAISE EXCEPTION 'Το πρόγραμμα Pharmaplus άλλαξε. Ανανεώστε πριν αποθηκεύσετε.';END IF;
 SELECT * INTO old FROM scl_private.pp_months WHERE month_on=p_month_on;
 d:=CASE WHEN p_kind='campaign' THEN old.campaign ELSE old.thematic END;
 IF nullif(d->>'title','') IS NULL THEN RAISE EXCEPTION 'Καταχωρίστε πρώτα καμπάνια ή θεματική';END IF;
 IF p_kind='thematic' AND d ? 'theme_id' THEN RAISE EXCEPTION 'Το αρχείο αυτής της θεματικής ορίζεται στη βιβλιοθήκη';END IF;
 nd:=d||jsonb_build_object('file_identity',coalesce(d->'file_identity',jsonb_build_object('vertical',coalesce(d->'files'->>'vertical',''),'horizontal',coalesce(d->'files'->>'horizontal',''))),'files',coalesce(d->'files','{}')||jsonb_build_object(p_orientation,btrim(p_filename)));
 FOR r IN SELECT * FROM scl_private.pp_months WHERE month_on>=date_trunc('month',scl_private.today())::date AND
 CASE WHEN p_kind='campaign' THEN campaign_id=old.campaign_id AND campaign=d ELSE thematic=d END FOR UPDATE LOOP
  INSERT INTO scl_private.pp_history(revision,action,month_on,before_data,after_data) VALUES(rev+1,'file',r.month_on,to_jsonb(r),to_jsonb(r)||jsonb_build_object(p_kind,nd));
  IF p_kind='campaign' THEN UPDATE scl_private.pp_months SET campaign=nd,updated_at=now() WHERE month_on=r.month_on;
  ELSE UPDATE scl_private.pp_months SET thematic=nd,updated_at=now() WHERE month_on=r.month_on;END IF;
  dates:=dates||jsonb_build_array(r.month_on);counted:=counted+1;
 END LOOP;
 UPDATE scl_private.pp_meta SET revision=revision+1;
 RETURN jsonb_build_object('months',dates,'updated',counted);
END $$;
REVOKE ALL ON FUNCTION public.scl304_materials(text,integer),public.scl304_save_material(text,uuid,integer,text,text,bigint,text,text),public.scl304_task_history(text,text,uuid,integer,text),public.scl304_program_history(uuid,text,text),public.scl304_pp_file(text,date,text,text,text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl304_materials(text,integer),public.scl304_save_material(text,uuid,integer,text,text,bigint,text,text),public.scl304_task_history(text,text,uuid,integer,text),public.scl304_program_history(uuid,text,text),public.scl304_pp_file(text,date,text,text,text,bigint) TO anon,authenticated;
NOTIFY pgrst,'reload schema';

CREATE OR REPLACE FUNCTION scl_private.pp_resolve(slot jsonb,pid uuid,rid uuid,fmt text) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE d jsonb;kind text;cid text;identity text;file text;BEGIN
 IF nullif(slot->>'campaign_id','') IS NOT NULL AND scl_private.pp_scope(coalesce(nullif(slot->'scope_override','null'::jsonb),slot->'campaign'->'scope'),pid,rid) THEN
  d:=slot->'campaign';kind:='main';cid:=slot->>'campaign_id';identity:='campaign:'||cid;
 ELSE d:=coalesce(slot->'thematic','{}'::jsonb);kind:='fallback';identity:='theme:'||coalesce(d->>'theme_id',d->>'title','');END IF;
 IF nullif(d->>'title','') IS NULL THEN RETURN jsonb_build_object('display_kind','empty','display_title','Προσεχώς','content_key','empty','file_name','');END IF;
 file:=coalesce(d->'files'->>fmt,'');
 RETURN jsonb_build_object('display_kind',kind,'display_title',d->>'title','campaign_id',cid,'theme_id',d->>'theme_id','file_name',file,'content_revision',coalesce(d->'media_revision'->>fmt,''),'content_key',identity||':'||md5(jsonb_build_array(d->>'title',CASE WHEN d ? 'theme_id' THEN coalesce(d->'media_revision'->>fmt,'') ELSE coalesce(d->'file_identity'->>fmt,file) END)::text))
 || CASE WHEN kind='main' THEN d-'scope'-'files' ELSE jsonb_build_object('fallback_title',d->>'title') END;
END $$;

