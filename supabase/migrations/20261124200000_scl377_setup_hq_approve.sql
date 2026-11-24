-- SCL377 · Κ2γ: «Στησίματα» για τα Κεντρικά, έγκριση φωτογραφίας για την εταιρία, μέγεθος κάθε φωτογραφίας.
-- ΑΛΛΑΖΕΙ μόνο 2 συναρτήσεις του Κ2γ (scl375_ph_done, scl375_photo_commit) και προσθέτει 3 στήλες στον πίνακα του Κ2γ scl_private.ph_setup_done.
-- Καμία παλιότερη συνάρτηση ή πίνακας δεν αλλάζει. Αντίγραφο: scl_private.backup_v377_functions. Rollback: …_rollback.sql
BEGIN;
CREATE TABLE scl_private.backup_v377_functions(sig text PRIMARY KEY, def text NOT NULL, at timestamptz NOT NULL DEFAULT now());
ALTER TABLE scl_private.backup_v377_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v377_functions FROM PUBLIC,anon,authenticated;
INSERT INTO scl_private.backup_v377_functions(sig,def) SELECT s, pg_get_functiondef(s::regprocedure) FROM unnest(ARRAY['public.scl375_ph_done(text,integer)','public.scl375_photo_commit(text,text,text)']) s;

ALTER TABLE scl_private.ph_setup_done ADD COLUMN photo_bytes int, ADD COLUMN approved_at timestamptz, ADD COLUMN approved_by text;

DO $do$ DECLARE d text; a text := $a$'photo',d.photo_key IS NOT NULL)$a$;
BEGIN
 d := pg_get_functiondef('public.scl375_ph_done(text,integer)'::regprocedure);
 IF (length(d)-length(replace(d,a,'')))/length(a)<>1 THEN RAISE EXCEPTION 'SCL377: η scl375_ph_done δεν είναι όπως την περιμένω'; END IF;
 EXECUTE replace(d,a,$b$'photo',d.photo_key IS NOT NULL,'approved_at',d.approved_at,'approved_by',d.approved_by)$b$);
END $do$;

-- Νέα φωτογραφία = η έγκριση για την εταιρία φεύγει και θέλει ξανά.
DROP FUNCTION public.scl375_photo_commit(text,text,text);
CREATE FUNCTION public.scl375_photo_commit(p_link text, p_position_id text, p_path text, p_bytes int DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE w record; t timestamp := now() AT TIME ZONE 'Europe/Athens'; y int := extract(year FROM t)::int; m int := extract(month FROM t)::int; old text;
BEGIN
 SELECT * INTO w FROM scl_private.ph375_who(p_link);
 IF p_path IS NOT NULL AND p_path NOT LIKE w.pharmacy_id::text||'/'||y||'-'||lpad(m::text,2,'0')||'/'||p_position_id||'-%.jpg' THEN RAISE EXCEPTION 'Μη έγκυρο αρχείο.' USING ERRCODE='22023'; END IF;
 SELECT x.photo_key INTO old FROM scl_private.ph_setup_done x WHERE x.pharmacy_id=w.pharmacy_id AND x.year=y AND x.month=m AND x.position_id=p_position_id
  AND (w.role IN ('owner','manager') OR x.person_id IS NOT DISTINCT FROM w.person_id) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Τη φωτογραφία την αλλάζει όποιος δήλωσε το «Στήθηκε» ή ο Υπεύθυνος.' USING ERRCODE='42501'; END IF;
 UPDATE scl_private.ph_setup_done x SET photo_key=p_path, photo_bytes=CASE WHEN p_path IS NULL THEN NULL ELSE p_bytes END, approved_at=NULL, approved_by=NULL
  WHERE x.pharmacy_id=w.pharmacy_id AND x.year=y AND x.month=m AND x.position_id=p_position_id;
 RETURN jsonb_build_object('old', old, 'photo', p_path IS NOT NULL);
END $$;

CREATE FUNCTION public.scl375_photo_path_hq(p_key text, p_pharmacy_id uuid, p_year int, p_month int, p_position_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_key);
 RETURN jsonb_build_object('path',(SELECT x.photo_key FROM scl_private.ph_setup_done x WHERE x.pharmacy_id=p_pharmacy_id AND x.year=p_year AND x.month=p_month AND x.position_id=p_position_id));
END $$;
REVOKE ALL ON FUNCTION public.scl375_photo_commit(text,text,text,int),public.scl375_photo_path_hq(text,uuid,int,int,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl375_photo_commit(text,text,text,int),public.scl375_photo_path_hq(text,uuid,int,int,text) TO service_role;

-- ΚΕΝΤΡΙΚΑ: όλα τα φαρμακεία για έναν μήνα. Τι θέλει στήσιμο, τι στήθηκε, από ποιον, αν έχει φωτογραφία, αν εγκρίθηκε για την εταιρία. Και ο χώρος που πιάνουν οι φωτογραφίες.
CREATE FUNCTION public.scl375_hq_setups(p_key text, p_year int, p_month int) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_stats jsonb := jsonb_build_object('photos',0,'bytes',0);
BEGIN
 PERFORM public.scl290_assert_hq(p_key);
 IF p_year IS NULL OR p_month IS NULL OR p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'Μη έγκυρος μήνας.' USING ERRCODE='22023'; END IF;
 IF to_regclass('storage.objects') IS NOT NULL THEN
  EXECUTE $q$SELECT jsonb_build_object('photos',count(*),'bytes',coalesce(sum((metadata->>'size')::bigint),0)) FROM storage.objects WHERE bucket_id='scl375-setup'$q$ INTO v_stats;
 END IF;
 RETURN jsonb_build_object('year',p_year,'month',p_month,'storage',v_stats,'pharmacies',(
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(r.name,p.name),'code',r.pharmacy_code,'area',r.area,
    'people',(SELECT count(*) FROM scl_private.ph_person pe WHERE pe.pharmacy_id=p.id AND pe.revoked_at IS NULL),
    'positions',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e->>'id','title',e->>'title','type',e->>'type','category',e->>'category',
        'what',mm.m->>'final_title','kind',mm.m->>'final_type','supplier',mm.m->>'supplier','brand',mm.m->>'brand',
        'need',(e->>'type'='hq' AND mm.m IS NOT NULL) OR coalesce((mm.m->>'content_change_required')::boolean,false),
        'done',CASE WHEN d.pharmacy_id IS NULL THEN NULL ELSE jsonb_build_object('name',d.person_name,'at',d.done_at,'photo',d.photo_key IS NOT NULL,'bytes',d.photo_bytes,'approved_at',d.approved_at,'approved_by',d.approved_by) END)
       ORDER BY CASE e->>'type' WHEN 'hq' THEN 0 WHEN 'base' THEN 1 WHEN 'promo' THEN 2 ELSE 3 END,(e->>'ordinal')::numeric NULLS LAST),'[]'::jsonb)
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(i.positions)='array' THEN i.positions ELSE '[]'::jsonb END) e
      LEFT JOIN LATERAL (SELECT x AS m FROM public.scl290_snapshots s, jsonb_array_elements(CASE WHEN jsonb_typeof(s.months_json)='array' THEN s.months_json ELSE '[]'::jsonb END) x
         WHERE s.pharmacy_id=p.id AND s.year=p_year AND x->>'position_id'=e->>'id' AND (x->>'month')::int=p_month-1 LIMIT 1) mm ON true
      LEFT JOIN scl_private.ph_setup_done d ON d.pharmacy_id=p.id AND d.year=p_year AND d.month=p_month AND d.position_id=e->>'id'))
    ORDER BY coalesce(r.name,p.name)),'[]'::jsonb)
  FROM public.pharmacies p JOIN public.scl290_registry r ON r.pharmacy_id=p.id LEFT JOIN public.scl290_installations i ON i.pharmacy_id=p.id));
END $$;

-- Έγκριση φωτογραφίας για την εταιρία: Κεντρικά ή φαρμακείο (ιδιοκτήτης, Υπεύθυνος). Μόνο αν υπάρχει φωτογραφία.
CREATE FUNCTION scl_private.ph377_approve(p_pharmacy_id uuid, p_year int, p_month int, p_position_id text, p_on boolean, p_by text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE d scl_private.ph_setup_done;
BEGIN
 UPDATE scl_private.ph_setup_done x SET approved_at=CASE WHEN coalesce(p_on,true) THEN now() END, approved_by=CASE WHEN coalesce(p_on,true) THEN p_by END
  WHERE x.pharmacy_id=p_pharmacy_id AND x.year=p_year AND x.month=p_month AND x.position_id=p_position_id AND x.photo_key IS NOT NULL RETURNING * INTO d;
 IF NOT FOUND THEN RAISE EXCEPTION 'Δεν υπάρχει φωτογραφία στησίματος για έγκριση.' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('year',d.year,'month',d.month,'position_id',d.position_id,'approved_at',d.approved_at,'approved_by',d.approved_by);
END $$;
REVOKE ALL ON FUNCTION scl_private.ph377_approve(uuid,int,int,text,boolean,text) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.scl375_hq_setup_approve(p_key text, p_pharmacy_id uuid, p_year int, p_month int, p_position_id text, p_on boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN PERFORM public.scl290_assert_hq(p_key); RETURN scl_private.ph377_approve(p_pharmacy_id,p_year,p_month,p_position_id,p_on,'Κεντρικά'); END $$;
CREATE FUNCTION public.scl375_ph_setup_approve(p_token text, p_year int, p_month int, p_position_id text, p_on boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid := public.scl290_token_id(p_token);
BEGIN RETURN scl_private.ph377_approve(pid,p_year,p_month,p_position_id,p_on,coalesce('Φαρμακείο · '||scl_private.ph375_actor(),'Φαρμακείο')); END $$;
REVOKE ALL ON FUNCTION public.scl375_hq_setups(text,int,int),public.scl375_hq_setup_approve(text,uuid,int,int,text,boolean),public.scl375_ph_setup_approve(text,int,int,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl375_hq_setups(text,int,int),public.scl375_hq_setup_approve(text,uuid,int,int,text,boolean),public.scl375_ph_setup_approve(text,int,int,text,boolean) TO anon,authenticated;
COMMIT;
