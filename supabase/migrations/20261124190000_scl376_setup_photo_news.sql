-- SCL376 · Κ2γ: φωτογραφία στο «Στήθηκε», ημερομηνία κλεισίματος συμφωνίας για τα «Νέα», «Στήθηκε» μόνο στον μήνα που τρέχει.
-- ΑΛΛΑΖΕΙ μόνο 4 συναρτήσεις του SCL375 (σημερινές): scl375_staff_get, scl375_staff_done, scl375_ph_done, scl375_hq_people. Αντίγραφο: scl_private.backup_v376_functions.
-- ΠΡΟΣΘΕΤΕΙ 3 συναρτήσεις που τρέχει ΜΟΝΟ το πρόγραμμα των φωτογραφιών (service_role), και έναν κλειστό χώρο αρχείων «scl375-setup» (μόνο JPEG, έως 600 KB).
-- Καμία άλλη υπάρχουσα συνάρτηση ή πίνακας δεν αλλάζει. Rollback: …_rollback.sql
BEGIN;
CREATE TABLE scl_private.backup_v376_functions(sig text PRIMARY KEY, def text NOT NULL, at timestamptz NOT NULL DEFAULT now());
ALTER TABLE scl_private.backup_v376_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v376_functions FROM PUBLIC,anon,authenticated;

DO $do$
DECLARE r record; d text; n text; k int;
BEGIN
 FOR r IN SELECT * FROM (VALUES
  ('public.scl375_staff_get(text)', $a$'monthlyContentChanges','confirmed']$a$, $b$'monthlyContentChanges','confirmed','confirmedAt']$b$),
  ('public.scl375_staff_get(text)', $a$'at',d.done_at,'mine',$a$, $b$'at',d.done_at,'photo',d.photo_key IS NOT NULL,'mine',$b$),
  ('public.scl375_staff_done(text,integer,integer,text,boolean)', $a$IF p_year IS NULL OR p_year NOT IN (y,y+1) OR p_month IS NULL OR p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'Μη έγκυρος μήνας.'$a$, $b$IF p_year IS DISTINCT FROM y OR p_month IS DISTINCT FROM extract(month FROM (now() AT TIME ZONE 'Europe/Athens'))::int THEN RAISE EXCEPTION 'Το «Στήθηκε» δηλώνεται μόνο για τον μήνα που τρέχει.'$b$),
  ('public.scl375_staff_done(text,integer,integer,text,boolean)', $a$'at',d.done_at,'mine',$a$, $b$'at',d.done_at,'photo',d.photo_key IS NOT NULL,'mine',$b$),
  ('public.scl375_ph_done(text,integer)', $a$'name',d.person_name,'at',d.done_at)$a$, $b$'name',d.person_name,'at',d.done_at,'photo',d.photo_key IS NOT NULL)$b$),
  ('public.scl375_hq_people(text,uuid)', $a$'name',d.person_name,'at',d.done_at)$a$, $b$'name',d.person_name,'at',d.done_at,'photo',d.photo_key IS NOT NULL)$b$)) v(sig,a,b) LOOP
  d := pg_get_functiondef(r.sig::regprocedure);
  k := (length(d)-length(replace(d,r.a,'')))/length(r.a);
  IF k<>1 THEN RAISE EXCEPTION 'SCL376: στη % βρέθηκε % φορές το σημείο που περιμένω', r.sig, k; END IF;
  INSERT INTO scl_private.backup_v376_functions(sig,def) VALUES (r.sig,d) ON CONFLICT DO NOTHING;
  n := replace(d,r.a,r.b);
  EXECUTE n;
 END LOOP;
END $do$;

-- Οι 3 παρακάτω ΔΕΝ είναι ανοιχτές στο κοινό: τις καλεί μόνο το πρόγραμμα των φωτογραφιών, αφού ελεγχθεί ο σύνδεσμος εδώ μέσα.
CREATE FUNCTION public.scl375_photo_begin(p_link text, p_position_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE w record; t timestamp := now() AT TIME ZONE 'Europe/Athens'; y int := extract(year FROM t)::int; m int := extract(month FROM t)::int;
BEGIN
 SELECT * INTO w FROM scl_private.ph375_who(p_link);
 IF p_position_id IS NULL OR p_position_id !~ '^[a-z0-9-]{1,40}$' OR NOT EXISTS(SELECT 1 FROM scl_private.ph_setup_done x WHERE x.pharmacy_id=w.pharmacy_id AND x.year=y AND x.month=m AND x.position_id=p_position_id) THEN
  RAISE EXCEPTION 'Πρώτα δήλωσε «Στήθηκε» για αυτή τη θέση.' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('path', w.pharmacy_id::text||'/'||y||'-'||lpad(m::text,2,'0')||'/'||p_position_id||'-'||encode(extensions.gen_random_bytes(8),'hex')||'.jpg');
END $$;

CREATE FUNCTION public.scl375_photo_commit(p_link text, p_position_id text, p_path text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE w record; t timestamp := now() AT TIME ZONE 'Europe/Athens'; y int := extract(year FROM t)::int; m int := extract(month FROM t)::int; old text;
BEGIN
 SELECT * INTO w FROM scl_private.ph375_who(p_link);
 IF p_path IS NOT NULL AND p_path NOT LIKE w.pharmacy_id::text||'/'||y||'-'||lpad(m::text,2,'0')||'/'||p_position_id||'-%.jpg' THEN RAISE EXCEPTION 'Μη έγκυρο αρχείο.' USING ERRCODE='22023'; END IF;
 SELECT x.photo_key INTO old FROM scl_private.ph_setup_done x WHERE x.pharmacy_id=w.pharmacy_id AND x.year=y AND x.month=m AND x.position_id=p_position_id
  AND (w.role IN ('owner','manager') OR x.person_id IS NOT DISTINCT FROM w.person_id) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Τη φωτογραφία την αλλάζει όποιος δήλωσε το «Στήθηκε» ή ο Υπεύθυνος.' USING ERRCODE='42501'; END IF;
 UPDATE scl_private.ph_setup_done x SET photo_key=p_path WHERE x.pharmacy_id=w.pharmacy_id AND x.year=y AND x.month=m AND x.position_id=p_position_id;
 RETURN jsonb_build_object('old', old, 'photo', p_path IS NOT NULL);
END $$;

CREATE FUNCTION public.scl375_photo_path(p_link text, p_year int, p_month int, p_position_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE w record; k text;
BEGIN
 SELECT * INTO w FROM scl_private.ph375_who(p_link);
 SELECT x.photo_key INTO k FROM scl_private.ph_setup_done x WHERE x.pharmacy_id=w.pharmacy_id AND x.year=p_year AND x.month=p_month AND x.position_id=p_position_id;
 RETURN jsonb_build_object('path', k);
END $$;

REVOKE ALL ON FUNCTION public.scl375_photo_begin(text,text),public.scl375_photo_commit(text,text,text),public.scl375_photo_path(text,int,int,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.scl375_photo_begin(text,text),public.scl375_photo_commit(text,text,text),public.scl375_photo_path(text,int,int,text) TO service_role;

-- Κλειστός χώρος αρχείων: καμία πολιτική πρόσβασης, άρα μόνο το πρόγραμμα των φωτογραφιών διαβάζει και γράφει.
DO $do$ BEGIN
 IF to_regclass('storage.buckets') IS NOT NULL THEN
  INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES ('scl375-setup','scl375-setup',false,614400,ARRAY['image/jpeg']) ON CONFLICT (id) DO NOTHING;
 END IF;
END $do$;
COMMIT;
