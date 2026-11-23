-- scl373: SpaceCoLLab Market, Κ2β «Άνθρωποι εταιρίας» (ζητήθηκε 23/11): κάθε άνθρωπος της εταιρίας μπαίνει με email και δικό του κωδικό.
-- Ο σύνδεσμος που δίνουν τα Κεντρικά γίνεται «σύνδεσμος πρώτης εισόδου» για τον υπεύθυνο. Ο υπεύθυνος προσκαλεί συναδέλφους
-- με σύνδεσμο μίας χρήσης. Καμία αποστολή email από το σύστημα.
-- ΚΩΔΙΚΟΙ: αποθηκεύεται μόνο αποτύπωμα bcrypt (pgcrypto). Καμία συνάρτηση δεν επιστρέφει κωδικό ή αποτύπωμα.
-- ΣΥΝΔΕΣΗ: είναι γραμμή στον mk_access με person_id, άρα όλες οι υπάρχουσες συναρτήσεις του Market (scl360_mk_*, scl361_mk_dots,
-- scl370_mk_me) δουλεύουν όπως είναι. Λήξη 30 ημέρες.
-- ΑΛΛΑΓΕΣ ΣΕ ΥΠΑΡΧΟΝΤΑ (3 συναρτήσεις, καμία στήλη): (α) scl_private.mk_company_hq και public.scl370_hq_company_link του scl370, ώστε ο
-- «σύνδεσμος εταιρίας» των Κεντρικών να μην μπερδεύεται με συνδέσεις ανθρώπων· (β) scl_private.mk_access_id του scl360, που μαθαίνει τη
-- λήξη σύνδεσης (+1 συνθήκη· για συνδέσμους χωρίς λήξη, όπως ο δοκιμαστικός, συμπεριφέρεται ακριβώς όπως πριν).
-- Rollback: supabase/rollback/20261123200000_scl373_market_people_rollback.sql

CREATE TABLE scl_private.backup_v373_functions AS
 SELECT n.nspname::text AS schema_name, p.proname::text AS fn, pg_get_function_identity_arguments(p.oid) AS args,
        pg_get_functiondef(p.oid) AS definition, now() AS taken_at
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','scl_private') AND p.prokind='f';
ALTER TABLE scl_private.backup_v373_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v373_functions FROM PUBLIC,anon,authenticated;

-- 1. Πίνακες (όλοι νέοι).
-- Στοιχεία εισόδου ανά άνθρωπο. Το email είναι μοναδικό σε όλο το Market.
CREATE TABLE scl_private.mk_person_auth(
 person_id uuid PRIMARY KEY REFERENCES scl_private.mk_company_person(id) ON DELETE CASCADE,
 email text NOT NULL UNIQUE CHECK(email=lower(email) AND length(email)<=120),
 pass_hash text,
 active boolean NOT NULL DEFAULT true,
 failed integer NOT NULL DEFAULT 0,
 locked_until timestamptz,
 last_login timestamptz,
 password_set_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now());
-- Πρόσκληση μίας χρήσης (και «ξέχασα τον κωδικό»). Ισχύει 7 ημέρες.
CREATE TABLE scl_private.mk_invite(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 token uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
 person_id uuid NOT NULL REFERENCES scl_private.mk_company_person(id) ON DELETE CASCADE,
 created_by text NOT NULL CHECK(length(created_by) BETWEEN 1 AND 120),
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '7 days',
 used_at timestamptz,
 revoked_at timestamptz);
CREATE INDEX mk_invite_person ON scl_private.mk_invite(person_id);
-- Λήξη σύνδεσης (η σύνδεση είναι γραμμή του mk_access).
CREATE TABLE scl_private.mk_session(
 access_id uuid PRIMARY KEY REFERENCES scl_private.mk_access(id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL);
-- Ιστορικό εισόδων και αλλαγών (μόνο προσθήκες).
CREATE TABLE scl_private.mk_people_log(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 at timestamptz NOT NULL DEFAULT now(),
 company_id uuid,
 person_id uuid,
 actor text NOT NULL,
 action text NOT NULL,
 detail text);
CREATE INDEX mk_people_log_company ON scl_private.mk_people_log(company_id,at DESC);
ALTER TABLE scl_private.mk_person_auth ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_invite ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE scl_private.mk_people_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.mk_person_auth,scl_private.mk_invite,scl_private.mk_session,scl_private.mk_people_log FROM PUBLIC,anon,authenticated;

-- 2. Νέα έκδοση 2 συναρτήσεων του scl370: «σύνδεσμος εταιρίας» = μόνο γραμμές χωρίς άνθρωπο.
CREATE OR REPLACE FUNCTION scl_private.mk_company_hq(p_company uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT jsonb_build_object('id',c.id,'name',c.name,'legal_name',c.legal_name,'vat',c.vat,'tax_office',c.tax_office,'address',c.address,
  'billing_email',c.billing_email,'notes',c.notes,'active',c.active,'created_at',c.created_at,
  'person',(SELECT jsonb_build_object('full_name',p.full_name,'email',p.email,'phone',p.phone,'role',p.role)
            FROM scl_private.mk_company_person p WHERE p.company_id=c.id AND p.is_primary),
  'brands',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name) ORDER BY b.name),'[]'::jsonb)
            FROM scl_private.mk_company_brand cb JOIN scl_private.mk_brand b ON b.id=cb.brand_id WHERE cb.company_id=c.id),
  'link',(SELECT a.token FROM scl_private.mk_access a WHERE a.company_id=c.id AND a.person_id IS NULL AND a.revoked_at IS NULL ORDER BY a.created_at DESC LIMIT 1))
 FROM scl_private.mk_company c WHERE c.id=p_company $$;

CREATE OR REPLACE FUNCTION public.scl370_hq_company_link(p_hq_key text, p_company_id uuid, p_renew boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE c scl_private.mk_company%ROWTYPE;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT * INTO c FROM scl_private.mk_company WHERE id=p_company_id;
 IF c.id IS NULL THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF NOT c.active THEN RAISE EXCEPTION 'MARKET_COMPANY_INACTIVE' USING ERRCODE='22023'; END IF;
 IF coalesce(p_renew,false) THEN UPDATE scl_private.mk_access SET revoked_at=now() WHERE company_id=c.id AND person_id IS NULL AND revoked_at IS NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM scl_private.mk_access WHERE company_id=c.id AND person_id IS NULL AND revoked_at IS NULL) THEN
  INSERT INTO scl_private.mk_access(label,kind,company_id) VALUES(left(c.name,80),'company',c.id); END IF;
 RETURN scl_private.mk_company_hq(c.id);
END $$;

-- Ο έλεγχος κλειδιού του Market (scl360) μαθαίνει τη λήξη σύνδεσης: κλειδί με ληγμένη σύνδεση δεν ισχύει. Τα υπόλοιπα όπως ήταν.
CREATE OR REPLACE FUNCTION scl_private.mk_access_id(p_key text) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE aid uuid;
BEGIN
 IF p_key IS NULL OR p_key !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Μη έγκυρη πρόσβαση Market'; END IF;
 SELECT a.id INTO aid FROM scl_private.mk_access a WHERE a.token=p_key::uuid AND a.revoked_at IS NULL
  AND NOT EXISTS(SELECT 1 FROM scl_private.mk_session s WHERE s.access_id=a.id AND s.expires_at<=now());
 IF aid IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Μη έγκυρη πρόσβαση Market'; END IF;
 RETURN aid;
END $$;

-- 3. Ιδιωτικές συναρτήσεις.
CREATE FUNCTION scl_private.mk_pw_check(p_password text) RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path TO '' AS $$
BEGIN
 IF p_password IS NULL OR length(p_password)<10 THEN RAISE EXCEPTION 'MARKET_AUTH:password_short' USING ERRCODE='22023'; END IF;
 IF octet_length(p_password)>72 THEN RAISE EXCEPTION 'MARKET_AUTH:password_long' USING ERRCODE='22023'; END IF;
END $$;
CREATE FUNCTION scl_private.mk_email_norm(p_email text) RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path TO '' AS $$
DECLARE e text:=lower(btrim(coalesce(p_email,'')));
BEGIN
 IF length(e)>120 OR e !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' THEN RAISE EXCEPTION 'MARKET_AUTH:email' USING ERRCODE='22023'; END IF;
 RETURN e;
END $$;
-- Νέα σύνδεση για άνθρωπο. Επιστρέφει το κλειδί της.
CREATE FUNCTION scl_private.mk_session_open(p_person uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE p scl_private.mk_company_person%ROWTYPE; aid uuid; tok uuid;
BEGIN
 SELECT * INTO p FROM scl_private.mk_company_person WHERE id=p_person;
 INSERT INTO scl_private.mk_access(label,kind,company_id,person_id) VALUES(left(p.full_name,80),'company',p.company_id,p.id) RETURNING id,token INTO aid,tok;
 INSERT INTO scl_private.mk_session(access_id,expires_at) VALUES(aid,now()+interval '30 days');
 UPDATE scl_private.mk_person_auth SET last_login=now(),failed=0,locked_until=NULL WHERE person_id=p.id;
 RETURN tok;
END $$;
CREATE FUNCTION scl_private.mk_sessions_close(p_person uuid) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $$
 UPDATE scl_private.mk_access SET revoked_at=now() WHERE person_id=p_person AND revoked_at IS NULL $$;
-- Ο συνδεδεμένος άνθρωπος. Σφάλμα αν το κλειδί δεν είναι σύνδεση ανθρώπου ενεργής εταιρίας.
CREATE FUNCTION scl_private.mk_person_of(p_key text) RETURNS scl_private.mk_company_person LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a scl_private.mk_access%ROWTYPE; p scl_private.mk_company_person%ROWTYPE;
BEGIN
 SELECT * INTO a FROM scl_private.mk_access WHERE id=scl_private.mk_access_id(p_key);
 IF a.person_id IS NULL THEN RAISE EXCEPTION 'MARKET_AUTH:login_required' USING ERRCODE='42501'; END IF;
 SELECT p2.* INTO p FROM scl_private.mk_company_person p2 JOIN scl_private.mk_company c ON c.id=p2.company_id
  JOIN scl_private.mk_person_auth au ON au.person_id=p2.id WHERE p2.id=a.person_id AND c.active AND au.active;
 IF p.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Μη έγκυρη πρόσβαση Market'; END IF;
 RETURN p;
END $$;
CREATE FUNCTION scl_private.mk_people_list(p_company uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',coalesce(au.email,p.email),'role',p.role,'is_primary',p.is_primary,
   'state',CASE WHEN au.person_id IS NULL THEN 'none' WHEN NOT au.active THEN 'inactive' WHEN au.pass_hash IS NULL THEN 'invited' ELSE 'active' END,
   'last_login',au.last_login,
   'invite_until',(SELECT max(i.expires_at) FROM scl_private.mk_invite i WHERE i.person_id=p.id AND i.used_at IS NULL AND i.revoked_at IS NULL AND i.expires_at>now()))
   ORDER BY NOT p.is_primary,upper(p.full_name)),'[]'::jsonb)
 FROM scl_private.mk_company_person p LEFT JOIN scl_private.mk_person_auth au ON au.person_id=p.id WHERE p.company_id=p_company $$;
-- Νέα πρόσκληση για άνθρωπο· οι παλιές του παύουν.
CREATE FUNCTION scl_private.mk_invite_new(p_person uuid, p_by text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE tok uuid;
BEGIN
 UPDATE scl_private.mk_invite SET revoked_at=now() WHERE person_id=p_person AND used_at IS NULL AND revoked_at IS NULL;
 INSERT INTO scl_private.mk_invite(person_id,created_by) VALUES(p_person,left(p_by,120)) RETURNING token INTO tok;
 RETURN tok;
END $$;

-- 4. Market: είσοδος.
-- Σύνδεσμος πρώτης εισόδου: τι να δείξει η σελίδα. state: 'setup' (ορίστε κωδικό) | 'login' (υπάρχει ήδη υπεύθυνος με κωδικό) | 'session' | 'test'.
CREATE FUNCTION public.scl373_mk_state(p_key text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a scl_private.mk_access%ROWTYPE; c scl_private.mk_company%ROWTYPE; pr scl_private.mk_company_person%ROWTYPE; has boolean;
BEGIN
 SELECT * INTO a FROM scl_private.mk_access WHERE id=scl_private.mk_access_id(p_key);
 IF a.kind='test' THEN RETURN jsonb_build_object('state','test'); END IF;
 SELECT * INTO c FROM scl_private.mk_company WHERE id=a.company_id;
 IF c.id IS NULL OR NOT c.active THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Μη έγκυρη πρόσβαση Market'; END IF;
 IF a.person_id IS NOT NULL THEN
  PERFORM scl_private.mk_person_of(p_key);
  RETURN jsonb_build_object('state','session','is_admin',(SELECT is_primary FROM scl_private.mk_company_person WHERE id=a.person_id));
 END IF;
 SELECT * INTO pr FROM scl_private.mk_company_person WHERE company_id=c.id AND is_primary;
 has:=EXISTS(SELECT 1 FROM scl_private.mk_person_auth au WHERE au.person_id=pr.id AND au.pass_hash IS NOT NULL);
 RETURN jsonb_build_object('state',CASE WHEN has THEN 'login' ELSE 'setup' END,'company',c.name,
  'full_name',CASE WHEN has THEN NULL ELSE pr.full_name END,'email',CASE WHEN has THEN NULL ELSE pr.email END);
END $$;

-- Πρώτη είσοδος υπευθύνου: όνομα, email, κωδικός. Ο σύνδεσμος παύει και επιστρέφεται σύνδεση.
CREATE FUNCTION public.scl373_mk_setup(p_key text, p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a scl_private.mk_access%ROWTYPE; c scl_private.mk_company%ROWTYPE; pid uuid; v_name text:=scl_private.mk_txt(p,'full_name'); v_email text; v_pw text:=p->>'password';
BEGIN
 SELECT * INTO a FROM scl_private.mk_access WHERE id=scl_private.mk_access_id(p_key) FOR UPDATE;
 IF a.kind<>'company' OR a.person_id IS NOT NULL THEN RAISE EXCEPTION 'MARKET_AUTH:not_setup_link' USING ERRCODE='22023'; END IF;
 SELECT * INTO c FROM scl_private.mk_company WHERE id=a.company_id;
 IF c.id IS NULL OR NOT c.active THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Μη έγκυρη πρόσβαση Market'; END IF;
 SELECT id INTO pid FROM scl_private.mk_company_person WHERE company_id=c.id AND is_primary;
 IF EXISTS(SELECT 1 FROM scl_private.mk_person_auth WHERE person_id=pid AND pass_hash IS NOT NULL) THEN RAISE EXCEPTION 'MARKET_AUTH:already_setup' USING ERRCODE='22023'; END IF;
 IF v_name IS NULL OR length(v_name) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'MARKET_AUTH:full_name' USING ERRCODE='22023'; END IF;
 v_email:=scl_private.mk_email_norm(p->>'email');
 PERFORM scl_private.mk_pw_check(v_pw);
 IF EXISTS(SELECT 1 FROM scl_private.mk_person_auth WHERE email=v_email AND person_id IS DISTINCT FROM pid) THEN RAISE EXCEPTION 'MARKET_AUTH:email_taken' USING ERRCODE='23505'; END IF;
 IF pid IS NULL THEN
  INSERT INTO scl_private.mk_company_person(company_id,full_name,email,is_primary) VALUES(c.id,v_name,v_email,true) RETURNING id INTO pid;
 ELSE UPDATE scl_private.mk_company_person SET full_name=v_name,email=v_email WHERE id=pid; END IF;
 INSERT INTO scl_private.mk_person_auth(person_id,email,pass_hash,password_set_at) VALUES(pid,v_email,extensions.crypt(v_pw,extensions.gen_salt('bf',10)),now())
  ON CONFLICT(person_id) DO UPDATE SET email=excluded.email,pass_hash=excluded.pass_hash,password_set_at=now(),active=true,failed=0,locked_until=NULL;
 UPDATE scl_private.mk_access SET revoked_at=now() WHERE company_id=c.id AND person_id IS NULL AND revoked_at IS NULL;
 INSERT INTO scl_private.mk_people_log(company_id,person_id,actor,action) VALUES(c.id,pid,v_name,'setup');
 RETURN jsonb_build_object('key',scl_private.mk_session_open(pid));
END $$;

-- Είσοδος με email και κωδικό. 5 λάθος προσπάθειες = αναμονή 15 λεπτών. Το ίδιο μήνυμα για λάθος email και λάθος κωδικό.
CREATE FUNCTION public.scl373_mk_login(p_email text, p_password text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE au scl_private.mk_person_auth%ROWTYPE; e text:=lower(btrim(coalesce(p_email,''))); ok boolean:=false;
BEGIN
 IF p_password IS NULL OR octet_length(p_password)>72 OR length(e)>120 THEN RETURN jsonb_build_object('ok',false,'error','bad_login'); END IF;
 SELECT x.* INTO au FROM scl_private.mk_person_auth x JOIN scl_private.mk_company_person p ON p.id=x.person_id JOIN scl_private.mk_company c ON c.id=p.company_id
  WHERE x.email=e AND x.active AND c.active AND x.pass_hash IS NOT NULL FOR UPDATE OF x;
 IF au.person_id IS NULL THEN
  PERFORM extensions.crypt(p_password,extensions.gen_salt('bf',10)); -- ίδιος χρόνος και ίδια απάντηση για άγνωστο email
  RETURN jsonb_build_object('ok',false,'error','bad_login');
 END IF;
 IF au.locked_until IS NOT NULL AND au.locked_until>now() THEN RETURN jsonb_build_object('ok',false,'error','locked'); END IF;
 ok:=au.pass_hash=extensions.crypt(p_password,au.pass_hash);
 IF NOT ok THEN
  -- η αποτυχία πρέπει να γραφτεί, άρα δεν πετάμε σφάλμα εδώ: επιστρέφουμε ok=false
  UPDATE scl_private.mk_person_auth SET failed=CASE WHEN failed+1>=5 THEN 0 ELSE failed+1 END,
   locked_until=CASE WHEN failed+1>=5 THEN now()+interval '15 minutes' ELSE locked_until END WHERE person_id=au.person_id;
  RETURN jsonb_build_object('ok',false,'error',CASE WHEN au.failed+1>=5 THEN 'locked' ELSE 'bad_login' END);
 END IF;
 INSERT INTO scl_private.mk_people_log(company_id,person_id,actor,action)
  SELECT p.company_id,p.id,p.full_name,'login' FROM scl_private.mk_company_person p WHERE p.id=au.person_id;
 RETURN jsonb_build_object('ok',true,'key',scl_private.mk_session_open(au.person_id));
END $$;

CREATE FUNCTION public.scl373_mk_logout(p_key text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 UPDATE scl_private.mk_access SET revoked_at=now() WHERE id=scl_private.mk_access_id(p_key) AND person_id IS NOT NULL;
 RETURN jsonb_build_object('ok',true);
END $$;

-- Πρόσκληση: τι να δείξει η σελίδα (χωρίς σύνδεση). Μόνο όνομα εταιρίας, όνομα και email του προσκεκλημένου.
CREATE FUNCTION public.scl373_mk_invite_info(p_token text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'MARKET_AUTH:invite_invalid' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object('company',c.name,'full_name',p.full_name,'email',au.email) INTO r
 FROM scl_private.mk_invite i JOIN scl_private.mk_company_person p ON p.id=i.person_id JOIN scl_private.mk_company c ON c.id=p.company_id
  JOIN scl_private.mk_person_auth au ON au.person_id=p.id
 WHERE i.token=p_token::uuid AND i.used_at IS NULL AND i.revoked_at IS NULL AND i.expires_at>now() AND c.active AND au.active;
 IF r IS NULL THEN RAISE EXCEPTION 'MARKET_AUTH:invite_invalid' USING ERRCODE='42501'; END IF;
 RETURN r;
END $$;

-- Αποδοχή πρόσκλησης: ο άνθρωπος ορίζει τον κωδικό του. Οι παλιές του συνδέσεις κλείνουν.
CREATE FUNCTION public.scl373_mk_invite_accept(p_token text, p_password text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE i scl_private.mk_invite%ROWTYPE; p scl_private.mk_company_person%ROWTYPE;
BEGIN
 PERFORM public.scl373_mk_invite_info(p_token);
 PERFORM scl_private.mk_pw_check(p_password);
 SELECT * INTO i FROM scl_private.mk_invite WHERE token=p_token::uuid FOR UPDATE;
 IF i.used_at IS NOT NULL THEN RAISE EXCEPTION 'MARKET_AUTH:invite_invalid' USING ERRCODE='42501'; END IF;
 SELECT * INTO p FROM scl_private.mk_company_person WHERE id=i.person_id;
 UPDATE scl_private.mk_invite SET used_at=now() WHERE id=i.id;
 UPDATE scl_private.mk_person_auth SET pass_hash=extensions.crypt(p_password,extensions.gen_salt('bf',10)),password_set_at=now(),failed=0,locked_until=NULL WHERE person_id=p.id;
 PERFORM scl_private.mk_sessions_close(p.id);
 INSERT INTO scl_private.mk_people_log(company_id,person_id,actor,action) VALUES(p.company_id,p.id,p.full_name,'password_set');
 RETURN jsonb_build_object('key',scl_private.mk_session_open(p.id));
END $$;

-- 5. Market: οι άνθρωποί μας.
CREATE FUNCTION public.scl373_mk_people(p_key text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key);
BEGIN
 RETURN jsonb_build_object('me',me.id,'is_admin',me.is_primary,'people',scl_private.mk_people_list(me.company_id));
END $$;

-- Ο υπεύθυνος προσθέτει άνθρωπο. Επιστρέφει πρόσκληση μίας χρήσης.
CREATE FUNCTION public.scl373_mk_person_add(p_key text, p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key); v_name text:=scl_private.mk_txt(p,'full_name'); v_role text:=scl_private.mk_txt(p,'role'); v_email text; pid uuid;
BEGIN
 IF NOT me.is_primary THEN RAISE EXCEPTION 'MARKET_AUTH:admin_only' USING ERRCODE='42501'; END IF;
 IF v_name IS NULL OR length(v_name) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'MARKET_AUTH:full_name' USING ERRCODE='22023'; END IF;
 IF v_role IS NOT NULL AND length(v_role)>80 THEN RAISE EXCEPTION 'MARKET_AUTH:role' USING ERRCODE='22023'; END IF;
 v_email:=scl_private.mk_email_norm(p->>'email');
 IF EXISTS(SELECT 1 FROM scl_private.mk_person_auth WHERE email=v_email) THEN RAISE EXCEPTION 'MARKET_AUTH:email_taken' USING ERRCODE='23505'; END IF;
 IF (SELECT count(*) FROM scl_private.mk_company_person WHERE company_id=me.company_id)>=30 THEN RAISE EXCEPTION 'MARKET_AUTH:too_many' USING ERRCODE='22023'; END IF;
 INSERT INTO scl_private.mk_company_person(company_id,full_name,email,role) VALUES(me.company_id,v_name,v_email,v_role) RETURNING id INTO pid;
 INSERT INTO scl_private.mk_person_auth(person_id,email) VALUES(pid,v_email);
 INSERT INTO scl_private.mk_people_log(company_id,person_id,actor,action,detail) VALUES(me.company_id,pid,me.full_name,'person_add',v_name);
 RETURN jsonb_build_object('invite',scl_private.mk_invite_new(pid,me.full_name),'people',scl_private.mk_people_list(me.company_id));
END $$;

-- Νέα πρόσκληση για υπάρχοντα άνθρωπο («ξέχασε τον κωδικό»). Ο παλιός κωδικός ισχύει μέχρι να οριστεί νέος.
CREATE FUNCTION public.scl373_mk_person_invite(p_key text, p_person uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key);
BEGIN
 IF NOT me.is_primary THEN RAISE EXCEPTION 'MARKET_AUTH:admin_only' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM scl_private.mk_company_person p JOIN scl_private.mk_person_auth au ON au.person_id=p.id
   WHERE p.id=p_person AND p.company_id=me.company_id AND au.active) THEN RAISE EXCEPTION 'MARKET_AUTH:person_not_found' USING ERRCODE='P0002'; END IF;
 INSERT INTO scl_private.mk_people_log(company_id,person_id,actor,action) VALUES(me.company_id,p_person,me.full_name,'invite');
 RETURN jsonb_build_object('invite',scl_private.mk_invite_new(p_person,me.full_name),'people',scl_private.mk_people_list(me.company_id));
END $$;

-- Απενεργοποίηση / επανενεργοποίηση ανθρώπου από τον υπεύθυνο. Όχι τον εαυτό του.
CREATE FUNCTION public.scl373_mk_person_active(p_key text, p_person uuid, p_active boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key);
BEGIN
 IF NOT me.is_primary THEN RAISE EXCEPTION 'MARKET_AUTH:admin_only' USING ERRCODE='42501'; END IF;
 IF p_person=me.id THEN RAISE EXCEPTION 'MARKET_AUTH:not_self' USING ERRCODE='22023'; END IF;
 UPDATE scl_private.mk_person_auth au SET active=coalesce(p_active,false) FROM scl_private.mk_company_person p
  WHERE p.id=au.person_id AND p.id=p_person AND p.company_id=me.company_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'MARKET_AUTH:person_not_found' USING ERRCODE='P0002'; END IF;
 IF NOT coalesce(p_active,false) THEN
  PERFORM scl_private.mk_sessions_close(p_person);
  UPDATE scl_private.mk_invite SET revoked_at=now() WHERE person_id=p_person AND used_at IS NULL AND revoked_at IS NULL;
 END IF;
 INSERT INTO scl_private.mk_people_log(company_id,person_id,actor,action) VALUES(me.company_id,p_person,me.full_name,CASE WHEN coalesce(p_active,false) THEN 'activate' ELSE 'deactivate' END);
 RETURN jsonb_build_object('people',scl_private.mk_people_list(me.company_id));
END $$;

-- Αλλαγή του δικού μου κωδικού. Οι άλλες συνδέσεις μου κλείνουν.
CREATE FUNCTION public.scl373_mk_password(p_key text, p_old text, p_new text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE me scl_private.mk_company_person:=scl_private.mk_person_of(p_key); h text;
BEGIN
 SELECT pass_hash INTO h FROM scl_private.mk_person_auth WHERE person_id=me.id FOR UPDATE;
 IF p_old IS NULL OR octet_length(p_old)>72 OR h IS NULL OR h<>extensions.crypt(p_old,h) THEN RETURN jsonb_build_object('ok',false,'error','bad_password'); END IF;
 PERFORM scl_private.mk_pw_check(p_new);
 UPDATE scl_private.mk_person_auth SET pass_hash=extensions.crypt(p_new,extensions.gen_salt('bf',10)),password_set_at=now() WHERE person_id=me.id;
 UPDATE scl_private.mk_access SET revoked_at=now() WHERE person_id=me.id AND revoked_at IS NULL AND token<>p_key::uuid;
 INSERT INTO scl_private.mk_people_log(company_id,person_id,actor,action) VALUES(me.company_id,me.id,me.full_name,'password_change');
 RETURN jsonb_build_object('ok',true);
END $$;

-- 6. Κεντρικά.
CREATE FUNCTION public.scl373_hq_people(p_hq_key text, p_company_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 IF NOT EXISTS(SELECT 1 FROM scl_private.mk_company WHERE id=p_company_id) THEN RAISE EXCEPTION 'MARKET_COMPANY_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('people',scl_private.mk_people_list(p_company_id));
END $$;
-- Τα Κεντρικά απενεργοποιούν / ενεργοποιούν οποιονδήποτε.
CREATE FUNCTION public.scl373_hq_person_active(p_hq_key text, p_person uuid, p_active boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE cid uuid;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 UPDATE scl_private.mk_person_auth au SET active=coalesce(p_active,false) FROM scl_private.mk_company_person p WHERE p.id=au.person_id AND p.id=p_person RETURNING p.company_id INTO cid;
 IF cid IS NULL THEN RAISE EXCEPTION 'MARKET_AUTH:person_not_found' USING ERRCODE='P0002'; END IF;
 IF NOT coalesce(p_active,false) THEN
  PERFORM scl_private.mk_sessions_close(p_person);
  UPDATE scl_private.mk_invite SET revoked_at=now() WHERE person_id=p_person AND used_at IS NULL AND revoked_at IS NULL;
 END IF;
 INSERT INTO scl_private.mk_people_log(company_id,person_id,actor,action) VALUES(cid,p_person,'Κεντρικά',CASE WHEN coalesce(p_active,false) THEN 'activate' ELSE 'deactivate' END);
 RETURN jsonb_build_object('people',scl_private.mk_people_list(cid));
END $$;
-- Τα Κεντρικά βγάζουν νέα πρόσκληση για άνθρωπο (π.χ. ο υπεύθυνος ξέχασε τον κωδικό του).
CREATE FUNCTION public.scl373_hq_person_invite(p_hq_key text, p_person uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE cid uuid;
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 SELECT p.company_id INTO cid FROM scl_private.mk_company_person p JOIN scl_private.mk_person_auth au ON au.person_id=p.id JOIN scl_private.mk_company c ON c.id=p.company_id
  WHERE p.id=p_person AND au.active AND c.active;
 IF cid IS NULL THEN RAISE EXCEPTION 'MARKET_AUTH:person_not_found' USING ERRCODE='P0002'; END IF;
 INSERT INTO scl_private.mk_people_log(company_id,person_id,actor,action) VALUES(cid,p_person,'Κεντρικά','invite');
 RETURN jsonb_build_object('invite',scl_private.mk_invite_new(p_person,'Κεντρικά'),'people',scl_private.mk_people_list(cid));
END $$;

REVOKE ALL ON FUNCTION scl_private.mk_pw_check(text),scl_private.mk_email_norm(text),scl_private.mk_session_open(uuid),
 scl_private.mk_sessions_close(uuid),scl_private.mk_person_of(text),scl_private.mk_people_list(uuid),scl_private.mk_invite_new(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.scl373_mk_state(text),public.scl373_mk_setup(text,jsonb),public.scl373_mk_login(text,text),public.scl373_mk_logout(text),
 public.scl373_mk_invite_info(text),public.scl373_mk_invite_accept(text,text),public.scl373_mk_people(text),public.scl373_mk_person_add(text,jsonb),
 public.scl373_mk_person_invite(text,uuid),public.scl373_mk_person_active(text,uuid,boolean),public.scl373_mk_password(text,text,text),
 public.scl373_hq_people(text,uuid),public.scl373_hq_person_active(text,uuid,boolean),public.scl373_hq_person_invite(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl373_mk_state(text),public.scl373_mk_setup(text,jsonb),public.scl373_mk_login(text,text),public.scl373_mk_logout(text),
 public.scl373_mk_invite_info(text),public.scl373_mk_invite_accept(text,text),public.scl373_mk_people(text),public.scl373_mk_person_add(text,jsonb),
 public.scl373_mk_person_invite(text,uuid),public.scl373_mk_person_active(text,uuid,boolean),public.scl373_mk_password(text,text,text),
 public.scl373_hq_people(text,uuid),public.scl373_hq_person_active(text,uuid,boolean),public.scl373_hq_person_invite(text,uuid) TO anon,authenticated;
