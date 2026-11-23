-- Αναίρεση του scl373. Γυρίζει τις 3 συναρτήσεις (2 του scl370, 1 του scl360) στην προηγούμενη έκδοση (από το backup_v373_functions), κλείνει όσες συνδέσεις
-- ανθρώπων υπάρχουν και σβήνει τα νέα. Εταιρίες, άνθρωποι (ονόματα), Brands και αιτήματα μένουν. Οι κωδικοί χάνονται:
-- μετά την αναίρεση η εταιρία μπαίνει ξανά με σύνδεσμο από τα Κεντρικά.
DROP FUNCTION IF EXISTS public.scl373_hq_person_invite(text,uuid),public.scl373_hq_person_active(text,uuid,boolean),public.scl373_hq_people(text,uuid),
 public.scl373_mk_password(text,text,text),public.scl373_mk_person_active(text,uuid,boolean),public.scl373_mk_person_invite(text,uuid),
 public.scl373_mk_person_add(text,jsonb),public.scl373_mk_people(text),public.scl373_mk_invite_accept(text,text),public.scl373_mk_invite_info(text),
 public.scl373_mk_logout(text),public.scl373_mk_login(text,text),public.scl373_mk_setup(text,jsonb),public.scl373_mk_state(text);
DROP FUNCTION IF EXISTS scl_private.mk_invite_new(uuid,text),scl_private.mk_people_list(uuid),scl_private.mk_person_of(text),scl_private.mk_sessions_close(uuid),
 scl_private.mk_session_open(uuid),scl_private.mk_email_norm(text),scl_private.mk_pw_check(text);
DELETE FROM scl_private.mk_access WHERE person_id IS NOT NULL;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT definition FROM scl_private.backup_v373_functions WHERE (schema_name='scl_private' AND fn IN ('mk_company_hq','mk_access_id')) OR (schema_name='public' AND fn='scl370_hq_company_link') LOOP
  EXECUTE r.definition; END LOOP; END $$;
DROP TABLE IF EXISTS scl_private.mk_people_log,scl_private.mk_session,scl_private.mk_invite,scl_private.mk_person_auth;
DROP TABLE IF EXISTS scl_private.backup_v373_functions;
