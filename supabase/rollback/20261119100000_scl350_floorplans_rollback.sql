-- Rollback για scl350: σβήνει ΜΟΝΟ ό,τι δημιούργησε η migration 20261119100000_scl350_floorplans.
-- Δεν αγγίζει καμία υπάρχουσα συνάρτηση ή πίνακα. Ο πίνακας scl_private.backup_v350_functions μένει ως αντίγραφο.
-- ΠΡΟΣΟΧΗ: διαγράφονται και ΟΛΕΣ οι αποθηκευμένες κατόψεις με όλες τις εκδόσεις τους.
-- Αν υπάρχουν κατόψεις, πάρτε πρώτα αντίγραφο:
--   SELECT jsonb_object_agg(registry_id::text||'#'||version_no, scl_private.fp_plan(id)) FROM scl_private.fp_versions;
DROP FUNCTION IF EXISTS
 public.scl350_hq_fp_get(text,uuid,integer),
 public.scl350_hq_fp_save(text,uuid,integer,jsonb,text),
 public.scl350_hq_fp_overview(text),
 public.scl350_hq_fp_get_many(text,uuid[]),
 public.scl350_fp_get(text);
DROP FUNCTION IF EXISTS
 scl_private.fp_save(uuid,integer,jsonb,text,text),
 scl_private.fp_versions_list(uuid),
 scl_private.fp_plan(uuid),
 scl_private.fp_num(jsonb,text,text);
DROP TABLE IF EXISTS
 scl_private.fp_positions,
 scl_private.fp_items,
 scl_private.fp_openings,
 scl_private.fp_versions;
