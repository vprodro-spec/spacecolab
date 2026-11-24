-- SCL378 · Κ2γ: ποιος εγκρίνει τη φωτογραφία στησίματος, και η φωτογραφία μέσα στους όρους του Market (έκδοση 2).
--  · Τα Κεντρικά εγκρίνουν ΜΟΝΟ τη θέση Pharmaplus. Το φαρμακείο εγκρίνει όλες τις δικές του θέσεις, όχι τη θέση Pharmaplus.
--  · Όροι Market έκδοση 2: ένας νέος όρος για τη φωτογραφία σε κάθε πλευρά. Η έκδοση 1 μένει όπως είναι.
-- ΑΛΛΑΖΕΙ 2 συναρτήσεις του Κ2γ (scl375_hq_setup_approve, scl375_ph_setup_approve). Αντίγραφο: scl_private.backup_v378_functions. Rollback: …_rollback.sql
BEGIN;
CREATE TABLE scl_private.backup_v378_functions(sig text PRIMARY KEY, def text NOT NULL, at timestamptz NOT NULL DEFAULT now());
ALTER TABLE scl_private.backup_v378_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v378_functions FROM PUBLIC,anon,authenticated;
INSERT INTO scl_private.backup_v378_functions(sig,def) SELECT s, pg_get_functiondef(s::regprocedure) FROM unnest(ARRAY['public.scl375_hq_setup_approve(text,uuid,integer,integer,text,boolean)','public.scl375_ph_setup_approve(text,integer,integer,text,boolean)']) s;

CREATE OR REPLACE FUNCTION public.scl375_hq_setup_approve(p_key text, p_pharmacy_id uuid, p_year int, p_month int, p_position_id text, p_on boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.scl290_assert_hq(p_key);
 IF p_position_id IS DISTINCT FROM 'hq' THEN RAISE EXCEPTION 'Τις φωτογραφίες των συμφωνιών του φαρμακείου τις εγκρίνει το φαρμακείο.' USING ERRCODE='42501'; END IF;
 RETURN scl_private.ph377_approve(p_pharmacy_id,p_year,p_month,p_position_id,p_on,'Κεντρικά');
END $$;
CREATE OR REPLACE FUNCTION public.scl375_ph_setup_approve(p_token text, p_year int, p_month int, p_position_id text, p_on boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE pid uuid := public.scl290_token_id(p_token);
BEGIN
 IF p_position_id = 'hq' THEN RAISE EXCEPTION 'Τη φωτογραφία της θέσης Pharmaplus την εγκρίνει η Pharmaplus.' USING ERRCODE='42501'; END IF;
 RETURN scl_private.ph377_approve(pid,p_year,p_month,p_position_id,p_on,coalesce('Φαρμακείο · '||scl_private.ph375_actor(),'Φαρμακείο'));
END $$;

DO $do$ BEGIN
 IF (SELECT max(version) FROM scl_private.mk_terms)<>1 OR (SELECT jsonb_array_length(items) FROM scl_private.mk_terms WHERE side='company' AND version=1)<>7 OR (SELECT jsonb_array_length(items) FROM scl_private.mk_terms WHERE side='pharmacy' AND version=1)<>6 THEN
  RAISE EXCEPTION 'SCL378: οι όροι δεν είναι στην έκδοση 1 που περιμένω'; END IF;
END $do$;
INSERT INTO scl_private.mk_terms(side,version,items)
SELECT 'company',2,(SELECT jsonb_agg(e ORDER BY o) FROM (
  SELECT e,o::numeric FROM jsonb_array_elements(t.items) WITH ORDINALITY x(e,o)
  UNION ALL SELECT jsonb_build_object('t','Το φαρμακείο ανεβάζει φωτογραφία του στησίματος για κάθε μήνα προβολής. Η φωτογραφία είναι μέρος της συμφωνίας και το αποδεικτικό ότι η προβολή στήθηκε. Τη βλέπετε εδώ μόλις την εγκρίνει το φαρμακείο.'),5.5) q)
 FROM scl_private.mk_terms t WHERE t.side='company' AND t.version=1
UNION ALL
SELECT 'pharmacy',2,(SELECT jsonb_agg(e ORDER BY o) FROM (
  SELECT e,o::numeric FROM jsonb_array_elements(t.items) WITH ORDINALITY x(e,o)
  UNION ALL SELECT jsonb_build_object('t','Για κάθε μήνα προβολής ανεβάζεις φωτογραφία του στησίματος: από κοντά, μόνο η οθόνη και τα ράφια της. Η φωτογραφία είναι μέρος της συμφωνίας. Την ελέγχεις και την εγκρίνεις εσύ, και τότε τη βλέπει η εταιρία. Αν δεν ανεβάσεις φωτογραφία, η εταιρία μπορεί να τη ζητήσει πριν πληρώσει.'),4.5) q)
 FROM scl_private.mk_terms t WHERE t.side='pharmacy' AND t.version=1;
COMMIT;
