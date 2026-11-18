-- Rollback για scl340 (αναθεωρημένο, χωρίς τζίρο override): σβήνει ΜΟΝΟ ό,τι δημιούργησε η migration 20261118190000_scl340_sales_totals.
-- Δεν αγγίζει καμία υπάρχουσα συνάρτηση, πίνακα ή τη στήλη pharmacy_code (αυτή ανήκει στο scl3319).
-- Ο πίνακας scl_private.backup_v340_functions μένει ως αντίγραφο.
-- Προσοχή: διαγράφονται και όλα τα φορτωμένα στοιχεία τζίρου/αποδείξεων BI, οι αλλαγές αποδείξεων και το ιστορικό τους.
DROP FUNCTION IF EXISTS
 public.scl340_sales_get(text,integer),
 public.scl340_sales_save(text,integer,numeric),
 public.scl340_hq_sales_data(text,integer),
 public.scl340_hq_sales_set(text,uuid,integer,numeric),
 public.scl340_hq_sales_settings(text,numeric,boolean),
 public.scl340_hq_set_pharmacy_code(text,uuid,text);
DROP FUNCTION IF EXISTS
 scl_private.sales_import(text,jsonb),
 scl_private.sales_set_receipts(uuid,integer,numeric,text),
 scl_private.sales_effective(uuid,integer),
 scl_private.sales_program_turnover(uuid,integer);
DROP TABLE IF EXISTS
 scl_private.pharmacy_receipts_changes,
 scl_private.pharmacy_receipts_override,
 scl_private.pharmacy_month_totals,
 scl_private.sales_batches,
 scl_private.sales_settings;
