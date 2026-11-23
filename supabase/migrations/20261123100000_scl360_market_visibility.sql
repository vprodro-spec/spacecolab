-- scl360: SpaceCoLLab Market, κομμάτι Κ1 «Ορατότητα».
-- Το φαρμακείο αποφασίζει ποιες θέσεις πάγκου βλέπουν οι εταιρίες. Το Market διαβάζει πραγματικά φαρμακεία, μόνο για ανάγνωση.
-- Αποκλειστικά ΠΡΟΣΘΗΚΕΣ: νέοι πίνακες scl_private.mk_* και νέες συναρτήσεις scl360_* / scl_private.mk_*.
-- Καμία υπάρχουσα συνάρτηση, πίνακας, trigger ή γραμμή δεν αλλάζει. Δεν γράφει ποτέ σε πρόγραμμα, εγκατάσταση ή χρεώσεις.
-- Προς το Market ΔΕΝ φεύγει ποτέ: τζίρος, αποδείξεις, επισκέψεις ως αριθμός, πωλήσεις, μάρκα/προμηθευτής συμφωνίας, βασικό πρόγραμμα, χρεώσεις.
-- ΡΙΣΕΤ: οι πίνακες mk_* δένονται με το μητρώο με ON DELETE RESTRICT (όπως οι fp_*).
-- ΕΦΑΡΜΟΣΤΗΚΕ 23/11/2026 (~10:20) μετά από ρητό «ναι». Μετά την εφαρμογή: 0 από 120 υπάρχοντες ορισμούς συναρτήσεων άλλαξαν,
-- μητρώο, προγράμματα, εγκαταστάσεις, χρεώσεις και τιμοκατάλογος ίδια· οι 16 νέοι ορισμοί ίδιοι με αυτούς των τοπικών δοκιμών (58/58).
-- Rollback: supabase/rollback/20261123100000_scl360_market_visibility_rollback.sql

-- 0. Αντίγραφο ασφαλείας ορισμών συναρτήσεων πριν από την αλλαγή.
CREATE TABLE scl_private.backup_v360_functions AS
 SELECT n.nspname::text AS schema_name, p.proname::text AS fn, pg_get_function_identity_arguments(p.oid) AS args,
        pg_get_functiondef(p.oid) AS definition, now() AS taken_at
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','scl_private') AND p.prokind='f';
ALTER TABLE scl_private.backup_v360_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v360_functions FROM PUBLIC,anon,authenticated;

-- 1. Πίνακες.
-- Ανά φαρμακείο: αποδοχή όρων Market (μία φορά) και σημείο στον χάρτη.
CREATE TABLE scl_private.mk_pharmacy(
 registry_id uuid PRIMARY KEY REFERENCES public.scl290_registry(id) ON DELETE RESTRICT,
 terms_accepted_at timestamptz,
 lat numeric(9,6) CHECK(lat BETWEEN 34 AND 42),
 lng numeric(9,6) CHECK(lng BETWEEN 19 AND 30),
 geo_source text CHECK(geo_source IS NULL OR length(geo_source)<=120),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((lat IS NULL)=(lng IS NULL))
);
-- Ανά θέση πάγκου: «Φαίνεται στις εταιρίες στο SpaceCoLLab Market» και «Δέχομαι ομαδικές προτάσεις Pharmaplus». Κλειστά από προεπιλογή.
CREATE TABLE scl_private.mk_position_settings(
 registry_id uuid NOT NULL REFERENCES public.scl290_registry(id) ON DELETE RESTRICT,
 position_id text NOT NULL CHECK(position_id ~ '^base-[0-9]{1,2}$'),
 visible boolean NOT NULL DEFAULT false,
 group_offers boolean NOT NULL DEFAULT false,
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(registry_id,position_id)
);
-- Ιστορικό αλλαγών των διακοπτών και της αποδοχής όρων.
CREATE TABLE scl_private.mk_settings_history(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 registry_id uuid NOT NULL REFERENCES public.scl290_registry(id) ON DELETE RESTRICT,
 position_id text,
 event text NOT NULL CHECK(event IN ('settings','terms')),
 visible boolean, group_offers boolean,
 changed_at timestamptz NOT NULL DEFAULT now()
);
-- Πρόσβαση στο Market με προσωπικό σύνδεσμο. Στο Κ1 μόνο δοκιμαστικός ('test'). Οι εταιρίες έρχονται στο Κ2.
CREATE TABLE scl_private.mk_access(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 token uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
 label text NOT NULL CHECK(length(label) BETWEEN 1 AND 80),
 kind text NOT NULL CHECK(kind IN ('test')),
 created_at timestamptz NOT NULL DEFAULT now(),
 revoked_at timestamptz
);
ALTER TABLE scl_private.mk_pharmacy ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_position_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_settings_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_access ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.mk_pharmacy,scl_private.mk_position_settings,scl_private.mk_settings_history,scl_private.mk_access FROM PUBLIC,anon,authenticated;

-- 2. Βοηθητικές (ιδιωτικές).
-- Αριθμός από jsonb όπως το Number() του εργαλείου· NULL αν δεν είναι αριθμός.
CREATE FUNCTION scl_private.mk_num(v jsonb) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN v IS NULL THEN NULL
  WHEN jsonb_typeof(v)='number' THEN (v#>>'{}')::numeric
  WHEN jsonb_typeof(v)='string' AND (v#>>'{}') ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' THEN btrim(v#>>'{}')::numeric
  END
$$;

-- Τιμή συμφωνίας ανά μήνα: ΙΔΙΟΣ τύπος με το εργαλείο (computeBasePrice × positionFactor, Math.round, τουλάχιστον 100 €).
CREATE FUNCTION scl_private.mk_price(p_turnover numeric,p_counters numeric) RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT floor(greatest(100::double precision,
   greatest(100::double precision,150*power(greatest(coalesce(p_turnover,0),0)::double precision/1000000,0.7::double precision))
   * (CASE WHEN p_counters IS NULL THEN 0.85
           WHEN greatest(1,p_counters-1)<=1 THEN 1.10
           WHEN greatest(1,p_counters-1)=2 THEN 1
           WHEN greatest(1,p_counters-1)=3 THEN 0.95
           WHEN greatest(1,p_counters-1)=4 THEN 0.90
           ELSE 0.85 END)::double precision)+0.5)::integer
$$;

-- Εύρος πελατών τον μήνα (1–5). Όρια: 2.000 · 4.000 · 6.000 · 9.000. NULL = χωρίς στοιχεία κίνησης.
CREATE FUNCTION scl_private.mk_band(p_visits_monthly numeric) RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN p_visits_monthly IS NULL OR p_visits_monthly<=0 THEN NULL
  WHEN p_visits_monthly<2000 THEN 1 WHEN p_visits_monthly<4000 THEN 2
  WHEN p_visits_monthly<6000 THEN 3 WHEN p_visits_monthly<9000 THEN 4 ELSE 5 END
$$;

-- Ο μήνας m (0–11) του έτους y καλύπτεται από εγγραφή με startMonth/duration (όπως το monthsForNegotiation του εργαλείου).
CREATE FUNCTION scl_private.mk_covers(rec jsonb,m integer) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT m>=greatest(0,coalesce(scl_private.mk_num(rec->'startMonth'),0))
    AND m< least(12,greatest(0,coalesce(scl_private.mk_num(rec->'startMonth'),0))
                    +greatest(1,coalesce(nullif(scl_private.mk_num(rec->'duration'),0),1)))
$$;

-- Ελεύθερος μήνας θέσης: κλειδωμένο αρχικό πρόγραμμα, θέση σε λειτουργία, χωρίς συμφωνία, προσυμφωνία ή χορηγία ραφιών.
CREATE FUNCTION scl_private.mk_month_free(card jsonb,pos jsonb,y integer,m integer) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT coalesce(card->>'initialPlanLocked','')='true'
  AND scl_private.position_active(coalesce(pos,'{}'::jsonb)||jsonb_build_object('stopsOn',card->'stopsOn'),y,m)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(card->'confirmedDeals')='array' THEN card->'confirmedDeals' ELSE '[]'::jsonb END) d
                 WHERE coalesce(d->>'confirmed','')='true' AND scl_private.mk_covers(d,m))
  AND NOT (coalesce(card#>>'{negotiation,confirmed}','')='true'
           AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(card->'confirmedDeals')='array' THEN card->'confirmedDeals' ELSE '[]'::jsonb END) d)
           AND scl_private.mk_covers(card->'negotiation',m))
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(card->'preagreements')='array' THEN card->'preagreements' ELSE '[]'::jsonb END) d
                 WHERE jsonb_typeof(d)='object' AND coalesce(d->>'confirmed','')<>'true' AND scl_private.mk_covers(d,m))
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(card->'sponsoredShelves')='array' THEN card->'sponsoredShelves' ELSE '[]'::jsonb END) d
                 WHERE jsonb_typeof(d)='object' AND coalesce(d->>'status','')<>'cancelled' AND scl_private.mk_num(d->'month')=m)
$$;

-- Κατάσταση και διαθεσιμότητα μιας θέσης πάγκου, για το τρέχον και το επόμενο έτος.
-- reason: turnover = δεν έχει τζίρο · initial = δεν έχει κλειδώσει το αρχικό πρόγραμμα · inactive = η θέση δεν λειτουργεί.
-- years: [{year, price, free:[μήνες 0–11], until:{μήνας: 'YYYY-MM-DD'}}]. Μήνας ζητιέται έως τις 8 του προηγούμενου.
CREATE FUNCTION scl_private.mk_position_view(p_rid uuid,p_pos jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid;d date:=scl_private.today();y0 integer;y integer;st jsonb;card jsonb;tv numeric;
 has_turnover boolean:=false;has_locked boolean:=false;has_active boolean:=false;years jsonb:='[]'::jsonb;free jsonb;m integer;
BEGIN
 SELECT pharmacy_id INTO pid FROM public.scl290_registry WHERE id=p_rid;
 y0:=extract(year FROM d)::integer;
 FOR y IN y0..y0+1 LOOP
  SELECT s.state_json INTO st FROM public.scl290_snapshots s WHERE s.pharmacy_id=pid AND s.year=y;
  IF NOT FOUND THEN CONTINUE; END IF;
  tv:=CASE WHEN jsonb_typeof(st->'turnover')='number' THEN (st->>'turnover')::numeric END;
  IF tv IS NULL OR tv<=0 THEN CONTINUE; END IF;
  has_turnover:=true;
  SELECT c INTO card FROM jsonb_array_elements(CASE WHEN jsonb_typeof(st->'cards')='array' THEN st->'cards' ELSE '[]'::jsonb END) c WHERE c->>'id'=p_pos->>'id' LIMIT 1;
  IF card IS NULL OR coalesce(card->>'initialPlanLocked','')<>'true' THEN CONTINUE; END IF;
  has_locked:=true;
  free:='[]'::jsonb;
  FOR m IN 0..11 LOOP
   IF make_date(y,m+1,1)+interval '1 month'<=d THEN CONTINUE; END IF;
   IF scl_private.position_active(p_pos||jsonb_build_object('stopsOn',card->'stopsOn'),y,m) THEN has_active:=true; END IF;
   IF d<=scl_private.cutoff(y,m)-7 AND scl_private.mk_month_free(card,p_pos,y,m) THEN free:=free||to_jsonb(m); END IF;
  END LOOP;
  years:=years||jsonb_build_object('year',y,'price',scl_private.mk_price(tv,scl_private.mk_num(st->'totalCounters')),'free',free);
 END LOOP;
 RETURN jsonb_build_object('id',p_pos->>'id','title',coalesce(nullif(p_pos->>'title',''),p_pos->>'id'),
  'format',CASE WHEN p_pos->>'screenFormat'='horizontal' THEN 'horizontal' ELSE 'vertical' END,
  'ok',has_turnover AND has_locked AND has_active,
  'reason',CASE WHEN NOT has_turnover THEN 'turnover' WHEN NOT has_locked THEN 'initial' WHEN NOT has_active THEN 'inactive' END,
  'years',CASE WHEN has_turnover AND has_locked AND has_active THEN years ELSE '[]'::jsonb END);
END $$;

-- Θέσεις πάγκου (type base) της εγκατάστασης ενός φαρμακείου. Η θέση Pharmaplus και οι Promotion/Experience δεν πωλούνται στο Κ1.
CREATE FUNCTION scl_private.mk_base_positions(p_rid uuid) RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT p FROM public.scl290_registry r JOIN public.scl290_installations i ON i.pharmacy_id=r.pharmacy_id,
  jsonb_array_elements(CASE WHEN jsonb_typeof(i.positions)='array' THEN i.positions ELSE '[]'::jsonb END) WITH ORDINALITY AS t(p,o)
 WHERE r.id=p_rid AND p->>'type'='base' AND (p->>'id') ~ '^base-[0-9]{1,2}$'
 ORDER BY coalesce(scl_private.mk_num(p->'ordinal'),o),o
$$;

-- Η κάρτα του φαρμακείου ΟΠΩΣ ΤΗ ΒΛΕΠΕΙ Η ΕΤΑΙΡΙΑ. Κλειστό φαρμακείο: μόνο όνομα, περιοχή, σημείο.
CREATE FUNCTION scl_private.mk_card(p_rid uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.scl290_registry;g scl_private.mk_pharmacy;pos jsonb;v jsonb;positions jsonb:='[]'::jsonb;vis boolean;band integer;base jsonb;
BEGIN
 SELECT * INTO r FROM public.scl290_registry WHERE id=p_rid;
 IF NOT FOUND OR r.pharmacy_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.scl290_installations i WHERE i.pharmacy_id=r.pharmacy_id) THEN RETURN NULL; END IF;
 SELECT * INTO g FROM scl_private.mk_pharmacy WHERE registry_id=p_rid;
 FOR pos IN SELECT * FROM scl_private.mk_base_positions(p_rid) LOOP
  SELECT s.visible INTO vis FROM scl_private.mk_position_settings s WHERE s.registry_id=p_rid AND s.position_id=pos->>'id';
  IF coalesce(vis,false) AND g.terms_accepted_at IS NOT NULL THEN
   v:=scl_private.mk_position_view(p_rid,pos);
   IF (v->>'ok')::boolean THEN positions:=positions||(v-'ok'-'reason'); END IF;
  END IF;
 END LOOP;
 base:=jsonb_build_object('id',r.id,'name',r.name,'area',r.area,'lat',g.lat,'lng',g.lng,'open',jsonb_array_length(positions)>0);
 IF jsonb_array_length(positions)=0 THEN RETURN base; END IF;
 band:=scl_private.mk_band(nullif(scl_private.sales_effective(p_rid,extract(year FROM scl_private.today())::integer)#>>'{effective,visits_monthly}','')::numeric);
 RETURN base||jsonb_build_object('band',band,'positions',positions,
  'has_3d',EXISTS(SELECT 1 FROM scl_private.fp_versions f WHERE f.registry_id=p_rid AND f.status='active' AND f.params ? 'cam'));
END $$;

-- Έλεγχος προσωπικού συνδέσμου Market.
CREATE FUNCTION scl_private.mk_access_id(p_key text) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE aid uuid;
BEGIN
 IF p_key IS NULL OR p_key !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Μη έγκυρη πρόσβαση Market'; END IF;
 SELECT id INTO aid FROM scl_private.mk_access WHERE token=p_key::uuid AND revoked_at IS NULL;
 IF aid IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Μη έγκυρη πρόσβαση Market'; END IF;
 RETURN aid;
END $$;

-- Φαρμακείο: όλα όσα χρειάζεται η σελίδα «Οι οθόνες μου» για τους διακόπτες.
CREATE FUNCTION scl_private.mk_pharmacy_view(p_rid uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE g scl_private.mk_pharmacy;pos jsonb;v jsonb;s scl_private.mk_position_settings;out jsonb:='[]'::jsonb;
BEGIN
 SELECT * INTO g FROM scl_private.mk_pharmacy WHERE registry_id=p_rid;
 FOR pos IN SELECT * FROM scl_private.mk_base_positions(p_rid) LOOP
  v:=scl_private.mk_position_view(p_rid,pos);
  SELECT * INTO s FROM scl_private.mk_position_settings x WHERE x.registry_id=p_rid AND x.position_id=pos->>'id';
  out:=out||(v||jsonb_build_object('visible',coalesce(s.visible,false),'group_offers',coalesce(s.group_offers,false)));
 END LOOP;
 RETURN jsonb_build_object('terms_accepted_at',g.terms_accepted_at,'positions',out,'company_view',scl_private.mk_card(p_rid));
END $$;

-- 3. Δημόσιες συναρτήσεις.
-- Φαρμακείο: ανάγνωση.
CREATE FUNCTION public.scl360_market_get(p_token text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid;rid uuid;
BEGIN
 pid:=public.scl290_token_id(p_token);
 SELECT id INTO rid FROM public.scl290_registry WHERE pharmacy_id=pid;
 RETURN scl_private.mk_pharmacy_view(rid);
END $$;

-- Φαρμακείο: αλλαγή διακόπτη. NULL = δεν αλλάζει. Το άνοιγμα θέλει αποδοχή όρων (μία φορά) και θέση έτοιμη· το κλείσιμο επιτρέπεται πάντα.
CREATE FUNCTION public.scl360_market_set(p_token text,p_position_id text,p_visible boolean,p_group_offers boolean,p_accept_terms boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid;rid uuid;pos jsonb;v jsonb;cur scl_private.mk_position_settings;nv boolean;ng boolean;accepted timestamptz;
BEGIN
 pid:=public.scl290_token_id(p_token);
 SELECT id INTO rid FROM public.scl290_registry WHERE pharmacy_id=pid;
 SELECT p INTO pos FROM scl_private.mk_base_positions(rid) p WHERE p->>'id'=p_position_id;
 IF pos IS NULL THEN RAISE EXCEPTION 'MARKET_POSITION: Η θέση δεν υπάρχει ή δεν πωλείται'; END IF;
 SELECT * INTO cur FROM scl_private.mk_position_settings WHERE registry_id=rid AND position_id=p_position_id;
 nv:=coalesce(p_visible,cur.visible,false);ng:=coalesce(p_group_offers,cur.group_offers,false);
 IF (nv AND NOT coalesce(cur.visible,false)) OR (ng AND NOT coalesce(cur.group_offers,false)) THEN
  SELECT terms_accepted_at INTO accepted FROM scl_private.mk_pharmacy WHERE registry_id=rid;
  IF accepted IS NULL THEN
   IF p_accept_terms IS NOT TRUE THEN RAISE EXCEPTION 'MARKET_TERMS: Χρειάζεται αποδοχή των όρων'; END IF;
   INSERT INTO scl_private.mk_pharmacy(registry_id,terms_accepted_at) VALUES(rid,now())
    ON CONFLICT(registry_id) DO UPDATE SET terms_accepted_at=now(),updated_at=now();
   INSERT INTO scl_private.mk_settings_history(registry_id,event) VALUES(rid,'terms');
  END IF;
  v:=scl_private.mk_position_view(rid,pos);
  IF NOT (v->>'ok')::boolean THEN RAISE EXCEPTION 'MARKET_NOT_READY:%',v->>'reason'; END IF;
 END IF;
 IF nv IS DISTINCT FROM coalesce(cur.visible,false) OR ng IS DISTINCT FROM coalesce(cur.group_offers,false) THEN
  INSERT INTO scl_private.mk_position_settings(registry_id,position_id,visible,group_offers) VALUES(rid,p_position_id,nv,ng)
   ON CONFLICT(registry_id,position_id) DO UPDATE SET visible=excluded.visible,group_offers=excluded.group_offers,updated_at=now();
  INSERT INTO scl_private.mk_settings_history(registry_id,position_id,event,visible,group_offers) VALUES(rid,p_position_id,'settings',nv,ng);
 END IF;
 RETURN scl_private.mk_pharmacy_view(rid);
END $$;

-- Κεντρικά: μία γραμμή ανά φαρμακείο με εγκατάσταση. Μόνο ανάγνωση.
CREATE FUNCTION public.scl360_hq_market_overview(p_hq_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('registry_id',r.id,
   'visible',(SELECT count(*) FROM scl_private.mk_position_settings s WHERE s.registry_id=r.id AND s.visible),
   'group_offers',(SELECT count(*) FROM scl_private.mk_position_settings s WHERE s.registry_id=r.id AND s.group_offers),
   'terms_accepted_at',g.terms_accepted_at,'has_point',g.lat IS NOT NULL,
   'has_plan',EXISTS(SELECT 1 FROM scl_private.fp_versions f WHERE f.registry_id=r.id AND f.status='active'),
   'has_3d',EXISTS(SELECT 1 FROM scl_private.fp_versions f WHERE f.registry_id=r.id AND f.status='active' AND f.params ? 'cam')) ORDER BY r.id)
  FROM public.scl290_registry r JOIN public.scl290_installations i ON i.pharmacy_id=r.pharmacy_id
  LEFT JOIN scl_private.mk_pharmacy g ON g.registry_id=r.id),'[]'::jsonb);
END $$;

-- Κεντρικά: «Δες πώς το βλέπουν οι εταιρίες» για ένα φαρμακείο. Η ίδια προεπισκόπηση με του φαρμακείου.
CREATE FUNCTION public.scl360_hq_market_preview(p_hq_key text,p_registry_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN scl_private.mk_pharmacy_view(p_registry_id);
END $$;

-- Market: λίστα φαρμακείων με οθόνες. Ανοιχτά με θέσεις και τιμή· κλειστά μόνο με όνομα, περιοχή, σημείο.
CREATE FUNCTION public.scl360_mk_list(p_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM scl_private.mk_access_id(p_key);
 RETURN coalesce((SELECT jsonb_agg(scl_private.mk_card(r.id) ORDER BY r.name,r.id)
  FROM public.scl290_registry r JOIN public.scl290_installations i ON i.pharmacy_id=r.pharmacy_id),'[]'::jsonb);
END $$;

-- Market: κάρτα ενός φαρμακείου, με την κάτοψη για το 3D όταν τα Κεντρικά έχουν ορίσει αρχική προβολή. Κλειστό φαρμακείο: χωρίς κάτοψη.
CREATE FUNCTION public.scl360_mk_pharmacy(p_key text,p_registry_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE c jsonb;vid uuid;pl jsonb;
BEGIN
 PERFORM scl_private.mk_access_id(p_key);
 c:=scl_private.mk_card(p_registry_id);
 IF c IS NULL THEN RAISE EXCEPTION 'MARKET_PHARMACY: Το φαρμακείο δεν βρέθηκε'; END IF;
 IF (c->>'open')::boolean AND (c->>'has_3d')::boolean THEN
  SELECT id INTO vid FROM scl_private.fp_versions WHERE registry_id=p_registry_id AND status='active';
  pl:=scl_private.fp_plan(vid);
  pl:=jsonb_set(pl,'{version}',coalesce(pl->'version','{}'::jsonb)-'note'-'based_on'-'edited_by');
  c:=c||jsonb_build_object('plan',pl);
 END IF;
 RETURN c;
END $$;

REVOKE ALL ON FUNCTION scl_private.mk_num(jsonb),scl_private.mk_price(numeric,numeric),scl_private.mk_band(numeric),scl_private.mk_covers(jsonb,integer),
 scl_private.mk_month_free(jsonb,jsonb,integer,integer),scl_private.mk_position_view(uuid,jsonb),scl_private.mk_base_positions(uuid),
 scl_private.mk_card(uuid),scl_private.mk_access_id(text),scl_private.mk_pharmacy_view(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.scl360_market_get(text),public.scl360_market_set(text,text,boolean,boolean,boolean),
 public.scl360_hq_market_overview(text),public.scl360_hq_market_preview(text,uuid),public.scl360_mk_list(text),public.scl360_mk_pharmacy(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl360_market_get(text),public.scl360_market_set(text,text,boolean,boolean,boolean),
 public.scl360_hq_market_overview(text),public.scl360_hq_market_preview(text,uuid),public.scl360_mk_list(text),public.scl360_mk_pharmacy(text,uuid) TO anon,authenticated;
