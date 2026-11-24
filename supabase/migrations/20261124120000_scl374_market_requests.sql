-- scl374: SpaceCoLLab Market, Κ3α «Αίτημα»: η εταιρία στέλνει αίτημα για θέση και μήνες, το φαρμακείο το βλέπει και μπορεί να πει «Δεν δέχομαι»,
-- τα Κεντρικά βλέπουν ό,τι περιμένει. Το «Δέχομαι» → Συμφωνία είναι το Κ3β και ΔΕΝ υπάρχει εδώ.
-- ΤΙ ΔΕΝ ΑΓΓΙΖΕΙ: scl290_snapshots, πρόγραμμα φαρμακείου, χρεώσεις, τιμοκατάλογο. Το αίτημα δεν κλειδώνει μήνα.
-- ΟΡΟΙ: κάθε αίτημα κρατά την έκδοση των όρων που είδαν εταιρία και φαρμακείο (mk_terms). Η εταιρία τους αποδέχεται όταν στέλνει.
-- ΠΛΑΝΟΓΡΑΜΜΑ: μέρος της συμφωνίας. Η εταιρία έχει βιβλιοθήκη προτύπων (κάθετο / οριζόντιο, 4 ράφια, χωρίς κωδικούς: σχήμα συσκευασίας, πλάτος, χρώματα, προσόψεις, με έλεγχο ότι χωράει). Στο αίτημα παγώνει αντίγραφο.
--  Υποχρεωτικό το πρότυπο που ταιριάζει στη θέση· το άλλο προαιρετικό (στα ομαδικά, Κ7, και τα δύο).
-- ΧΡΕΩΣΗ ΦΑΡΜΑΚΕΙΟΥ: μόνο ενημερωτικά και μόνο προς το φαρμακείο και τα Κεντρικά (30 € συμφωνία + 10 € μέσω Market, ανά θέμα). Η εταιρία δεν τη βλέπει ποτέ.
-- ΑΠΟΔΕΙΚΤΙΚΟ: κάθε αίτημα έχει αριθμό και ιστορικό (mk_request_log) που μόνο προστίθεται. Τα στοιχεία του αιτήματος δεν αλλάζουν ποτέ μετά την
-- αποστολή (trigger). Εξαίρεση: αιτήματα «δοκιμαστικής» εταιρίας, που τα Κεντρικά μπορούν να σβήσουν.
-- ΑΛΛΑΓΕΣ ΣΕ ΥΠΑΡΧΟΝΤΑ: +1 στήλη mk_company.is_test (προεπιλογή false)· νέα έκδοση 2 συναρτήσεων του Κ2:
--  scl_private.mk_company_hq (+is_test, +requests) και public.scl371_hq_company_delete (δεν σβήνει εταιρία που έχει πραγματικά αιτήματα).
-- Rollback: supabase/rollback/20261124120000_scl374_market_requests_rollback.sql

CREATE TABLE scl_private.backup_v374_functions AS
 SELECT n.nspname::text AS schema_name, p.proname::text AS fn, pg_get_function_identity_arguments(p.oid) AS args,
        pg_get_functiondef(p.oid) AS definition, now() AS taken_at
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','scl_private') AND p.prokind='f';
ALTER TABLE scl_private.backup_v374_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v374_functions FROM PUBLIC,anon,authenticated;

-- 1. Πίνακες.
ALTER TABLE scl_private.mk_company ADD COLUMN is_test boolean NOT NULL DEFAULT false;

-- Όροι ανά πλευρά και έκδοση. Οι παλιές εκδόσεις δεν σβήνονται, για να δείχνει κάθε αποδεικτικό τους όρους που ίσχυαν τότε.
-- audience: all = τους βλέπουν και οι δύο πλευρές · pharmacy = μόνο το φαρμακείο και τα Κεντρικά (χρέωση Pharmaplus).
CREATE TABLE scl_private.mk_terms(
 side text NOT NULL CHECK(side IN ('company','pharmacy')),
 version integer NOT NULL CHECK(version>0),
 items jsonb NOT NULL CHECK(jsonb_typeof(items)='array' AND jsonb_array_length(items) BETWEEN 1 AND 20),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(side,version));
ALTER TABLE scl_private.mk_terms ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.mk_terms FROM PUBLIC,anon,authenticated;
INSERT INTO scl_private.mk_terms(side,version,items) VALUES
('company',1,'[
 {"t":"Ζητάτε την οθόνη της θέσης μαζί με όλα τα ράφια της, για τους μήνες και στην τιμή που αναγράφονται."},
 {"t":"Αν το φαρμακείο δεχτεί, είναι οριστική συμφωνία μεταξύ της εταιρίας σας και του φαρμακείου."},
 {"t":"Πληρώνετε το φαρμακείο απευθείας, στο τέλος κάθε μήνα προβολής, με τιμολόγιο του φαρμακείου. Οι τιμές είναι προ ΦΠΑ."},
 {"t":"Παραδίδετε το υλικό έως τις 15 του προηγούμενου μήνα. Αν δεν το παραδώσετε, παίζει το βασικό πρόγραμμα του φαρμακείου και πληρώνετε κανονικά."},
 {"t":"Το πλανόγραμμα του αιτήματος είναι μέρος της συμφωνίας. Φροντίζετε να υπάρχουν τα προϊόντα στο φαρμακείο πριν από την έναρξη."},
 {"t":"Μπορείτε να αποσύρετε το αίτημα όσο περιμένει απάντηση. Μετά την αποδοχή, ακύρωση γίνεται μόνο μέσω της Pharmaplus."},
 {"t":"Η Pharmaplus είναι ενδιάμεσος και δεν είναι μέρος της συμφωνίας."}]'),
('pharmacy',1,'[
 {"t":"Δίνεις την οθόνη της θέσης μαζί με όλα τα ράφια της στην εταιρία, για τους μήνες και στην τιμή που αναγράφονται."},
 {"t":"Η αποδοχή είναι οριστική συμφωνία. Ακύρωση γίνεται μόνο μέσω των Κεντρικών."},
 {"t":"Τιμολογείς την εταιρία στο τέλος κάθε μήνα προβολής και εισπράττεις απευθείας από αυτήν."},
 {"t":"Στήνεις τα ράφια της θέσης με το πλανόγραμμα του αιτήματος που ταιριάζει στη θέση σου, για όλη τη διάρκεια."},
 {"t":"Απαντάς σε 7 ημέρες, το αργότερο έως τις 15 του προηγούμενου μήνα. Αλλιώς το αίτημα λήγει."},
 {"t":"Χρεώνεσαι από την Pharmaplus 30 € ανά θέμα για τη συμφωνία και 10 € ανά θέμα επειδή έκλεισε μέσω Market.","audience":"pharmacy"}]');

-- Βιβλιοθήκη πλανογραμμάτων της εταιρίας. shelves: 4 ράφια από πάνω προς τα κάτω, το καθένα λίστα προϊόντων {kind, name, w, color, cap, n} (βλ. mk_shelves).
CREATE TABLE scl_private.mk_planogram(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES scl_private.mk_company(id) ON DELETE CASCADE,
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 60),
 format text NOT NULL CHECK(format IN ('vertical','horizontal')),
 shelves jsonb NOT NULL,
 updated_by text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 archived_at timestamptz);
CREATE INDEX mk_planogram_company ON scl_private.mk_planogram(company_id) WHERE archived_at IS NULL;
ALTER TABLE scl_private.mk_planogram ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.mk_planogram FROM PUBLIC,anon,authenticated;

CREATE SEQUENCE scl_private.mk_request_no;
REVOKE ALL ON SEQUENCE scl_private.mk_request_no FROM PUBLIC,anon,authenticated;

-- Το αίτημα. Ό,τι είδε η εταιρία τη στιγμή της αποστολής μένει γραμμένο εδώ (ονόματα, τιμή), ακόμα κι αν αλλάξει αργότερα το μητρώο.
-- months: 0–11. status: pending | declined | expired | withdrawn | cancelled | accepted (το accepted γράφεται από το Κ3β).
-- reason: declined → month | other_months | fit | other · expired → time | closed | unavailable · cancelled → hq | company_inactive.
CREATE TABLE scl_private.mk_request(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 no integer NOT NULL UNIQUE DEFAULT nextval('scl_private.mk_request_no'),
 company_id uuid NOT NULL REFERENCES scl_private.mk_company(id) ON DELETE RESTRICT,
 company_name text NOT NULL,
 person_id uuid REFERENCES scl_private.mk_company_person(id) ON DELETE SET NULL,
 person_name text NOT NULL,
 registry_id uuid NOT NULL REFERENCES public.scl290_registry(id) ON DELETE RESTRICT,
 pharmacy_name text NOT NULL,
 position_id text NOT NULL CHECK(position_id ~ '^base-[0-9]{1,2}$'),
 position_title text NOT NULL,
 format text NOT NULL CHECK(format IN ('vertical','horizontal')),
 year integer NOT NULL CHECK(year BETWEEN 2026 AND 2100),
 months integer[] NOT NULL CHECK(cardinality(months) BETWEEN 1 AND 12),
 brand_ids integer[] NOT NULL CHECK(cardinality(brand_ids) BETWEEN 1 AND 10),
 brand_names text[] NOT NULL,
 categories text[] NOT NULL DEFAULT '{}',
 subcategories text[] NOT NULL DEFAULT '{}',
 theme text CHECK(theme IS NULL OR length(theme) BETWEEN 1 AND 60),
 same_theme boolean NOT NULL DEFAULT true,
 message text CHECK(message IS NULL OR length(message) BETWEEN 1 AND 200),
 price_month integer NOT NULL CHECK(price_month>0),
 plans jsonb NOT NULL CHECK(jsonb_typeof(plans)='array' AND jsonb_array_length(plans) BETWEEN 1 AND 12),
 terms_company integer NOT NULL,
 terms_pharmacy integer NOT NULL,
 fee_deal integer NOT NULL DEFAULT 30,
 fee_market integer NOT NULL DEFAULT 10,
 answer_by date NOT NULL,
 is_test boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','declined','expired','withdrawn','cancelled','accepted')),
 reason text CHECK(reason IS NULL OR length(reason)<=40),
 hq_note text CHECK(hq_note IS NULL OR length(hq_note)<=300),
 closed_at timestamptz,
 seen_pharmacy_at timestamptz,
 seen_company_at timestamptz,
 CHECK((status='pending')=(closed_at IS NULL))
);
CREATE INDEX mk_request_company ON scl_private.mk_request(company_id,created_at DESC);
CREATE INDEX mk_request_registry ON scl_private.mk_request(registry_id,created_at DESC);
CREATE INDEX mk_request_pending ON scl_private.mk_request(status) WHERE status='pending';

-- Ιστορικό αιτήματος: μόνο προσθήκες. side: company | pharmacy | hq | system.
CREATE TABLE scl_private.mk_request_log(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id uuid NOT NULL REFERENCES scl_private.mk_request(id) ON DELETE CASCADE,
 at timestamptz NOT NULL DEFAULT now(),
 side text NOT NULL CHECK(side IN ('company','pharmacy','hq','system')),
 actor text NOT NULL CHECK(length(actor) BETWEEN 1 AND 160),
 action text NOT NULL CHECK(action IN ('sent','seen','declined','expired','withdrawn','cancelled','answer_seen','accepted')),
 detail jsonb);
CREATE INDEX mk_request_log_req ON scl_private.mk_request_log(request_id,id);
ALTER TABLE scl_private.mk_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_request_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.mk_request,scl_private.mk_request_log FROM PUBLIC,anon,authenticated;

-- Φύλακες: τα στοιχεία του αιτήματος δεν αλλάζουν· αίτημα και ιστορικό δεν σβήνονται (εκτός δοκιμαστικών).
CREATE FUNCTION scl_private.mk_request_guard() RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  IF NOT OLD.is_test THEN RAISE EXCEPTION 'MARKET_REQ:immutable' USING ERRCODE='42501'; END IF;
  RETURN OLD;
 END IF;
 IF (NEW.id,NEW.no,NEW.company_id,NEW.company_name,NEW.person_name,NEW.registry_id,NEW.pharmacy_name,NEW.position_id,NEW.position_title,NEW.format,NEW.year,
     NEW.months,NEW.brand_ids,NEW.brand_names,NEW.categories,NEW.subcategories,NEW.theme,NEW.same_theme,NEW.message,NEW.price_month,NEW.plans,NEW.terms_company,NEW.terms_pharmacy,NEW.fee_deal,NEW.fee_market,NEW.answer_by,NEW.is_test,NEW.created_at)
    IS DISTINCT FROM
    (OLD.id,OLD.no,OLD.company_id,OLD.company_name,OLD.person_name,OLD.registry_id,OLD.pharmacy_name,OLD.position_id,OLD.position_title,OLD.format,OLD.year,
     OLD.months,OLD.brand_ids,OLD.brand_names,OLD.categories,OLD.subcategories,OLD.theme,OLD.same_theme,OLD.message,OLD.price_month,OLD.plans,OLD.terms_company,OLD.terms_pharmacy,OLD.fee_deal,OLD.fee_market,OLD.answer_by,OLD.is_test,OLD.created_at)
 THEN RAISE EXCEPTION 'MARKET_REQ:immutable' USING ERRCODE='42501'; END IF;
 IF OLD.status<>'pending' AND NEW.status IS DISTINCT FROM OLD.status THEN RAISE EXCEPTION 'MARKET_REQ:immutable' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER mk_request_guard BEFORE UPDATE OR DELETE ON scl_private.mk_request FOR EACH ROW EXECUTE FUNCTION scl_private.mk_request_guard();
CREATE FUNCTION scl_private.mk_request_log_guard() RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
 IF TG_OP='DELETE' AND NOT EXISTS(SELECT 1 FROM scl_private.mk_request r WHERE r.id=OLD.request_id AND NOT r.is_test) THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'MARKET_REQ:immutable' USING ERRCODE='42501';
END $$;
CREATE TRIGGER mk_request_log_guard BEFORE UPDATE OR DELETE ON scl_private.mk_request_log FOR EACH ROW EXECUTE FUNCTION scl_private.mk_request_log_guard();
REVOKE ALL ON FUNCTION scl_private.mk_request_guard(),scl_private.mk_request_log_guard() FROM PUBLIC,anon,authenticated;

-- 2. Ιδιωτικές συναρτήσεις.
CREATE FUNCTION scl_private.mk_req_label(p_no integer, p_at timestamptz) RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO '' AS $$
 SELECT 'ΑΙΤ-'||extract(year FROM p_at AT TIME ZONE 'Europe/Athens')::integer::text||'-'||lpad(p_no::text,5,'0') $$;

-- Είναι ακόμα ελεύθεροι οι μήνες του αιτήματος; NULL = ναι. 'unavailable' = η θέση ή το πρόγραμμά της δεν υπάρχει πια · 'closed' = κάποιος μήνας κλείστηκε.
-- (Δεν κοιτά τον διακόπτη ορατότητας: αίτημα που περιμένει απαντιέται ακόμα κι αν το φαρμακείο κλείσει το «Φαίνεται».)
CREATE FUNCTION scl_private.mk_req_block(p_rid uuid, p_pos text, p_year integer, p_months integer[]) RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid; pos jsonb; st jsonb; card jsonb; m integer;
BEGIN
 SELECT p INTO pos FROM scl_private.mk_base_positions(p_rid) p WHERE p->>'id'=p_pos;
 IF pos IS NULL THEN RETURN 'unavailable'; END IF;
 SELECT pharmacy_id INTO pid FROM public.scl290_registry WHERE id=p_rid;
 SELECT s.state_json INTO st FROM public.scl290_snapshots s WHERE s.pharmacy_id=pid AND s.year=p_year;
 IF st IS NULL THEN RETURN 'unavailable'; END IF;
 SELECT c INTO card FROM jsonb_array_elements(CASE WHEN jsonb_typeof(st->'cards')='array' THEN st->'cards' ELSE '[]'::jsonb END) c WHERE c->>'id'=p_pos LIMIT 1;
 IF card IS NULL THEN RETURN 'unavailable'; END IF;
 FOREACH m IN ARRAY p_months LOOP
  IF NOT scl_private.mk_month_free(card,pos,p_year,m) THEN RETURN 'closed'; END IF;
 END LOOP;
 RETURN NULL;
END $$;

CREATE FUNCTION scl_private.mk_req_log(p_id uuid, p_side text, p_actor text, p_action text, p_detail jsonb DEFAULT NULL) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $$
 INSERT INTO scl_private.mk_request_log(request_id,side,actor,action,detail) VALUES(p_id,p_side,left(p_actor,160),p_action,p_detail) $$;

-- Κλείνει όσα αιτήματα που περιμένουν δεν μπορούν πια να απαντηθούν. Δεν χρειάζεται χρονοδιακόπτης: τρέχει κάθε φορά που ανοίγει μια λίστα.
CREATE FUNCTION scl_private.mk_req_sweep(p_company uuid, p_rid uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r scl_private.mk_request%ROWTYPE; why text; st text;
BEGIN
 FOR r IN SELECT * FROM scl_private.mk_request x WHERE x.status='pending' AND (p_company IS NULL OR x.company_id=p_company) AND (p_rid IS NULL OR x.registry_id=p_rid) ORDER BY x.created_at FOR UPDATE LOOP
  why:=NULL;st:='expired';
  IF NOT (SELECT c.active FROM scl_private.mk_company c WHERE c.id=r.company_id) THEN st:='cancelled';why:='company_inactive';
  ELSIF scl_private.today()>r.answer_by THEN why:='time';
  ELSE why:=scl_private.mk_req_block(r.registry_id,r.position_id,r.year,r.months);
  END IF;
  IF why IS NOT NULL THEN
   UPDATE scl_private.mk_request SET status=st,reason=why,closed_at=now() WHERE id=r.id;
   PERFORM scl_private.mk_req_log(r.id,'system','Σύστημα',st,jsonb_build_object('reason',why));
  END IF;
 END LOOP;
END $$;

-- Η μονάδα ραφιών ανά format: πλάτος ραφιού σε εκατοστά και πλήθος ραφιών (Βαγγέλης 24/11: οριζόντια 50, κάθετη 35· χωρίς ύψη).
-- 4 ράφια από πάνω προς τα κάτω. Αλλάζουν μόνο εδώ.
CREATE FUNCTION scl_private.mk_shelf_spec(p_format text) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO '' AS $$
 SELECT CASE p_format WHEN 'horizontal' THEN '{"w":50,"n":4}'::jsonb WHEN 'vertical' THEN '{"w":35,"n":4}'::jsonb END $$;

-- Έλεγχος και καθάρισμα ραφιών πλανογράμματος. Κάθε προϊόν: {kind, name, w, color, cap?, n}.
--  kind: bottle | pump | spray | tube | jar | box | sachet · w: πλάτος σε εκατοστά (μισά επιτρέπονται) · color, cap: #rrggbb · n: προσόψεις 1–20.
-- Ακριβώς 4 ράφια, έως 12 προϊόντα το καθένα, τουλάχιστον 1 προϊόν συνολικά. Πρέπει να χωράνε στο πλάτος: άθροισμα w×n ≤ πλάτος ραφιού. Ύψη δεν ελέγχονται.
CREATE FUNCTION scl_private.mk_shelves(v jsonb, p_format text) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path TO '' AS $$
DECLARE out jsonb:='[]'::jsonb; sh jsonb; it jsonb; row jsonb; nm text; n integer; w numeric; used numeric; total integer:=0; kd text; col text; cap text;
 spec jsonb:=scl_private.mk_shelf_spec(p_format);
BEGIN
 IF spec IS NULL THEN RAISE EXCEPTION 'MARKET_PLAN:format' USING ERRCODE='22023'; END IF;
 IF v IS NULL OR jsonb_typeof(v)<>'array' OR jsonb_array_length(v)<>(spec->>'n')::integer THEN RAISE EXCEPTION 'MARKET_PLAN:shelves' USING ERRCODE='22023'; END IF;
 FOR sh IN SELECT * FROM jsonb_array_elements(v) LOOP
  IF jsonb_typeof(sh)<>'array' OR jsonb_array_length(sh)>12 THEN RAISE EXCEPTION 'MARKET_PLAN:shelves' USING ERRCODE='22023'; END IF;
  row:='[]'::jsonb; used:=0;
  FOR it IN SELECT * FROM jsonb_array_elements(sh) LOOP
   IF jsonb_typeof(it)<>'object' THEN RAISE EXCEPTION 'MARKET_PLAN:item' USING ERRCODE='22023'; END IF;
   nm:=nullif(btrim(regexp_replace(coalesce(it->>'name',''),'[[:space:]]+',' ','g')),'');
   kd:=coalesce(it->>'kind','box'); col:=lower(coalesce(it->>'color','#2459e0')); cap:=lower(nullif(it->>'cap',''));
   IF nm IS NULL OR length(nm)>60 OR kd NOT IN ('bottle','pump','spray','tube','jar','box','sachet') OR col !~ '^#[0-9a-f]{6}$' OR (cap IS NOT NULL AND cap !~ '^#[0-9a-f]{6}$')
     OR coalesce(it->>'n',it->>'facings','1') !~ '^[0-9]{1,2}$' OR coalesce(it->>'w','5') !~ '^[0-9]{1,2}(\.[05])?$' THEN
    RAISE EXCEPTION 'MARKET_PLAN:item' USING ERRCODE='22023'; END IF;
   n:=coalesce(it->>'n',it->>'facings','1')::integer; w:=coalesce(it->>'w','5')::numeric;
   IF n<1 OR n>20 OR w<1 THEN RAISE EXCEPTION 'MARKET_PLAN:item' USING ERRCODE='22023'; END IF;
   used:=used+w*n;
   row:=row||jsonb_strip_nulls(jsonb_build_object('kind',kd,'name',nm,'w',w,'color',col,'cap',cap,'n',n)); total:=total+1;
  END LOOP;
  IF used>(spec->>'w')::numeric THEN RAISE EXCEPTION 'MARKET_PLAN:width' USING ERRCODE='22023'; END IF;
  out:=out||jsonb_build_array(row);
 END LOOP;
 IF total=0 THEN RAISE EXCEPTION 'MARKET_PLAN:empty' USING ERRCODE='22023'; END IF;
 RETURN out;
END $$;

CREATE FUNCTION scl_private.mk_plan_list(p_company uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'format',g.format,'shelves',g.shelves,'updated_at',g.updated_at,'updated_by',g.updated_by) ORDER BY g.format DESC,upper(g.name)),'[]'::jsonb)
 FROM scl_private.mk_planogram g WHERE g.company_id=p_company AND g.archived_at IS NULL $$;

-- Οι όροι μιας πλευράς σε μια έκδοση. p_all=false: χωρίς όσα είναι μόνο για το φαρμακείο.
CREATE FUNCTION scl_private.mk_terms_items(p_side text, p_version integer, p_all boolean) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT coalesce((SELECT jsonb_agg(e->>'t' ORDER BY o) FROM scl_private.mk_terms t, jsonb_array_elements(t.items) WITH ORDINALITY x(e,o)
  WHERE t.side=p_side AND t.version=p_version AND (p_all OR coalesce(e->>'audience','all')='all')),'[]'::jsonb) $$;

-- Το αίτημα όπως το βλέπει κάθε πλευρά. side: company | pharmacy | hq.
-- Η εταιρία δεν βλέπει το σχόλιο του φαρμακείου ούτε τον λόγο ακύρωσης των Κεντρικών. Το φαρμακείο δεν βλέπει ΑΦΜ ή στοιχεία τιμολόγησης.
CREATE FUNCTION scl_private.mk_req_json(r scl_private.mk_request, p_side text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT jsonb_build_object('id',r.id,'no',scl_private.mk_req_label(r.no,r.created_at),'status',r.status,'reason',r.reason,
   'company',r.company_name,'sender',r.person_name,
   'pharmacy',jsonb_build_object('id',r.registry_id,'name',r.pharmacy_name,'area',(SELECT g.area FROM public.scl290_registry g WHERE g.id=r.registry_id)),
   'position',jsonb_build_object('id',r.position_id,'title',r.position_title,'format',r.format),
   'year',r.year,'months',to_jsonb(r.months),'brands',to_jsonb(r.brand_names),'theme',r.theme,'same_theme',r.same_theme,'message',r.message,
   'categories',to_jsonb(r.categories),'subcategories',to_jsonb(r.subcategories),
   'price_month',r.price_month,'total',r.price_month*cardinality(r.months),'plans',r.plans,
   -- η εταιρία βλέπει και τι αναλαμβάνει το φαρμακείο, ΧΩΡΙΣ τον όρο της χρέωσής του (audience=pharmacy)
   'terms',jsonb_build_object('version',r.terms_company,'company',scl_private.mk_terms_items('company',r.terms_company,false),
     'pharmacy_version',r.terms_pharmacy,'pharmacy',scl_private.mk_terms_items('pharmacy',r.terms_pharmacy,false)),
   'created_at',r.created_at,'answer_by',r.answer_by,'days_left',CASE WHEN r.status='pending' THEN r.answer_by-scl_private.today() END,
   'closed_at',r.closed_at,'is_test',r.is_test)
  -- Απόφαση 24/11: η εταιρία ΔΕΝ μαθαίνει αν το φαρμακείο άνοιξε το αίτημα.
  ||CASE WHEN p_side IN ('pharmacy','hq') THEN jsonb_build_object('seen_pharmacy_at',r.seen_pharmacy_at) ELSE '{}'::jsonb END
  ||CASE WHEN p_side='hq' THEN jsonb_build_object('hq_note',r.hq_note,'seen_company_at',r.seen_company_at,
      'pharmacy_code',(SELECT g.pharmacy_code FROM public.scl290_registry g WHERE g.id=r.registry_id)) ELSE '{}'::jsonb END
  ||CASE WHEN p_side='company' THEN jsonb_build_object('seen_company_at',r.seen_company_at) ELSE '{}'::jsonb END
  ||CASE WHEN p_side IN ('pharmacy','hq') THEN jsonb_build_object(
      'terms',jsonb_build_object('version',r.terms_company,'company',scl_private.mk_terms_items('company',r.terms_company,false),
        'pharmacy_version',r.terms_pharmacy,'pharmacy',scl_private.mk_terms_items('pharmacy',r.terms_pharmacy,true),
        'pharmacy_public',scl_private.mk_terms_items('pharmacy',r.terms_pharmacy,false)),
      'charge',jsonb_build_object('themes',CASE WHEN r.same_theme THEN 1 ELSE cardinality(r.months) END,'deal',r.fee_deal,'market',r.fee_market,
        'total',(r.fee_deal+r.fee_market)*CASE WHEN r.same_theme THEN 1 ELSE cardinality(r.months) END,
        'net',r.price_month*cardinality(r.months)-(r.fee_deal+r.fee_market)*CASE WHEN r.same_theme THEN 1 ELSE cardinality(r.months) END)) ELSE '{}'::jsonb END $$;

-- Ιστορικό ενός αιτήματος όπως το βλέπει κάθε πλευρά (το σχόλιο/λόγος των Κεντρικών μόνο στα Κεντρικά).
CREATE FUNCTION scl_private.mk_req_history(p_id uuid, p_side text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('at',l.at,'side',l.side,'actor',l.actor,'action',l.action,
   'detail',CASE WHEN p_side='hq' THEN l.detail ELSE l.detail-'note' END) ORDER BY l.id),'[]'::jsonb)
 FROM scl_private.mk_request_log l WHERE l.request_id=p_id AND NOT (p_side='company' AND l.action='seen') $$;

CREATE FUNCTION scl_private.mk_ints(v jsonb, p_max integer) RETURNS integer[] LANGUAGE plpgsql IMMUTABLE SET search_path TO '' AS $$
DECLARE a integer[];
BEGIN
 IF v IS NULL OR jsonb_typeof(v)='null' THEN RETURN '{}'; END IF;
 IF jsonb_typeof(v)<>'array' OR jsonb_array_length(v)>p_max THEN RAISE EXCEPTION 'MARKET_REQ:bad_list' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v) e WHERE jsonb_typeof(e)<>'number' OR (e#>>'{}') !~ '^[0-9]{1,9}$') THEN RAISE EXCEPTION 'MARKET_REQ:bad_list' USING ERRCODE='22023'; END IF;
 SELECT coalesce(array_agg(DISTINCT (e#>>'{}')::integer ORDER BY (e#>>'{}')::integer),'{}') INTO a FROM jsonb_array_elements(v) e;
 RETURN a;
END $$;

-- Λίστα ονομάτων από jsonb (χωρίς διπλά, ταξινομημένη). Κατηγορίες και υποκατηγορίες στο αίτημα είναι μόνο πληροφορία, όχι δέσμευση.
CREATE FUNCTION scl_private.mk_strs(v jsonb, p_max integer) RETURNS text[] LANGUAGE plpgsql IMMUTABLE SET search_path TO '' AS $$
DECLARE a text[];
BEGIN
 IF v IS NULL OR jsonb_typeof(v)='null' THEN RETURN '{}'; END IF;
 IF jsonb_typeof(v)<>'array' OR jsonb_array_length(v)>p_max OR EXISTS(SELECT 1 FROM jsonb_array_elements(v) e WHERE jsonb_typeof(e)<>'string' OR length(e#>>'{}') NOT BETWEEN 1 AND 120) THEN
  RAISE EXCEPTION 'MARKET_REQ:bad_list' USING ERRCODE='22023'; END IF;
 SELECT coalesce(array_agg(DISTINCT e#>>'{}' ORDER BY e#>>'{}'),'{}') INTO a FROM jsonb_array_elements(v) e;
 RETURN a;
END $$;

-- 3. Market (εταιρία). Όλα θέλουν σύνδεση ανθρώπου: ο δοκιμαστικός σύνδεσμος δεν στέλνει αιτήματα.
-- Αποστολή. p: {registry_id, position_id, year, months:[0–11], brand_ids:[…], categories?:[ονόματα], subcategories?:[ονόματα], theme?, same_theme?, message?,
--  plans:[{months, vertical?, horizontal?}], accept_terms:true, terms_version}
CREATE FUNCTION public.scl374_mk_request_send(p_key text, p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key); co scl_private.mk_company%ROWTYPE; rid uuid; card jsonb; pos jsonb; yr jsonb;
 v_year integer; v_months integer[]; v_brands integer[]; v_cats text[]; v_subs text[]; v_theme text:=scl_private.mk_txt(p,'theme'); v_msg text:=scl_private.mk_txt(p,'message'); v_names text[]; nid uuid; r scl_private.mk_request%ROWTYPE;
 v_plans jsonb:='[]'::jsonb; e jsonb; pm integer[]; seen integer[]:='{}'; one jsonb; f text; g scl_private.mk_planogram%ROWTYPE; tc integer; tp integer;
BEGIN
 SELECT * INTO co FROM scl_private.mk_company WHERE id=me.company_id;
 IF coalesce(p->>'registry_id','') !~ '^[0-9a-fA-F-]{36}$' OR coalesce(p->>'position_id','') !~ '^base-[0-9]{1,2}$' OR coalesce(p->>'year','') !~ '^[0-9]{4}$' THEN
  RAISE EXCEPTION 'MARKET_REQ:bad_request' USING ERRCODE='22023'; END IF;
 rid:=(p->>'registry_id')::uuid; v_year:=(p->>'year')::integer;
 v_months:=scl_private.mk_ints(p->'months',12); v_brands:=scl_private.mk_ints(p->'brand_ids',10);
 v_cats:=scl_private.mk_strs(p->'categories',20); v_subs:=scl_private.mk_strs(p->'subcategories',40);
 IF cardinality(v_months)=0 OR EXISTS(SELECT 1 FROM unnest(v_months) m WHERE m>11) THEN RAISE EXCEPTION 'MARKET_REQ:months' USING ERRCODE='22023'; END IF;
 IF cardinality(v_brands)=0 THEN RAISE EXCEPTION 'MARKET_REQ:brand' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(v_brands) b WHERE NOT EXISTS(SELECT 1 FROM scl_private.mk_company_brand cb WHERE cb.company_id=co.id AND cb.brand_id=b)) THEN
  RAISE EXCEPTION 'MARKET_REQ:brand_not_yours' USING ERRCODE='42501'; END IF;
 IF v_theme IS NOT NULL AND length(v_theme)>60 THEN RAISE EXCEPTION 'MARKET_REQ:theme_long' USING ERRCODE='22023'; END IF;
 IF v_msg IS NOT NULL AND length(v_msg)>200 THEN RAISE EXCEPTION 'MARKET_REQ:message_long' USING ERRCODE='22023'; END IF;
 IF cardinality(v_brands)>1 AND v_theme IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:theme_required' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(v_cats) x WHERE NOT EXISTS(SELECT 1 FROM scl_private.mk_category c WHERE c.name=x))
  OR EXISTS(SELECT 1 FROM unnest(v_subs) x WHERE NOT EXISTS(SELECT 1 FROM scl_private.mk_subcategory s WHERE s.name=x)) THEN RAISE EXCEPTION 'MARKET_REQ:bad_list' USING ERRCODE='22023'; END IF;
 -- ό,τι βλέπει η εταιρία αυτή τη στιγμή: θέση ανοιχτή, μήνες ελεύθεροι και μέσα στο όριο (έως 8 του προηγούμενου)
 card:=scl_private.mk_card(rid);
 IF card IS NULL OR NOT coalesce((card->>'open')::boolean,false) THEN RAISE EXCEPTION 'MARKET_REQ:not_available' USING ERRCODE='22023'; END IF;
 SELECT x INTO pos FROM jsonb_array_elements(card->'positions') x WHERE x->>'id'=p->>'position_id';
 IF pos IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_available' USING ERRCODE='22023'; END IF;
 SELECT x INTO yr FROM jsonb_array_elements(pos->'years') x WHERE (x->>'year')::integer=v_year;
 IF yr IS NULL OR EXISTS(SELECT 1 FROM unnest(v_months) m WHERE NOT (yr->'free') @> to_jsonb(m)) THEN RAISE EXCEPTION 'MARKET_REQ:month_taken' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM scl_private.mk_request x WHERE x.company_id=co.id AND x.registry_id=rid AND x.position_id=p->>'position_id' AND x.year=v_year AND x.status='pending' AND x.months && v_months) THEN
  RAISE EXCEPTION 'MARKET_REQ:duplicate' USING ERRCODE='23505'; END IF;
 IF (SELECT count(*) FROM scl_private.mk_request x WHERE x.company_id=co.id AND x.status='pending')>=100 THEN RAISE EXCEPTION 'MARKET_REQ:too_many' USING ERRCODE='22023'; END IF;
 -- πλανογράμματα: plans = [{months:[…], vertical:<id>, horizontal:<id>}]. Όλοι οι μήνες του αιτήματος ακριβώς μία φορά. Ίδιο θέμα = μία γραμμή.
 IF jsonb_typeof(p->'plans') IS DISTINCT FROM 'array' OR jsonb_array_length(p->'plans') NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'MARKET_REQ:plan_required' USING ERRCODE='22023'; END IF;
 IF coalesce((p->>'same_theme')::boolean,true) AND jsonb_array_length(p->'plans')<>1 THEN RAISE EXCEPTION 'MARKET_REQ:plan_months' USING ERRCODE='22023'; END IF;
 FOR e IN SELECT * FROM jsonb_array_elements(p->'plans') LOOP
  pm:=scl_private.mk_ints(e->'months',12);
  IF cardinality(pm)=0 OR pm && seen OR NOT pm <@ v_months THEN RAISE EXCEPTION 'MARKET_REQ:plan_months' USING ERRCODE='22023'; END IF;
  seen:=seen||pm; one:=jsonb_build_object('months',to_jsonb(pm));
  FOREACH f IN ARRAY ARRAY['vertical','horizontal'] LOOP
   IF coalesce(e->>f,'')='' THEN
    IF f=pos->>'format' THEN RAISE EXCEPTION 'MARKET_REQ:plan_required' USING ERRCODE='22023'; END IF;
    CONTINUE;
   END IF;
   IF (e->>f) !~ '^[0-9a-fA-F-]{36}$' THEN RAISE EXCEPTION 'MARKET_REQ:plan_not_found' USING ERRCODE='P0002'; END IF;
   SELECT * INTO g FROM scl_private.mk_planogram WHERE id=(e->>f)::uuid AND company_id=co.id AND archived_at IS NULL AND format=f;
   IF g.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:plan_not_found' USING ERRCODE='P0002'; END IF;
   one:=one||jsonb_build_object(f,jsonb_build_object('name',g.name,'shelves',g.shelves));
  END LOOP;
  v_plans:=v_plans||one;
 END LOOP;
 IF cardinality(seen)<>cardinality(v_months) THEN RAISE EXCEPTION 'MARKET_REQ:plan_months' USING ERRCODE='22023'; END IF;
 -- αποδοχή όρων: η εταιρία συμφωνεί με την τρέχουσα έκδοση
 SELECT max(version) FILTER(WHERE side='company'),max(version) FILTER(WHERE side='pharmacy') INTO tc,tp FROM scl_private.mk_terms;
 IF (p->>'accept_terms') IS DISTINCT FROM 'true' OR coalesce(p->>'terms_version','') IS DISTINCT FROM tc::text THEN RAISE EXCEPTION 'MARKET_REQ:terms' USING ERRCODE='22023'; END IF;
 SELECT array_agg(b.name ORDER BY b.name) INTO v_names FROM scl_private.mk_brand b WHERE b.id=ANY(v_brands);
 INSERT INTO scl_private.mk_request(company_id,company_name,person_id,person_name,registry_id,pharmacy_name,position_id,position_title,format,year,months,brand_ids,brand_names,
   categories,subcategories,theme,same_theme,message,price_month,plans,terms_company,terms_pharmacy,answer_by,is_test)
  VALUES(co.id,co.name,me.id,me.full_name,rid,card->>'name',pos->>'id',pos->>'title',pos->>'format',v_year,v_months,v_brands,v_names,v_cats,v_subs,v_theme,
   coalesce((p->>'same_theme')::boolean,true),v_msg,(yr->>'price')::integer,v_plans,tc,tp,
   least(scl_private.today()+7,scl_private.cutoff(v_year,(SELECT min(m) FROM unnest(v_months) m))),co.is_test)
  RETURNING id INTO nid;
 SELECT * INTO r FROM scl_private.mk_request WHERE id=nid;
 PERFORM scl_private.mk_req_log(nid,'company',me.full_name||' · '||co.name,'sent',
  jsonb_build_object('pharmacy',r.pharmacy_name,'position',r.position_title,'year',r.year,'months',to_jsonb(r.months),'brands',to_jsonb(r.brand_names),'theme',r.theme,
   'same_theme',r.same_theme,'price_month',r.price_month,'answer_by',r.answer_by,'terms_accepted',r.terms_company,
   'plans',(SELECT jsonb_agg(jsonb_build_object('months',x->'months','vertical',x#>'{vertical,name}','horizontal',x#>'{horizontal,name}')) FROM jsonb_array_elements(r.plans) x)));
 RETURN jsonb_build_object('request',scl_private.mk_req_json(r,'company'));
END $$;

-- Οι όροι που ισχύουν τώρα για την εταιρία (τους βλέπει πριν στείλει).
CREATE FUNCTION public.scl374_mk_terms(p_key text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v integer; vp integer;
BEGIN
 PERFORM scl_private.mk_access_id(p_key);
 SELECT max(version) INTO v FROM scl_private.mk_terms WHERE side='company';
 SELECT max(version) INTO vp FROM scl_private.mk_terms WHERE side='pharmacy';
 RETURN jsonb_build_object('version',v,'items',scl_private.mk_terms_items('company',v,false),'pharmacy_items',scl_private.mk_terms_items('pharmacy',vp,false));
END $$;

-- Βιβλιοθήκη πλανογραμμάτων της εταιρίας.
CREATE FUNCTION public.scl374_mk_planograms(p_key text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key);
BEGIN RETURN jsonb_build_object('planograms',scl_private.mk_plan_list(me.company_id),
 'spec',jsonb_build_object('vertical',scl_private.mk_shelf_spec('vertical'),'horizontal',scl_private.mk_shelf_spec('horizontal'))); END $$;

-- Αποθήκευση προτύπου. p: {id?, name, format, shelves:[[{name,facings}…]×4]}. Τα αιτήματα που έχουν ήδη σταλεί δεν αλλάζουν (κρατούν αντίγραφο).
CREATE FUNCTION public.scl374_mk_planogram_save(p_key text, p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key); v_name text:=scl_private.mk_txt(p,'name'); v_fmt text:=p->>'format'; v_sh jsonb; pid uuid;
BEGIN
 IF v_name IS NULL OR length(v_name)>60 THEN RAISE EXCEPTION 'MARKET_PLAN:name' USING ERRCODE='22023'; END IF;
 IF v_fmt IS NULL OR v_fmt NOT IN ('vertical','horizontal') THEN RAISE EXCEPTION 'MARKET_PLAN:format' USING ERRCODE='22023'; END IF;
 v_sh:=scl_private.mk_shelves(p->'shelves',v_fmt);
 IF coalesce(p->>'id','')<>'' THEN
  IF (p->>'id') !~ '^[0-9a-fA-F-]{36}$' THEN RAISE EXCEPTION 'MARKET_PLAN:not_found' USING ERRCODE='P0002'; END IF;
  UPDATE scl_private.mk_planogram SET name=v_name,shelves=v_sh,updated_by=me.full_name,updated_at=now()
   WHERE id=(p->>'id')::uuid AND company_id=me.company_id AND archived_at IS NULL AND format=v_fmt RETURNING id INTO pid;
  IF pid IS NULL THEN RAISE EXCEPTION 'MARKET_PLAN:not_found' USING ERRCODE='P0002'; END IF;
 ELSE
  IF (SELECT count(*) FROM scl_private.mk_planogram WHERE company_id=me.company_id AND archived_at IS NULL)>=60 THEN RAISE EXCEPTION 'MARKET_PLAN:too_many' USING ERRCODE='22023'; END IF;
  INSERT INTO scl_private.mk_planogram(company_id,name,format,shelves,updated_by) VALUES(me.company_id,v_name,v_fmt,v_sh,me.full_name) RETURNING id INTO pid;
 END IF;
 RETURN jsonb_build_object('id',pid,'planograms',scl_private.mk_plan_list(me.company_id));
END $$;

CREATE FUNCTION public.scl374_mk_planogram_delete(p_key text, p_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key);
BEGIN
 UPDATE scl_private.mk_planogram SET archived_at=now(),updated_by=me.full_name WHERE id=p_id AND company_id=me.company_id AND archived_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'MARKET_PLAN:not_found' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('planograms',scl_private.mk_plan_list(me.company_id));
END $$;

-- Τα αιτήματά μου. unseen = απαντήσεις που δεν έχει δει ακόμα η εταιρία.
CREATE FUNCTION public.scl374_mk_requests(p_key text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key);
BEGIN
 PERFORM scl_private.mk_req_sweep(me.company_id,NULL);
 RETURN jsonb_build_object(
  'requests',(SELECT coalesce(jsonb_agg(scl_private.mk_req_json(r,'company') ORDER BY (r.status<>'pending'),r.created_at DESC),'[]'::jsonb) FROM scl_private.mk_request r WHERE r.company_id=me.company_id),
  'unseen',(SELECT count(*) FROM scl_private.mk_request r WHERE r.company_id=me.company_id AND r.status IN ('declined','expired','cancelled','accepted') AND r.seen_company_at IS NULL));
END $$;

-- Η εταιρία άνοιξε «Τα αιτήματά μου»: οι απαντήσεις θεωρούνται ιδωμένες.
CREATE FUNCTION public.scl374_mk_requests_seen(p_key text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key); r record; n integer:=0;
BEGIN
 FOR r IN UPDATE scl_private.mk_request x SET seen_company_at=now() WHERE x.company_id=me.company_id AND x.status IN ('declined','expired','cancelled','accepted') AND x.seen_company_at IS NULL RETURNING x.id LOOP
  PERFORM scl_private.mk_req_log(r.id,'company',me.full_name,'answer_seen'); n:=n+1;
 END LOOP;
 RETURN jsonb_build_object('seen',n);
END $$;

CREATE FUNCTION public.scl374_mk_request_withdraw(p_key text, p_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key); r scl_private.mk_request%ROWTYPE;
BEGIN
 PERFORM scl_private.mk_req_sweep(me.company_id,NULL);
 SELECT * INTO r FROM scl_private.mk_request WHERE id=p_id AND company_id=me.company_id FOR UPDATE;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 IF r.status<>'pending' THEN RETURN jsonb_build_object('ok',false,'request',scl_private.mk_req_json(r,'company')); END IF;
 UPDATE scl_private.mk_request SET status='withdrawn',closed_at=now(),seen_company_at=now() WHERE id=r.id RETURNING * INTO r;
 PERFORM scl_private.mk_req_log(r.id,'company',me.full_name,'withdrawn');
 RETURN jsonb_build_object('ok',true,'request',scl_private.mk_req_json(r,'company'));
END $$;

-- Αποδεικτικό: το αίτημα με όλο το ιστορικό του.
CREATE FUNCTION public.scl374_mk_request_log(p_key text, p_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key); r scl_private.mk_request%ROWTYPE;
BEGIN
 SELECT * INTO r FROM scl_private.mk_request WHERE id=p_id AND company_id=me.company_id;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('request',scl_private.mk_req_json(r,'company'),'log',scl_private.mk_req_history(r.id,'company'));
END $$;

-- 4. Φαρμακείο (με το token του, όπως όλο το εργαλείο).
-- p_seen=true: το φαρμακείο άνοιξε τη σελίδα «Αιτήματα», άρα όσα περιμένουν σημειώνονται ως ιδωμένα.
CREATE FUNCTION public.scl374_ph_requests(p_token text, p_seen boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token); rid uuid; nm text; r record;
BEGIN
 SELECT g.id,g.name INTO rid,nm FROM public.scl290_registry g WHERE g.pharmacy_id=pid;
 IF rid IS NULL THEN RETURN jsonb_build_object('pending','[]'::jsonb,'history','[]'::jsonb,'count',0); END IF;
 PERFORM scl_private.mk_req_sweep(NULL,rid);
 IF coalesce(p_seen,false) THEN
  FOR r IN UPDATE scl_private.mk_request x SET seen_pharmacy_at=now() WHERE x.registry_id=rid AND x.status='pending' AND x.seen_pharmacy_at IS NULL RETURNING x.id LOOP
   PERFORM scl_private.mk_req_log(r.id,'pharmacy',nm,'seen');
  END LOOP;
 END IF;
 RETURN jsonb_build_object(
  'pending',(SELECT coalesce(jsonb_agg(scl_private.mk_req_json(x,'pharmacy') ORDER BY x.answer_by,x.created_at),'[]'::jsonb) FROM scl_private.mk_request x WHERE x.registry_id=rid AND x.status='pending'),
  'history',(SELECT coalesce(jsonb_agg(j ORDER BY ca DESC),'[]'::jsonb) FROM (SELECT scl_private.mk_req_json(x,'pharmacy') j,x.closed_at ca FROM scl_private.mk_request x WHERE x.registry_id=rid AND x.status<>'pending' ORDER BY x.closed_at DESC LIMIT 100) h),
  'count',(SELECT count(*) FROM scl_private.mk_request x WHERE x.registry_id=rid AND x.status='pending'));
END $$;

-- «Δεν δέχομαι». p_reason: month | other_months | fit | other. Το σχόλιο (προαιρετικό) το βλέπουν μόνο τα Κεντρικά.
CREATE FUNCTION public.scl374_ph_request_decline(p_token text, p_id uuid, p_reason text, p_note text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token); rid uuid; nm text; r scl_private.mk_request%ROWTYPE; v_note text:=nullif(btrim(coalesce(p_note,'')),'');
BEGIN
 SELECT g.id,g.name INTO rid,nm FROM public.scl290_registry g WHERE g.pharmacy_id=pid;
 IF p_reason IS NULL OR p_reason NOT IN ('month','other_months','fit','other') THEN RAISE EXCEPTION 'MARKET_REQ:reason' USING ERRCODE='22023'; END IF;
 IF v_note IS NOT NULL AND length(v_note)>300 THEN RAISE EXCEPTION 'MARKET_REQ:note_long' USING ERRCODE='22023'; END IF;
 PERFORM scl_private.mk_req_sweep(NULL,rid);
 SELECT * INTO r FROM scl_private.mk_request WHERE id=p_id AND registry_id=rid FOR UPDATE;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 IF r.status<>'pending' THEN RETURN jsonb_build_object('ok',false,'request',scl_private.mk_req_json(r,'pharmacy')); END IF;
 UPDATE scl_private.mk_request SET status='declined',reason=p_reason,hq_note=v_note,closed_at=now(),seen_pharmacy_at=coalesce(seen_pharmacy_at,now()) WHERE id=r.id RETURNING * INTO r;
 PERFORM scl_private.mk_req_log(r.id,'pharmacy',nm,'declined',jsonb_strip_nulls(jsonb_build_object('reason',p_reason,'note',v_note)));
 RETURN jsonb_build_object('ok',true,'request',scl_private.mk_req_json(r,'pharmacy'));
END $$;

CREATE FUNCTION public.scl374_ph_request_log(p_token text, p_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid:=public.scl290_token_id(p_token); r scl_private.mk_request%ROWTYPE;
BEGIN
 SELECT x.* INTO r FROM scl_private.mk_request x JOIN public.scl290_registry g ON g.id=x.registry_id WHERE x.id=p_id AND g.pharmacy_id=pid;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('request',scl_private.mk_req_json(r,'pharmacy'),'log',scl_private.mk_req_history(r.id,'pharmacy'));
END $$;

-- 5. Κεντρικά.
-- pending: όλα όσα περιμένουν, πρώτα όσα λήγουν σύντομα. unseen: απαντήσεις που η εταιρία δεν έχει δει. recent: τα τελευταία 100 κλειστά.
-- counts: χωρίς τα δοκιμαστικά.
CREATE FUNCTION public.scl374_hq_requests(p_hq_key text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 PERFORM scl_private.mk_req_sweep(NULL,NULL);
 RETURN jsonb_build_object(
  'pending',(SELECT coalesce(jsonb_agg(scl_private.mk_req_json(r,'hq') ORDER BY r.answer_by,r.created_at),'[]'::jsonb) FROM scl_private.mk_request r WHERE r.status='pending'),
  'unseen',(SELECT coalesce(jsonb_agg(scl_private.mk_req_json(r,'hq') ORDER BY r.closed_at),'[]'::jsonb) FROM scl_private.mk_request r WHERE r.status IN ('declined','expired','cancelled','accepted') AND r.seen_company_at IS NULL),
  'recent',(SELECT coalesce(jsonb_agg(j ORDER BY ca DESC),'[]'::jsonb) FROM (SELECT scl_private.mk_req_json(r,'hq') j,r.closed_at ca FROM scl_private.mk_request r WHERE r.status<>'pending' ORDER BY r.closed_at DESC LIMIT 100) h),
  'counts',jsonb_build_object(
   'pending',(SELECT count(*) FROM scl_private.mk_request r WHERE r.status='pending' AND NOT r.is_test),
   'urgent',(SELECT count(*) FROM scl_private.mk_request r WHERE r.status='pending' AND NOT r.is_test AND r.answer_by-scl_private.today()<=2),
   'unseen',(SELECT count(*) FROM scl_private.mk_request r WHERE r.status IN ('declined','expired','cancelled','accepted') AND r.seen_company_at IS NULL AND NOT r.is_test AND r.closed_at<now()-interval '3 days')));
END $$;

-- Τα Κεντρικά ακυρώνουν αίτημα που περιμένει, με υποχρεωτικό λόγο (τον βλέπουν μόνο τα Κεντρικά).
CREATE FUNCTION public.scl374_hq_request_cancel(p_hq_key text, p_id uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r scl_private.mk_request%ROWTYPE; v text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF v IS NULL OR length(v)>300 THEN RAISE EXCEPTION 'MARKET_REQ:reason' USING ERRCODE='22023'; END IF;
 PERFORM scl_private.mk_req_sweep(NULL,NULL);
 SELECT * INTO r FROM scl_private.mk_request WHERE id=p_id FOR UPDATE;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 IF r.status<>'pending' THEN RETURN jsonb_build_object('ok',false,'request',scl_private.mk_req_json(r,'hq')); END IF;
 UPDATE scl_private.mk_request SET status='cancelled',reason='hq',hq_note=v,closed_at=now() WHERE id=r.id RETURNING * INTO r;
 PERFORM scl_private.mk_req_log(r.id,'hq','Κεντρικά Pharmaplus','cancelled',jsonb_build_object('reason','hq','note',v));
 RETURN jsonb_build_object('ok',true,'request',scl_private.mk_req_json(r,'hq'));
END $$;

CREATE FUNCTION public.scl374_hq_request_log(p_hq_key text, p_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r scl_private.mk_request%ROWTYPE;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT * INTO r FROM scl_private.mk_request WHERE id=p_id;
 IF r.id IS NULL THEN RAISE EXCEPTION 'MARKET_REQ:not_found' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('request',scl_private.mk_req_json(r,'hq'),'log',scl_private.mk_req_history(r.id,'hq'));
END $$;

-- «Δοκιμαστική» εταιρία: τα αιτήματά της δεν μετράνε και σβήνονται. Αλλάζει μόνο όσο η εταιρία δεν έχει κανένα αίτημα.
CREATE FUNCTION public.scl374_hq_company_test(p_hq_key text, p_company_id uuid, p_test boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF NOT EXISTS(SELECT 1 FROM scl_private.mk_company WHERE id=p_company_id) THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM scl_private.mk_request WHERE company_id=p_company_id) THEN RAISE EXCEPTION 'MARKET_COMPANY_HAS_REQUESTS' USING ERRCODE='22023'; END IF;
 UPDATE scl_private.mk_company SET is_test=coalesce(p_test,false),updated_at=now() WHERE id=p_company_id;
 RETURN scl_private.mk_company_hq(p_company_id);
END $$;

-- Τα Κεντρικά σβήνουν τα αιτήματα μιας δοκιμαστικής εταιρίας (μετά από δοκιμές).
CREATE FUNCTION public.scl374_hq_test_purge(p_hq_key text, p_company_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE n integer;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF NOT EXISTS(SELECT 1 FROM scl_private.mk_company WHERE id=p_company_id AND is_test) THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_TEST' USING ERRCODE='22023'; END IF;
 DELETE FROM scl_private.mk_request WHERE company_id=p_company_id AND is_test;
 GET DIAGNOSTICS n=ROW_COUNT;
 RETURN jsonb_build_object('deleted',n);
END $$;

-- 6. Νέα έκδοση 2 συναρτήσεων του Κ2.
CREATE OR REPLACE FUNCTION scl_private.mk_company_hq(p_company uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT jsonb_build_object('id',c.id,'name',c.name,'legal_name',c.legal_name,'vat',c.vat,'tax_office',c.tax_office,'address',c.address,
  'billing_email',c.billing_email,'notes',c.notes,'active',c.active,'created_at',c.created_at,
  'person',(SELECT jsonb_build_object('full_name',p.full_name,'email',p.email,'phone',p.phone,'role',p.role)
            FROM scl_private.mk_company_person p WHERE p.company_id=c.id AND p.is_primary),
  'brands',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name) ORDER BY b.name),'[]'::jsonb)
            FROM scl_private.mk_company_brand cb JOIN scl_private.mk_brand b ON b.id=cb.brand_id WHERE cb.company_id=c.id),
  'link',(SELECT a.token FROM scl_private.mk_access a WHERE a.company_id=c.id AND a.person_id IS NULL AND a.revoked_at IS NULL ORDER BY a.created_at DESC LIMIT 1),
  'is_test',c.is_test,'requests',(SELECT count(*) FROM scl_private.mk_request r WHERE r.company_id=c.id))
 FROM scl_private.mk_company c WHERE c.id=p_company $$;

-- Διαγραφή εταιρίας: όχι αν έχει πραγματικά αιτήματα (τότε μόνο «Ανενεργή»). Τα δοκιμαστικά αιτήματα σβήνονται μαζί της.
CREATE OR REPLACE FUNCTION public.scl371_hq_company_delete(p_hq_key text, p_company_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE rid uuid;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT request_id INTO rid FROM scl_private.mk_company WHERE id=p_company_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM scl_private.mk_request WHERE company_id=p_company_id AND NOT is_test) THEN RAISE EXCEPTION 'MARKET_COMPANY_HAS_REQUESTS' USING ERRCODE='22023'; END IF;
 DELETE FROM scl_private.mk_request WHERE company_id=p_company_id;
 DELETE FROM scl_private.mk_access WHERE company_id=p_company_id;
 DELETE FROM scl_private.mk_company_brand WHERE company_id=p_company_id;
 DELETE FROM scl_private.mk_company_person WHERE company_id=p_company_id;
 DELETE FROM scl_private.mk_company WHERE id=p_company_id;
 UPDATE scl_private.mk_info_request SET status='new',handled_at=NULL WHERE id=rid AND status='done';
 RETURN jsonb_build_object('ok',true);
END $$;

REVOKE ALL ON FUNCTION scl_private.mk_req_label(integer,timestamptz),scl_private.mk_req_block(uuid,text,integer,integer[]),scl_private.mk_req_log(uuid,text,text,text,jsonb),
 scl_private.mk_req_sweep(uuid,uuid),scl_private.mk_req_json(scl_private.mk_request,text),scl_private.mk_req_history(uuid,text),scl_private.mk_ints(jsonb,integer),scl_private.mk_strs(jsonb,integer),scl_private.mk_shelves(jsonb,text),scl_private.mk_shelf_spec(text),scl_private.mk_plan_list(uuid),scl_private.mk_terms_items(text,integer,boolean) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.scl374_mk_request_send(text,jsonb),public.scl374_mk_requests(text),public.scl374_mk_requests_seen(text),public.scl374_mk_request_withdraw(text,uuid),
 public.scl374_mk_request_log(text,uuid),public.scl374_ph_requests(text,boolean),public.scl374_ph_request_decline(text,uuid,text,text),public.scl374_ph_request_log(text,uuid),
 public.scl374_hq_requests(text),public.scl374_hq_request_cancel(text,uuid,text),public.scl374_hq_request_log(text,uuid),public.scl374_hq_company_test(text,uuid,boolean),
 public.scl374_hq_test_purge(text,uuid),public.scl374_mk_terms(text),public.scl374_mk_planograms(text),public.scl374_mk_planogram_save(text,jsonb),public.scl374_mk_planogram_delete(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl374_mk_request_send(text,jsonb),public.scl374_mk_requests(text),public.scl374_mk_requests_seen(text),public.scl374_mk_request_withdraw(text,uuid),
 public.scl374_mk_request_log(text,uuid),public.scl374_ph_requests(text,boolean),public.scl374_ph_request_decline(text,uuid,text,text),public.scl374_ph_request_log(text,uuid),
 public.scl374_hq_requests(text),public.scl374_hq_request_cancel(text,uuid,text),public.scl374_hq_request_log(text,uuid),public.scl374_hq_company_test(text,uuid,boolean),
 public.scl374_hq_test_purge(text,uuid),public.scl374_mk_terms(text),public.scl374_mk_planograms(text),public.scl374_mk_planogram_save(text,jsonb),public.scl374_mk_planogram_delete(text,uuid) TO anon,authenticated;
