-- scl350: κατόψεις φαρμακείων (builder κάτοψης, φάση 1). Μοντέλο: spacecolab.floorplan του Design mockup, μονάδα εκατοστά.
-- Χώρος → ανοίγματα → έπιπλα → θέσεις. Κάθε αποθήκευση = νέα έκδοση με ημερομηνία· οι παλιές μένουν ως 'old'.
-- Φάση 1: γράφουν ΜΟΝΟ τα Κεντρικά. Το φαρμακείο διαβάζει μόνο την ενεργή έκδοση (με το token του).
-- Αποκλειστικά ΠΡΟΣΘΗΚΕΣ: νέοι πίνακες και νέες συναρτήσεις. Καμία υπάρχουσα συνάρτηση, πίνακας, trigger ή γραμμή δεν αλλάζει.
-- ΡΙΣΕΤ: οι πίνακες scl_private.fp_* ΔΕΝ σβήνονται στο ρίσετ των δεδομένων των φαρμακείων. Δένονται με το μητρώο
-- με ON DELETE RESTRICT, ώστε ένα σβήσιμο γραμμής μητρώου να αποτυγχάνει αντί να σβήσει σιωπηλά κάτοψη.
-- Η μόνη υπάρχουσα διαγραφή μητρώου (scl290_hq_activate, ένωση παλιού φαρμακείου χωρίς κωδικό) δεν επηρεάζεται:
-- σε τέτοια γραμμή δεν αποθηκεύεται κάτοψη.
-- ΕΦΑΡΜΟΣΤΗΚΕ 19/11/2026 (~10:40) μετά από ρητό «ναι». Μετά την εφαρμογή: 0 από 111 υπάρχοντες ορισμούς συναρτήσεων άλλαξαν,
-- μητρώο και snapshots ανέπαφα, οι 9 νέοι ορισμοί ίδιοι με αυτούς των τοπικών τεστ (62/62).
-- Rollback: supabase/rollback/20261119100000_scl350_floorplans_rollback.sql

-- 0. Αντίγραφο ασφαλείας ορισμών συναρτήσεων πριν από την αλλαγή.
CREATE TABLE scl_private.backup_v350_functions AS
 SELECT n.nspname::text AS schema_name, p.proname::text AS fn, pg_get_function_identity_arguments(p.oid) AS args,
        pg_get_functiondef(p.oid) AS definition, now() AS taken_at
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','scl_private') AND p.prokind='f';
ALTER TABLE scl_private.backup_v350_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v350_functions FROM PUBLIC,anon,authenticated;

-- 1. Πίνακες.
-- Έκδοση κάτοψης. room_pts = [[x,y],...] σε εκ. src: e = εκτίμηση (κατά προσέγγιση), d = δήλωση, m = μέτρηση.
CREATE TABLE scl_private.fp_versions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 registry_id uuid NOT NULL REFERENCES public.scl290_registry(id) ON DELETE RESTRICT,
 version_no integer NOT NULL CHECK(version_no>=1),
 status text NOT NULL CHECK(status IN ('draft','active','old')),
 edited_by text NOT NULL CHECK(edited_by IN ('hq','pharmacy')),
 based_on uuid REFERENCES scl_private.fp_versions(id),
 room_pts jsonb NOT NULL CHECK(jsonb_typeof(room_pts)='array' AND jsonb_array_length(room_pts) BETWEEN 3 AND 64),
 ceil_cm numeric(6,1) NOT NULL CHECK(ceil_cm BETWEEN 150 AND 1000),
 room_src text NOT NULL DEFAULT 'e' CHECK(room_src IN ('e','d','m')),
 eye_height_cm numeric(5,1) NOT NULL DEFAULT 160 CHECK(eye_height_cm BETWEEN 100 AND 220),
 note text CHECK(note IS NULL OR length(note)<=500),
 params jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(params)='object'),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(registry_id,version_no)
);
CREATE UNIQUE INDEX fp_versions_one_active ON scl_private.fp_versions(registry_id) WHERE status='active';

-- Ανοίγματα: ent = είσοδος, shop = βιτρίνα, win = παράθυρο, staff = πόρτα προσωπικού. wall_idx = τοίχος (ακμή περιγράμματος).
CREATE TABLE scl_private.fp_openings(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 version_id uuid NOT NULL REFERENCES scl_private.fp_versions(id) ON DELETE CASCADE,
 code text NOT NULL CHECK(code ~ '^[A-Za-z0-9_.-]{1,40}$'),
 kind text NOT NULL CHECK(kind IN ('ent','shop','win','staff')),
 wall_idx integer NOT NULL CHECK(wall_idx BETWEEN 0 AND 63),
 at_cm numeric(7,1) NOT NULL CHECK(at_cm BETWEEN 0 AND 10000),
 w_cm numeric(6,1) NOT NULL CHECK(w_cm BETWEEN 10 AND 3000),
 h_cm numeric(6,1) CHECK(h_cm IS NULL OR h_cm BETWEEN 10 AND 1000),
 sill_cm numeric(6,1) CHECK(sill_cm IS NULL OR sill_cm BETWEEN 0 AND 500),
 door_type text CHECK(door_type IS NULL OR length(door_type)<=30),
 swing text CHECK(swing IS NULL OR length(swing)<=30),
 src text NOT NULL DEFAULT 'e' CHECK(src IN ('e','d','m')),
 facade_no integer,                                    -- κρατημένο για το δέσιμο με Βιτρίνα (όχι στη φάση 1)
 params jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(params)='object'),
 UNIQUE(version_id,code)
);

-- Έπιπλα: counter (πάγκος I/Γ/Π), rack (ραφιέρα με στήλες), gondola, fridge, column. x,y = κέντρο, rot σε μοίρες.
-- params: ό,τι κρατά ο builder και δεν είναι στήλη (σχήμα πάγκου, τέρματα, πλάτη ραφιέρας κ.λπ.).
CREATE TABLE scl_private.fp_items(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 version_id uuid NOT NULL REFERENCES scl_private.fp_versions(id) ON DELETE CASCADE,
 code text NOT NULL CHECK(code ~ '^[A-Za-z0-9_.-]{1,40}$'),
 kind text NOT NULL CHECK(kind IN ('counter','rack','gondola','fridge','column')),
 lib_key text CHECK(lib_key IS NULL OR length(lib_key)<=40),
 name text CHECK(name IS NULL OR length(name)<=80),
 x_cm numeric(7,1) NOT NULL CHECK(x_cm BETWEEN -1000 AND 10000),
 y_cm numeric(7,1) NOT NULL CHECK(y_cm BETWEEN -1000 AND 10000),
 w_cm numeric(6,1) NOT NULL CHECK(w_cm BETWEEN 5 AND 3000),
 d_cm numeric(6,1) NOT NULL CHECK(d_cm BETWEEN 5 AND 3000),
 h_cm numeric(6,1) CHECK(h_cm IS NULL OR h_cm BETWEEN 1 AND 1000),
 rot_deg numeric(5,1) NOT NULL DEFAULT 0 CHECK(rot_deg>-360 AND rot_deg<360),
 bays integer CHECK(bays IS NULL OR bays BETWEEN 1 AND 60),
 bay_w_cm numeric(5,1) CHECK(bay_w_cm IS NULL OR bay_w_cm BETWEEN 10 AND 300),
 faces integer CHECK(faces IS NULL OR faces IN (1,2)),
 detail text NOT NULL DEFAULT 'rough' CHECK(detail IN ('rough','detailed')),
 locked boolean NOT NULL DEFAULT false,
 src text NOT NULL DEFAULT 'e' CHECK(src IN ('e','d','m')),
 finish_id uuid,                                       -- κρατημένο (υλικά/φινιρίσματα, όχι στη φάση 1)
 params jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(params)='object'),
 UNIQUE(version_id,code)
);

-- Θέσεις: code = σταθερό id της θέσης στην εγκατάσταση (hq, base-1, promo-1 ...).
-- mode: stand-counter (host πάγκος, edge F/B/L/R, offset) · stand-floor (σημείο, στροφή) · screen-only (host κολώνα/γόνδολα/ραφιέρα,
-- κάτω άκρη οθόνης) · special. params: πρότυπο σταντ (p1/p2/e1/e2), αλλαγές προτύπου, αριθμός ραφιών, σημείωση «άλλη λύση».
CREATE TABLE scl_private.fp_positions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 version_id uuid NOT NULL REFERENCES scl_private.fp_versions(id) ON DELETE CASCADE,
 code text NOT NULL CHECK(code ~ '^[A-Za-z0-9_.-]{1,40}$'),
 host_code text CHECK(host_code IS NULL OR host_code ~ '^[A-Za-z0-9_.-]{1,40}$'),
 mode text NOT NULL CHECK(mode IN ('stand-counter','stand-floor','screen-only','special')),
 edge text CHECK(edge IS NULL OR edge IN ('F','B','L','R')),
 offset_cm numeric(7,1) CHECK(offset_cm IS NULL OR offset_cm BETWEEN -1000 AND 10000),
 bay integer CHECK(bay IS NULL OR bay BETWEEN 0 AND 60),
 rot_deg numeric(5,1) CHECK(rot_deg IS NULL OR (rot_deg>-360 AND rot_deg<360)),
 floor_x numeric(7,1) CHECK(floor_x IS NULL OR floor_x BETWEEN -1000 AND 10000),
 floor_y numeric(7,1) CHECK(floor_y IS NULL OR floor_y BETWEEN -1000 AND 10000),
 screen_bottom_cm numeric(6,1) CHECK(screen_bottom_cm IS NULL OR screen_bottom_cm BETWEEN 0 AND 400),
 src text NOT NULL DEFAULT 'e' CHECK(src IN ('e','d','m')),
 params jsonb NOT NULL DEFAULT '{}' CHECK(jsonb_typeof(params)='object'),
 UNIQUE(version_id,code)
);

ALTER TABLE scl_private.fp_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.fp_openings ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.fp_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.fp_positions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.fp_versions,scl_private.fp_openings,scl_private.fp_items,scl_private.fp_positions FROM PUBLIC,anon,authenticated;

-- 2. Εσωτερικές συναρτήσεις.
-- Αριθμός από jsonb (ή NULL). Μη αριθμητική τιμή => σφάλμα με το όνομα του πεδίου.
CREATE FUNCTION scl_private.fp_num(p jsonb,p_key text,p_where text) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
BEGIN
 IF p IS NULL OR NOT (p ? p_key) OR jsonb_typeof(p->p_key)='null' THEN RETURN NULL; END IF;
 IF jsonb_typeof(p->p_key)<>'number' THEN RAISE EXCEPTION 'FP_INVALID: % — το πεδίο % πρέπει να είναι αριθμός',p_where,p_key; END IF;
 RETURN (p->>p_key)::numeric;
END $$;

-- Ολόκληρη η κάτοψη μιας έκδοσης, στη μορφή του builder (spacecolab.floorplan). Οι params ξαναμπαίνουν στο ίδιο αντικείμενο.
CREATE FUNCTION scl_private.fp_plan(p_vid uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object(
  'schema','spacecolab.floorplan','unit','cm',
  'version',jsonb_build_object('id',v.id,'no',v.version_no,'status',v.status,'edited_by',v.edited_by,'based_on',v.based_on,
     'saved_at',v.created_at,'note',v.note),
  'room',v.params||jsonb_build_object('pts',v.room_pts,'ceil',v.ceil_cm,'src',v.room_src,'eye',v.eye_height_cm),
  'openings',coalesce((SELECT jsonb_agg(o.params||jsonb_strip_nulls(jsonb_build_object('id',o.code,'kind',o.kind,'wall',o.wall_idx,'at',o.at_cm,
     'w',o.w_cm,'h',o.h_cm,'sill',o.sill_cm,'type',o.door_type,'swing',o.swing,'src',o.src)) ORDER BY o.code)
     FROM scl_private.fp_openings o WHERE o.version_id=v.id),'[]'::jsonb),
  'items',coalesce((SELECT jsonb_agg(i.params||jsonb_strip_nulls(jsonb_build_object('id',i.code,'kind',i.kind,'lib',i.lib_key,'name',i.name,
     'x',i.x_cm,'y',i.y_cm,'w',i.w_cm,'d',i.d_cm,'h',i.h_cm,'r',i.rot_deg,'bays',i.bays,'bw',i.bay_w_cm,'faces',i.faces,
     'detail',i.detail,'locked',i.locked,'src',i.src)) ORDER BY i.code)
     FROM scl_private.fp_items i WHERE i.version_id=v.id),'[]'::jsonb),
  'positions',coalesce((SELECT jsonb_agg(p.params||jsonb_strip_nulls(jsonb_build_object('id',p.code,'host',p.host_code,'mode',p.mode,'edge',p.edge,
     'ox',p.offset_cm,'bay',p.bay,'rot',p.rot_deg,'fcx',p.floor_x,'fcy',p.floor_y,'mh',p.screen_bottom_cm,'src',p.src)) ORDER BY p.code)
     FROM scl_private.fp_positions p WHERE p.version_id=v.id),'[]'::jsonb))
 FROM scl_private.fp_versions v WHERE v.id=p_vid
$$;

-- Λίστα εκδόσεων ενός φαρμακείου (νεότερη πρώτη).
CREATE FUNCTION scl_private.fp_versions_list(p_rid uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',v.id,'no',v.version_no,'status',v.status,'edited_by',v.edited_by,'saved_at',v.created_at,'note',v.note,
   'items',(SELECT count(*) FROM scl_private.fp_items i WHERE i.version_id=v.id),
   'positions',(SELECT count(*) FROM scl_private.fp_positions p WHERE p.version_id=v.id)) ORDER BY v.version_no DESC),'[]'::jsonb)
 FROM scl_private.fp_versions v WHERE v.registry_id=p_rid
$$;

-- Αποθήκευση: ελέγχει το σχέδιο και γράφει ΝΕΑ ενεργή έκδοση. Η προηγούμενη ενεργή γίνεται 'old'. Δεν σβήνεται τίποτα.
-- p_expected = αριθμός της ενεργής έκδοσης που άνοιξε ο χρήστης (0 αν δεν υπήρχε). Αν άλλαξε στο μεταξύ => FP_CHANGED.
CREATE FUNCTION scl_private.fp_save(p_rid uuid,p_expected integer,p_plan jsonb,p_note text,p_by text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE cur scl_private.fp_versions;nv integer;vid uuid;room jsonb;pt jsonb;e jsonb;i integer;
 known_o text[]:=ARRAY['id','kind','wall','at','w','h','sill','type','swing','src','facade_no'];
 known_i text[]:=ARRAY['id','kind','lib','name','x','y','w','d','h','r','bays','bw','faces','detail','locked','src'];
 known_p text[]:=ARRAY['id','host','mode','edge','ox','bay','rot','fcx','fcy','mh','src'];
 known_r text[]:=ARRAY['pts','ceil','src','eye'];
 n_walls integer;codes text[];
BEGIN
 IF p_by IS NULL OR p_by NOT IN ('hq','pharmacy') THEN RAISE EXCEPTION 'FP_INVALID: μη έγκυρος χρήστης'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.scl290_registry WHERE id=p_rid) THEN RAISE EXCEPTION 'FP_INVALID: άγνωστο φαρμακείο'; END IF;
 -- Παλιό φαρμακείο χωρίς κωδικό τιμολόγησης: η scl290_hq_activate σβήνει αυτή τη γραμμή όταν το αντιστοιχίσει.
 -- Η κάτοψη μπαίνει μόνο μετά την αντιστοίχιση, ώστε η ένωση να μη μπλοκάρει ποτέ.
 IF EXISTS(SELECT 1 FROM public.scl290_registry WHERE id=p_rid AND legacy AND billing_code IS NULL) THEN
  RAISE EXCEPTION 'FP_INVALID: Αντιστοιχίστε πρώτα το φαρμακείο με τον κωδικό τιμολόγησης'; END IF;
 IF p_plan IS NULL OR jsonb_typeof(p_plan)<>'object' THEN RAISE EXCEPTION 'FP_INVALID: κενό σχέδιο'; END IF;
 IF octet_length(p_plan::text)>300000 THEN RAISE EXCEPTION 'FP_INVALID: το σχέδιο είναι πολύ μεγάλο'; END IF;
 IF coalesce(p_plan->>'schema','')<>'spacecolab.floorplan' OR coalesce(p_plan->>'unit','')<>'cm' THEN
  RAISE EXCEPTION 'FP_INVALID: άγνωστη μορφή σχεδίου'; END IF;
 room:=p_plan->'room';
 IF room IS NULL OR jsonb_typeof(room)<>'object' OR jsonb_typeof(room->'pts')<>'array' THEN RAISE EXCEPTION 'FP_INVALID: λείπει το περίγραμμα του χώρου'; END IF;
 n_walls:=jsonb_array_length(room->'pts');
 IF n_walls NOT BETWEEN 3 AND 64 THEN RAISE EXCEPTION 'FP_INVALID: το περίγραμμα θέλει 3 έως 64 γωνίες'; END IF;
 FOR pt IN SELECT value FROM jsonb_array_elements(room->'pts') LOOP
  IF jsonb_typeof(pt)<>'array' OR jsonb_array_length(pt)<>2 OR jsonb_typeof(pt->0)<>'number' OR jsonb_typeof(pt->1)<>'number'
     OR (pt->>0)::numeric NOT BETWEEN -1000 AND 10000 OR (pt->>1)::numeric NOT BETWEEN -1000 AND 10000 THEN
   RAISE EXCEPTION 'FP_INVALID: μη έγκυρη γωνία χώρου'; END IF;
 END LOOP;
 FOREACH e IN ARRAY ARRAY[p_plan->'openings',p_plan->'items',p_plan->'positions'] LOOP
  IF e IS NOT NULL AND jsonb_typeof(e)<>'array' THEN RAISE EXCEPTION 'FP_INVALID: τα ανοίγματα, έπιπλα και θέσεις είναι λίστες'; END IF;
 END LOOP;
 IF jsonb_array_length(coalesce(p_plan->'openings','[]'))>40 THEN RAISE EXCEPTION 'FP_INVALID: έως 40 ανοίγματα'; END IF;
 IF jsonb_array_length(coalesce(p_plan->'items','[]'))>300 THEN RAISE EXCEPTION 'FP_INVALID: έως 300 έπιπλα'; END IF;
 IF jsonb_array_length(coalesce(p_plan->'positions','[]'))>60 THEN RAISE EXCEPTION 'FP_INVALID: έως 60 θέσεις'; END IF;

 PERFORM pg_advisory_xact_lock(hashtext('scl350_fp:'||p_rid::text));
 SELECT * INTO cur FROM scl_private.fp_versions WHERE registry_id=p_rid AND status='active';
 IF coalesce(cur.version_no,0) IS DISTINCT FROM coalesce(p_expected,0) THEN
  RAISE EXCEPTION 'FP_CHANGED: Η κάτοψη άλλαξε στο μεταξύ (έκδοση %). Ανοίξτε την ξανά.',coalesce(cur.version_no,0); END IF;
 SELECT coalesce(max(version_no),0)+1 INTO nv FROM scl_private.fp_versions WHERE registry_id=p_rid;
 UPDATE scl_private.fp_versions SET status='old' WHERE registry_id=p_rid AND status='active';

 INSERT INTO scl_private.fp_versions(registry_id,version_no,status,edited_by,based_on,room_pts,ceil_cm,room_src,eye_height_cm,note,params)
 VALUES(p_rid,nv,'active',p_by,cur.id,room->'pts',
  coalesce(scl_private.fp_num(room,'ceil','χώρος'),300),coalesce(room->>'src','e'),coalesce(scl_private.fp_num(room,'eye','χώρος'),160),
  nullif(btrim(coalesce(p_note,'')),''),room-known_r)
 RETURNING id INTO vid;

 i:=0;
 FOR e IN SELECT value FROM jsonb_array_elements(coalesce(p_plan->'openings','[]')) LOOP
  i:=i+1;
  IF jsonb_typeof(e)<>'object' THEN RAISE EXCEPTION 'FP_INVALID: άνοιγμα %',i; END IF;
  IF scl_private.fp_num(e,'wall','άνοιγμα '||i)>=n_walls THEN RAISE EXCEPTION 'FP_INVALID: το άνοιγμα % δείχνει τοίχο που δεν υπάρχει',coalesce(e->>'id',i::text); END IF;
  INSERT INTO scl_private.fp_openings(version_id,code,kind,wall_idx,at_cm,w_cm,h_cm,sill_cm,door_type,swing,src,facade_no,params)
  VALUES(vid,e->>'id',e->>'kind',scl_private.fp_num(e,'wall','άνοιγμα '||i)::integer,scl_private.fp_num(e,'at','άνοιγμα '||i),
   scl_private.fp_num(e,'w','άνοιγμα '||i),scl_private.fp_num(e,'h','άνοιγμα '||i),scl_private.fp_num(e,'sill','άνοιγμα '||i),
   e->>'type',e->>'swing',coalesce(e->>'src','e'),scl_private.fp_num(e,'facade_no','άνοιγμα '||i)::integer,e-known_o);
 END LOOP;

 i:=0;
 FOR e IN SELECT value FROM jsonb_array_elements(coalesce(p_plan->'items','[]')) LOOP
  i:=i+1;
  IF jsonb_typeof(e)<>'object' THEN RAISE EXCEPTION 'FP_INVALID: έπιπλο %',i; END IF;
  INSERT INTO scl_private.fp_items(version_id,code,kind,lib_key,name,x_cm,y_cm,w_cm,d_cm,h_cm,rot_deg,bays,bay_w_cm,faces,detail,locked,src,params)
  VALUES(vid,e->>'id',e->>'kind',e->>'lib',e->>'name',scl_private.fp_num(e,'x','έπιπλο '||i),scl_private.fp_num(e,'y','έπιπλο '||i),
   scl_private.fp_num(e,'w','έπιπλο '||i),scl_private.fp_num(e,'d','έπιπλο '||i),scl_private.fp_num(e,'h','έπιπλο '||i),
   coalesce(scl_private.fp_num(e,'r','έπιπλο '||i),0),scl_private.fp_num(e,'bays','έπιπλο '||i)::integer,scl_private.fp_num(e,'bw','έπιπλο '||i),
   scl_private.fp_num(e,'faces','έπιπλο '||i)::integer,coalesce(e->>'detail','rough'),coalesce((e->>'locked')::boolean,false),
   coalesce(e->>'src','e'),e-known_i);
 END LOOP;
 SELECT coalesce(array_agg(code),'{}') INTO codes FROM scl_private.fp_items WHERE version_id=vid;

 i:=0;
 FOR e IN SELECT value FROM jsonb_array_elements(coalesce(p_plan->'positions','[]')) LOOP
  i:=i+1;
  IF jsonb_typeof(e)<>'object' THEN RAISE EXCEPTION 'FP_INVALID: θέση %',i; END IF;
  IF e->>'mode' IN ('stand-counter','screen-only') AND NOT (coalesce(e->>'host','') = ANY(codes)) THEN
   RAISE EXCEPTION 'FP_INVALID: η θέση % δεν πατάει σε έπιπλο του σχεδίου',coalesce(e->>'id',i::text); END IF;
  IF e ? 'host' AND jsonb_typeof(e->'host')='string' AND NOT ((e->>'host') = ANY(codes)) THEN
   RAISE EXCEPTION 'FP_INVALID: η θέση % δείχνει έπιπλο που δεν υπάρχει',coalesce(e->>'id',i::text); END IF;
  INSERT INTO scl_private.fp_positions(version_id,code,host_code,mode,edge,offset_cm,bay,rot_deg,floor_x,floor_y,screen_bottom_cm,src,params)
  VALUES(vid,e->>'id',e->>'host',e->>'mode',e->>'edge',scl_private.fp_num(e,'ox','θέση '||i),scl_private.fp_num(e,'bay','θέση '||i)::integer,
   scl_private.fp_num(e,'rot','θέση '||i),scl_private.fp_num(e,'fcx','θέση '||i),scl_private.fp_num(e,'fcy','θέση '||i),
   scl_private.fp_num(e,'mh','θέση '||i),coalesce(e->>'src','e'),e-known_p);
 END LOOP;

 RETURN jsonb_build_object('id',vid,'no',nv,'saved_at',(SELECT created_at FROM scl_private.fp_versions WHERE id=vid));
EXCEPTION
 WHEN check_violation OR not_null_violation OR unique_violation OR invalid_text_representation THEN
  RAISE EXCEPTION 'FP_INVALID: %',SQLERRM;
END $$;

REVOKE ALL ON FUNCTION scl_private.fp_num(jsonb,text,text),scl_private.fp_plan(uuid),scl_private.fp_versions_list(uuid),
 scl_private.fp_save(uuid,integer,jsonb,text,text) FROM PUBLIC,anon,authenticated;

-- 3. Δημόσιες συναρτήσεις (RPC).
-- Κεντρικά: ενεργή κάτοψη (ή συγκεκριμένη έκδοση) + λίστα εκδόσεων. plan = null αν δεν υπάρχει σχέδιο.
CREATE FUNCTION public.scl350_hq_fp_get(p_hq_key text,p_registry_id uuid,p_version_no integer DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE vid uuid;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF NOT EXISTS(SELECT 1 FROM public.scl290_registry WHERE id=p_registry_id) THEN RAISE EXCEPTION 'Άγνωστο φαρμακείο'; END IF;
 IF p_version_no IS NULL THEN
  SELECT id INTO vid FROM scl_private.fp_versions WHERE registry_id=p_registry_id AND status='active';
 ELSE
  SELECT id INTO vid FROM scl_private.fp_versions WHERE registry_id=p_registry_id AND version_no=p_version_no;
  IF vid IS NULL THEN RAISE EXCEPTION 'Δεν υπάρχει η έκδοση %',p_version_no; END IF;
 END IF;
 RETURN jsonb_build_object('registry_id',p_registry_id,
  'active_no',(SELECT version_no FROM scl_private.fp_versions WHERE registry_id=p_registry_id AND status='active'),
  'plan',CASE WHEN vid IS NULL THEN NULL ELSE scl_private.fp_plan(vid) END,
  'versions',scl_private.fp_versions_list(p_registry_id));
END $$;

-- Κεντρικά: αποθήκευση ως νέα έκδοση με ημερομηνία.
CREATE FUNCTION public.scl350_hq_fp_save(p_hq_key text,p_registry_id uuid,p_expected_no integer,p_plan jsonb,p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN scl_private.fp_save(p_registry_id,p_expected_no,p_plan,p_note,'hq');
END $$;

-- Κεντρικά: ποια φαρμακεία έχουν κάτοψη (για σήμανση στη λίστα και για «Εξαγωγή επιλεγμένων»).
CREATE FUNCTION public.scl350_hq_fp_overview(p_hq_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('registry_id',v.registry_id,'no',v.version_no,'saved_at',v.created_at,
   'items',(SELECT count(*) FROM scl_private.fp_items i WHERE i.version_id=v.id),
   'positions',(SELECT count(*) FROM scl_private.fp_positions p WHERE p.version_id=v.id),
   'estimated',(v.room_src='e' OR EXISTS(SELECT 1 FROM scl_private.fp_items i WHERE i.version_id=v.id AND i.src='e')))
   ORDER BY v.registry_id) FROM scl_private.fp_versions v WHERE v.status='active'),'[]'::jsonb);
END $$;

-- Κεντρικά: ενεργές κατόψεις πολλών φαρμακείων μαζί (εκτύπωση «Εξαγωγή επιλεγμένων»). Έως 120.
CREATE FUNCTION public.scl350_hq_fp_get_many(p_hq_key text,p_registry_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF coalesce(array_length(p_registry_ids,1),0)>120 THEN RAISE EXCEPTION 'Έως 120 φαρμακεία ανά εξαγωγή'; END IF;
 RETURN coalesce((SELECT jsonb_object_agg(v.registry_id::text,scl_private.fp_plan(v.id))
   FROM scl_private.fp_versions v WHERE v.status='active' AND v.registry_id=ANY(coalesce(p_registry_ids,'{}'))),'{}'::jsonb);
END $$;

-- Φαρμακείο: μόνο ανάγνωση της ενεργής κάτοψης. plan = null αν δεν υπάρχει. Χωρίς ιστορικό εκδόσεων και σημειώσεις.
CREATE FUNCTION public.scl350_fp_get(p_token text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid;rid uuid;vid uuid;pl jsonb;
BEGIN
 pid:=public.scl290_token_id(p_token);
 SELECT id INTO rid FROM public.scl290_registry WHERE pharmacy_id=pid;
 SELECT id INTO vid FROM scl_private.fp_versions WHERE registry_id=rid AND status='active';
 IF vid IS NULL THEN RETURN jsonb_build_object('plan',NULL); END IF;
 pl:=scl_private.fp_plan(vid);
 pl:=jsonb_set(pl,'{version}',(pl->'version')-'note'-'based_on'-'edited_by');
 RETURN jsonb_build_object('plan',pl);
END $$;

REVOKE ALL ON FUNCTION public.scl350_hq_fp_get(text,uuid,integer),public.scl350_hq_fp_save(text,uuid,integer,jsonb,text),
 public.scl350_hq_fp_overview(text),public.scl350_hq_fp_get_many(text,uuid[]),public.scl350_fp_get(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl350_hq_fp_get(text,uuid,integer),public.scl350_hq_fp_save(text,uuid,integer,jsonb,text),
 public.scl350_hq_fp_overview(text),public.scl350_hq_fp_get_many(text,uuid[]),public.scl350_fp_get(text) TO anon,authenticated;
