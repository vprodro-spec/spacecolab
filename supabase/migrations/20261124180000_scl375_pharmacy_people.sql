-- SCL375 · Κ2γ «Άνθρωποι φαρμακείου»
-- ΤΙ ΚΑΝΕΙ: σύνδεσμοι με όνομα ανά φαρμακείο (Υπεύθυνος ή Υπάλληλος), που ανακαλούνται. Χωρίς κωδικούς.
--  · Υπεύθυνος: ο σύνδεσμός του δουλεύει στο εργαλείο όπως του ιδιοκτήτη. Δεν φτιάχνει ούτε ανακαλεί συνδέσμους.
--  · Υπάλληλος: ο σύνδεσμός του ΔΕΝ ανοίγει το εργαλείο. Διαβάζει μόνο μία συνάρτηση, που δεν στέλνει ποσά, τζίρο ή χρεώσεις.
--  · «Στήθηκε»: ανά θέση και μήνα, με όνομα, ημέρα και ώρα. Θέση για φωτογραφία (photo_key) που μένει άδεια προς το παρόν.
-- ΤΙ ΑΛΛΑΖΕΙ ΣΕ ΥΠΑΡΧΟΝΤΑ: μία γραμμή στην αρχή 5 συναρτήσεων (scl290_token_id και οι 4 upsert_*_by_token) και μία νέα στήλη
--  «person» σε 3 πίνακες ιστορικού. Αντίγραφο των 5 συναρτήσεων στο scl_private.backup_v375_functions. Rollback: …_rollback.sql
BEGIN;

CREATE TABLE scl_private.backup_v375_functions(sig text PRIMARY KEY, def text NOT NULL, at timestamptz NOT NULL DEFAULT now());
ALTER TABLE scl_private.backup_v375_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v375_functions FROM PUBLIC,anon,authenticated;

CREATE TABLE scl_private.ph_person(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 name text NOT NULL CHECK (char_length(name) BETWEEN 2 AND 60),
 role text NOT NULL CHECK (role IN ('manager','staff')),
 token text NOT NULL UNIQUE DEFAULT encode(extensions.gen_random_bytes(24),'hex'),
 created_at timestamptz NOT NULL DEFAULT now(),
 last_seen_at timestamptz,
 revoked_at timestamptz,
 revoked_by text);
CREATE INDEX ph_person_pharmacy ON scl_private.ph_person(pharmacy_id,created_at);
ALTER TABLE scl_private.ph_person ENABLE ROW LEVEL SECURITY;

CREATE TABLE scl_private.ph_setup_done(
 pharmacy_id uuid NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
 year int NOT NULL, month int NOT NULL CHECK (month BETWEEN 1 AND 12), position_id text NOT NULL,
 person_id uuid REFERENCES scl_private.ph_person(id) ON DELETE SET NULL,
 person_name text NOT NULL,
 done_at timestamptz NOT NULL DEFAULT now(),
 photo_key text,
 PRIMARY KEY(pharmacy_id,year,month,position_id));
ALTER TABLE scl_private.ph_setup_done ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.ph_person,scl_private.ph_setup_done FROM PUBLIC,anon,authenticated;

-- Ποιος ενεργεί σε αυτή τη συναλλαγή (όνομα Υπευθύνου) ή NULL όταν είναι ο σύνδεσμος του ιδιοκτήτη.
CREATE FUNCTION scl_private.ph375_actor() RETURNS text LANGUAGE sql STABLE SET search_path TO '' AS
$$ SELECT nullif(current_setting('scl375.actor',true),'') $$;

-- Σύνδεσμος Υπευθύνου -> ο σύνδεσμος του φαρμακείου (μόνο μέσα στη βάση, δεν επιστρέφεται ποτέ σε οθόνη). Οτιδήποτε άλλο μένει όπως ήρθε.
CREATE FUNCTION scl_private.ph375_token(p_token text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r record;
BEGIN
 IF p_token IS NULL OR p_token='' THEN RETURN p_token; END IF;
 SELECT pe.name, ph.token::text AS tok INTO r FROM scl_private.ph_person pe JOIN public.pharmacies ph ON ph.id=pe.pharmacy_id
  WHERE pe.token=p_token AND pe.role='manager' AND pe.revoked_at IS NULL;
 IF NOT FOUND THEN RETURN p_token; END IF;
 PERFORM set_config('scl375.actor', r.name, true);
 RETURN r.tok;
END $$;

-- Μόνο ο σύνδεσμος του ιδιοκτήτη (όχι Υπευθύνου).
CREATE FUNCTION scl_private.ph375_owner_id(p_token text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid;
BEGIN
 SELECT p.id INTO pid FROM public.pharmacies p JOIN public.scl290_registry r ON r.pharmacy_id=p.id WHERE p_token IS NOT NULL AND p_token<>'' AND p.token::text=p_token;
 IF pid IS NULL THEN RAISE EXCEPTION 'OWNER_ONLY' USING ERRCODE='42501'; END IF;
 RETURN pid;
END $$;

-- Ποιος είναι πίσω από έναν σύνδεσμο: ιδιοκτήτης, Υπεύθυνος ή Υπάλληλος.
CREATE FUNCTION scl_private.ph375_who(p_link text, OUT pharmacy_id uuid, OUT person_id uuid, OUT name text, OUT role text) LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 IF p_link IS NULL OR p_link='' THEN RAISE EXCEPTION 'PHARMACY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 SELECT pe.pharmacy_id, pe.id, pe.name, pe.role INTO pharmacy_id, person_id, name, role FROM scl_private.ph_person pe
  JOIN public.scl290_registry r ON r.pharmacy_id=pe.pharmacy_id WHERE pe.token=p_link AND pe.revoked_at IS NULL;
 IF FOUND THEN RETURN; END IF;
 SELECT p.id, NULL::uuid, NULL::text, 'owner' INTO pharmacy_id, person_id, name, role FROM public.pharmacies p
  JOIN public.scl290_registry r ON r.pharmacy_id=p.id WHERE p.token::text=p_link;
 IF NOT FOUND THEN RAISE EXCEPTION 'PHARMACY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
END $$;

CREATE FUNCTION scl_private.ph375_pick(j jsonb, keys text[]) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO '' AS
$$ SELECT coalesce(jsonb_object_agg(k, j->k),'{}'::jsonb) FROM unnest(keys) k WHERE jsonb_typeof(j)='object' AND j ? k $$;

CREATE FUNCTION scl_private.ph375_person_json(pe scl_private.ph_person, p_with_link boolean) RETURNS jsonb LANGUAGE sql STABLE SET search_path TO '' AS $$
 SELECT jsonb_build_object('id',pe.id,'name',pe.name,'role',pe.role,'created_at',pe.created_at,'last_seen_at',pe.last_seen_at,'revoked_at',pe.revoked_at,'revoked_by',pe.revoked_by)
  || CASE WHEN p_with_link AND pe.revoked_at IS NULL THEN jsonb_build_object('link',pe.token) ELSE '{}'::jsonb END $$;

REVOKE ALL ON FUNCTION scl_private.ph375_actor(),scl_private.ph375_token(text),scl_private.ph375_owner_id(text),scl_private.ph375_who(text),scl_private.ph375_pick(jsonb,text[]),scl_private.ph375_person_json(scl_private.ph_person,boolean) FROM PUBLIC,anon,authenticated;

-- ΥΠΑΡΧΟΥΣΕΣ ΣΥΝΑΡΤΗΣΕΙΣ: μία γραμμή στην αρχή, ώστε να δέχονται και σύνδεσμο Υπευθύνου. Αν κάτι δεν είναι όπως το περιμένω, σταματά και δεν αλλάζει τίποτα.
DO $do$
DECLARE f regprocedure; d text; n text; line text := E'\n  p_token := scl_private.ph375_token(p_token);';
BEGIN
 FOREACH f IN ARRAY ARRAY['public.scl290_token_id(text)'::regprocedure,
   'public.upsert_pharmacy_state_by_token(text,integer,jsonb)'::regprocedure,
   'public.upsert_pharmacy_setup_summary_by_token(text,integer,boolean,integer,integer,integer,boolean,jsonb)'::regprocedure,
   'public.upsert_pharmacy_position_months_by_token(text,integer,jsonb)'::regprocedure,
   'public.upsert_pharmacy_deals_by_token(text,integer,jsonb)'::regprocedure] LOOP
  d := pg_get_functiondef(f);
  IF d ~ 'ph375_token' THEN RAISE EXCEPTION 'SCL375: η % έχει ήδη αλλάξει', f; END IF;
  IF (SELECT prolang<>(SELECT oid FROM pg_language WHERE lanname='plpgsql') OR proargnames[1]<>'p_token' FROM pg_proc WHERE oid=f) THEN RAISE EXCEPTION 'SCL375: η % δεν είναι όπως την περιμένω', f; END IF;
  n := regexp_replace(d, '(\$function\$.*?\mbegin\M)', E'\\1'||line, 'i');
  IF n = d OR position(line IN n)=0 THEN RAISE EXCEPTION 'SCL375: δεν βρέθηκε η αρχή της %', f; END IF;
  INSERT INTO scl_private.backup_v375_functions(sig,def) VALUES (f::text,d);
  EXECUTE n;
 END LOOP;
END $do$;

-- Ποιος το έκανε: γράφεται μόνο του σε κάθε νέα γραμμή ιστορικού, χωρίς να αλλάξει καμία συνάρτηση που γράφει ιστορικό.
ALTER TABLE public.scl292_program_history ADD COLUMN person text;
ALTER TABLE public.scl292_program_history ALTER COLUMN person SET DEFAULT scl_private.ph375_actor();
ALTER TABLE public.scl292_reset_requests ADD COLUMN person text;
ALTER TABLE public.scl292_reset_requests ALTER COLUMN person SET DEFAULT scl_private.ph375_actor();
ALTER TABLE scl_private.mk_request_log ADD COLUMN person text;
ALTER TABLE scl_private.mk_request_log ALTER COLUMN person SET DEFAULT scl_private.ph375_actor();

-- ΕΡΓΑΛΕΙΟ ΦΑΡΜΑΚΕΙΟΥ
CREATE FUNCTION public.scl375_ph_whoami(p_token text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE w record;
BEGIN
 SELECT * INTO w FROM scl_private.ph375_who(p_token);
 IF w.role='staff' THEN RAISE EXCEPTION 'PHARMACY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF w.person_id IS NOT NULL THEN UPDATE scl_private.ph_person SET last_seen_at=now() WHERE id=w.person_id; END IF;
 RETURN jsonb_build_object('role',w.role,'name',w.name);
END $$;

CREATE FUNCTION public.scl375_ph_people(p_token text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid := scl_private.ph375_owner_id(p_token);
BEGIN
 RETURN jsonb_build_object('people',(SELECT coalesce(jsonb_agg(scl_private.ph375_person_json(pe,true) ORDER BY (pe.revoked_at IS NOT NULL), pe.created_at),'[]'::jsonb) FROM scl_private.ph_person pe WHERE pe.pharmacy_id=pid));
END $$;

CREATE FUNCTION public.scl375_ph_person_add(p_token text, p_name text, p_role text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid := scl_private.ph375_owner_id(p_token); v_name text := btrim(regexp_replace(coalesce(p_name,''),'\s+',' ','g')); pe scl_private.ph_person;
BEGIN
 IF char_length(v_name) NOT BETWEEN 2 AND 60 THEN RAISE EXCEPTION 'Γράψε όνομα (2 έως 60 χαρακτήρες).' USING ERRCODE='22023'; END IF;
 IF p_role IS NULL OR p_role NOT IN ('manager','staff') THEN RAISE EXCEPTION 'Διάλεξε Υπεύθυνος ή Υπάλληλος.' USING ERRCODE='22023'; END IF;
 IF (SELECT count(*) FROM scl_private.ph_person WHERE pharmacy_id=pid AND revoked_at IS NULL)>=30 THEN RAISE EXCEPTION 'Έως 30 ενεργοί σύνδεσμοι ανά φαρμακείο.' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM scl_private.ph_person WHERE pharmacy_id=pid AND revoked_at IS NULL AND lower(name)=lower(v_name)) THEN RAISE EXCEPTION 'Υπάρχει ήδη ενεργός σύνδεσμος με αυτό το όνομα.' USING ERRCODE='22023'; END IF;
 INSERT INTO scl_private.ph_person(pharmacy_id,name,role) VALUES (pid,v_name,p_role) RETURNING * INTO pe;
 RETURN scl_private.ph375_person_json(pe,true);
END $$;

CREATE FUNCTION public.scl375_ph_person_revoke(p_token text, p_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid := scl_private.ph375_owner_id(p_token); pe scl_private.ph_person;
BEGIN
 UPDATE scl_private.ph_person SET revoked_at=now(), revoked_by='Φαρμακείο' WHERE id=p_id AND pharmacy_id=pid AND revoked_at IS NULL RETURNING * INTO pe;
 IF NOT FOUND THEN RAISE EXCEPTION 'Ο σύνδεσμος δεν βρέθηκε ή έχει ήδη ανακληθεί.' USING ERRCODE='P0002'; END IF;
 RETURN scl_private.ph375_person_json(pe,false);
END $$;

-- Τι έχει στηθεί (ιδιοκτήτης και Υπεύθυνος).
CREATE FUNCTION public.scl375_ph_done(p_token text, p_year int) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid := public.scl290_token_id(p_token);
BEGIN
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('year',d.year,'month',d.month,'position_id',d.position_id,'name',d.person_name,'at',d.done_at) ORDER BY d.year,d.month,d.position_id),'[]'::jsonb)
  FROM scl_private.ph_setup_done d WHERE d.pharmacy_id=pid AND d.year=p_year);
END $$;

-- ΚΕΝΤΡΙΚΑ: βλέπουν και ανακαλούν. Δεν βλέπουν τους συνδέσμους.
CREATE FUNCTION public.scl375_hq_people(p_key text, p_pharmacy_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_key);
 RETURN jsonb_build_object(
  'people',(SELECT coalesce(jsonb_agg(scl_private.ph375_person_json(pe,false) ORDER BY (pe.revoked_at IS NOT NULL), pe.created_at),'[]'::jsonb) FROM scl_private.ph_person pe WHERE pe.pharmacy_id=p_pharmacy_id),
  'done',(SELECT coalesce(jsonb_agg(jsonb_build_object('year',d.year,'month',d.month,'position_id',d.position_id,'name',d.person_name,'at',d.done_at) ORDER BY d.year DESC,d.month DESC,d.position_id),'[]'::jsonb) FROM scl_private.ph_setup_done d WHERE d.pharmacy_id=p_pharmacy_id));
END $$;

CREATE FUNCTION public.scl375_hq_person_revoke(p_key text, p_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pe scl_private.ph_person;
BEGIN
 PERFORM public.scl290_assert_hq(p_key);
 UPDATE scl_private.ph_person SET revoked_at=now(), revoked_by='Κεντρικά' WHERE id=p_id AND revoked_at IS NULL RETURNING * INTO pe;
 IF NOT FOUND THEN RAISE EXCEPTION 'Ο σύνδεσμος δεν βρέθηκε ή έχει ήδη ανακληθεί.' USING ERRCODE='P0002'; END IF;
 RETURN scl_private.ph375_person_json(pe,false);
END $$;

-- ΣΕΛΙΔΑ ΥΠΑΛΛΗΛΟΥ: μόνο ό,τι αναφέρεται εδώ με το όνομά του. Ποσά, τζίρος, χρεώσεις και σημειώσεις δεν υπάρχουν στη λίστα.
CREATE FUNCTION public.scl375_staff_get(p_link text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE w record; v_tok text; v_today date := (now() AT TIME ZONE 'Europe/Athens')::date; y int; v_plan jsonb; v_pp jsonb := '{}'::jsonb; v_rows jsonb;
 mk text[] := ARRAY['year','month','position_id','position_name','position_type','position_orientation','player_code','basic_theme','basic_source','final_type','final_title','final_detail','change_from_basic','custom_theme','deal_id','supplier','brand','deal_theme','sponsored_active','sponsored_detail','sponsored_shelves_count','sponsored_shelves_position','content_change_required','content_change_reason','block_start','block_end'];
 dk text[] := ARRAY['deal_uid','position_id','start_month','end_month','supplier','brand','deal_theme','deal_content_mode','product_codes'];
 rk text[] := ARRAY['subline','products','monthlySublines','monthlyProducts','monthlyContentChanges','confirmed'];
BEGIN
 SELECT * INTO w FROM scl_private.ph375_who(p_link);
 IF w.person_id IS NOT NULL THEN UPDATE scl_private.ph_person SET last_seen_at=now() WHERE id=w.person_id; END IF;
 SELECT token::text INTO v_tok FROM public.pharmacies WHERE id=w.pharmacy_id;
 y := extract(year FROM v_today)::int;
 BEGIN v_plan := public.scl350_fp_get(v_tok)->'plan'; EXCEPTION WHEN OTHERS THEN v_plan := NULL; END;
 FOR i IN 0..1 LOOP
  BEGIN
   SELECT coalesce(jsonb_agg(to_jsonb(c) - 'company_benefit' ORDER BY c.month),'[]'::jsonb) INTO v_rows FROM public.pharmacy_get_pharmaplus_campaigns(v_tok, y+i) c;
  EXCEPTION WHEN OTHERS THEN v_rows := '[]'::jsonb; END;
  v_pp := v_pp || jsonb_build_object((y+i)::text, v_rows);
 END LOOP;
 RETURN jsonb_build_object(
  'today', v_today, 'year', y,
  'me', jsonb_build_object('name',w.name,'role',w.role),
  'pharmacy', (SELECT jsonb_build_object('name',coalesce(r.name,p.name),'area',r.area) FROM public.pharmacies p LEFT JOIN public.scl290_registry r ON r.pharmacy_id=p.id WHERE p.id=w.pharmacy_id),
  'positions', (SELECT coalesce(jsonb_agg(scl_private.ph375_pick(e, ARRAY['id','type','title','ordinal','category','playerCode','contentCode','screenFormat','shelves','startsOn','stopsOn']) ORDER BY (e->>'ordinal')::numeric NULLS LAST),'[]'::jsonb)
    FROM public.scl290_installations i, jsonb_array_elements(CASE WHEN jsonb_typeof(i.positions)='array' THEN i.positions ELSE '[]'::jsonb END) e WHERE i.pharmacy_id=w.pharmacy_id),
  'years', (SELECT coalesce(jsonb_object_agg(s.year::text, jsonb_build_object(
     'months',(SELECT coalesce(jsonb_agg(scl_private.ph375_pick(m, mk)),'[]'::jsonb) FROM jsonb_array_elements(CASE WHEN jsonb_typeof(s.months_json)='array' THEN s.months_json ELSE '[]'::jsonb END) m),
     'deals',(SELECT coalesce(jsonb_agg(scl_private.ph375_pick(d, dk) || scl_private.ph375_pick(d->'raw_json', rk)),'[]'::jsonb) FROM jsonb_array_elements(CASE WHEN jsonb_typeof(s.deals_json)='array' THEN s.deals_json ELSE '[]'::jsonb END) d))),'{}'::jsonb)
    FROM public.scl290_snapshots s WHERE s.pharmacy_id=w.pharmacy_id AND s.year IN (y,y+1)),
  'themes', (SELECT coalesce(jsonb_agg(scl_private.ph375_pick(t.data, ARRAY['id','key','title','category','status','variants','legacySlots'])),'[]'::jsonb) FROM public.scl293_themes t),
  'pharmaplus', v_pp,
  'materials', (SELECT coalesce(jsonb_agg(jsonb_build_object('year',a.year,'position_id',a.position_id,'event_key',a.event_key,'orientation',a.orientation,'status',a.status)),'[]'::jsonb) FROM scl_private.agreement_materials a WHERE a.pharmacy_id=w.pharmacy_id AND a.year IN (y,y+1)),
  'plan', v_plan,
  'done', (SELECT coalesce(jsonb_agg(jsonb_build_object('year',d.year,'month',d.month,'position_id',d.position_id,'name',d.person_name,'at',d.done_at,'mine',d.person_id IS NOT DISTINCT FROM w.person_id)),'[]'::jsonb) FROM scl_private.ph_setup_done d WHERE d.pharmacy_id=w.pharmacy_id AND d.year IN (y,y+1)));
END $$;

-- «Στήθηκε» / αναίρεση. Ο πρώτος που το πατά μένει γραμμένος. Αναίρεση: ο ίδιος, Υπεύθυνος ή ιδιοκτήτης.
CREATE FUNCTION public.scl375_staff_done(p_link text, p_year int, p_month int, p_position_id text, p_done boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE w record; y int := extract(year FROM (now() AT TIME ZONE 'Europe/Athens'))::int; d scl_private.ph_setup_done;
BEGIN
 SELECT * INTO w FROM scl_private.ph375_who(p_link);
 IF p_year IS NULL OR p_year NOT IN (y,y+1) OR p_month IS NULL OR p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'Μη έγκυρος μήνας.' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.scl290_installations i, jsonb_array_elements(CASE WHEN jsonb_typeof(i.positions)='array' THEN i.positions ELSE '[]'::jsonb END) e WHERE i.pharmacy_id=w.pharmacy_id AND e->>'id'=p_position_id) THEN RAISE EXCEPTION 'Η θέση δεν βρέθηκε.' USING ERRCODE='P0002'; END IF;
 IF coalesce(p_done,true) THEN
  INSERT INTO scl_private.ph_setup_done(pharmacy_id,year,month,position_id,person_id,person_name) VALUES (w.pharmacy_id,p_year,p_month,p_position_id,w.person_id,coalesce(w.name,'Φαρμακείο')) ON CONFLICT DO NOTHING;
 ELSE
  DELETE FROM scl_private.ph_setup_done x WHERE x.pharmacy_id=w.pharmacy_id AND x.year=p_year AND x.month=p_month AND x.position_id=p_position_id AND (w.role IN ('owner','manager') OR x.person_id IS NOT DISTINCT FROM w.person_id);
  IF NOT FOUND AND EXISTS(SELECT 1 FROM scl_private.ph_setup_done x WHERE x.pharmacy_id=w.pharmacy_id AND x.year=p_year AND x.month=p_month AND x.position_id=p_position_id) THEN RAISE EXCEPTION 'Το έχει δηλώσει άλλος. Αναίρεση μόνο από τον ίδιο ή τον Υπεύθυνο.' USING ERRCODE='42501'; END IF;
 END IF;
 SELECT * INTO d FROM scl_private.ph_setup_done x WHERE x.pharmacy_id=w.pharmacy_id AND x.year=p_year AND x.month=p_month AND x.position_id=p_position_id;
 RETURN jsonb_build_object('year',p_year,'month',p_month,'position_id',p_position_id,'done',d.pharmacy_id IS NOT NULL,'name',d.person_name,'at',d.done_at,'mine',d.pharmacy_id IS NOT NULL AND d.person_id IS NOT DISTINCT FROM w.person_id);
END $$;

REVOKE ALL ON FUNCTION public.scl375_ph_whoami(text),public.scl375_ph_people(text),public.scl375_ph_person_add(text,text,text),public.scl375_ph_person_revoke(text,uuid),public.scl375_ph_done(text,int),public.scl375_hq_people(text,uuid),public.scl375_hq_person_revoke(text,uuid),public.scl375_staff_get(text),public.scl375_staff_done(text,int,int,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl375_ph_whoami(text),public.scl375_ph_people(text),public.scl375_ph_person_add(text,text,text),public.scl375_ph_person_revoke(text,uuid),public.scl375_ph_done(text,int),public.scl375_hq_people(text,uuid),public.scl375_hq_person_revoke(text,uuid),public.scl375_staff_get(text),public.scl375_staff_done(text,int,int,text,boolean) TO anon,authenticated;
COMMIT;
