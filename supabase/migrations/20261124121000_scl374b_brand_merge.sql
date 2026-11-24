-- scl374b · Ένωση διπλού Brand στο μητρώο του Market: «DR.ALTHEA» (id 949) μέσα στο «DR. ALTHEA» (id 1090).
-- Γίνεται ΠΡΙΝ μπουν αιτήματα, γιατί τα αιτήματα δείχνουν σε Brand. Κανένα από τα δύο δεν ανήκει σε εταιρία (έλεγχος 24/11).
-- Κρατά αντίγραφο σε scl_private.backup_v374_brand_merge. Rollback: 20261124121000_scl374b_brand_merge_rollback.sql
DO $$
BEGIN
 IF (SELECT name FROM scl_private.mk_brand WHERE id=949) IS DISTINCT FROM 'DR.ALTHEA' OR (SELECT name FROM scl_private.mk_brand WHERE id=1090) IS DISTINCT FROM 'DR. ALTHEA' THEN RAISE EXCEPTION 'Τα Brands 949/1090 δεν είναι αυτά που περιμένω'; END IF;
 IF EXISTS(SELECT 1 FROM scl_private.mk_company_brand WHERE brand_id IN (949,1090)) THEN RAISE EXCEPTION 'Κάποιο από τα δύο Brands ανήκει πια σε εταιρία· θέλει ξανά έλεγχο'; END IF;
 IF EXISTS(SELECT 1 FROM scl_private.mk_brand_scope a JOIN scl_private.mk_brand_scope b ON a.brand_id=949 AND b.brand_id=1090 AND a.category_id=b.category_id AND a.subcategory_id IS NOT DISTINCT FROM b.subcategory_id) THEN RAISE EXCEPTION 'Κοινή κατηγορία/υποκατηγορία στα δύο Brands· θέλει ξανά έλεγχο'; END IF;
END $$;
CREATE TABLE scl_private.backup_v374_brand_merge AS
 SELECT 'brand'::text AS kind, to_jsonb(b) AS j FROM scl_private.mk_brand b WHERE b.id IN (949,1090)
 UNION ALL SELECT 'scope', to_jsonb(s) FROM scl_private.mk_brand_scope s WHERE s.brand_id IN (949,1090);
ALTER TABLE scl_private.backup_v374_brand_merge ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON scl_private.backup_v374_brand_merge FROM PUBLIC,anon,authenticated;
UPDATE scl_private.mk_brand_scope SET brand_id=1090 WHERE brand_id=949;
DELETE FROM scl_private.mk_brand WHERE id=949;
-- Το «φαρμακεία» του Brand μένει 7 (το μεγαλύτερο από τα δύο): δεν ξέρουμε πόσα φαρμακεία είναι κοινά, άρα δεν τα προσθέτουμε.
