-- Rollback για scl351: ξανά ο αρχικός έλεγχος (χωρίς 'service').
-- Αν έχουν ήδη αποθηκευτεί σημεία εξυπηρέτησης, ο έλεγχος αποτυγχάνει και ΤΙΠΟΤΑ δεν αλλάζει (η συναλλαγή γυρίζει πίσω).
-- Δείτε πρώτα: SELECT count(*) FROM scl_private.fp_items WHERE kind='service';
BEGIN;
ALTER TABLE scl_private.fp_items DROP CONSTRAINT fp_items_kind_check;
ALTER TABLE scl_private.fp_items ADD CONSTRAINT fp_items_kind_check CHECK (kind IN ('counter','rack','gondola','fridge','column'));
COMMIT;
