-- scl351: τα έπιπλα της κάτοψης δέχονται και «σημεία εξυπηρέτησης» (kind = 'service': ζυγαριά, θέση αναμονής, μέτρηση πίεσης),
-- όπως η βιβλιοθήκη του Design mockup. Μόνο διεύρυνση ενός ελέγχου τιμών στον πίνακα scl_private.fp_items (scl350).
-- Καμία συνάρτηση, κανένας άλλος πίνακας, καμία γραμμή δεν αλλάζει.
-- Rollback: supabase/rollback/20261119130000_scl351_fp_service_rollback.sql
ALTER TABLE scl_private.fp_items DROP CONSTRAINT fp_items_kind_check;
ALTER TABLE scl_private.fp_items ADD CONSTRAINT fp_items_kind_check CHECK (kind IN ('counter','rack','gondola','fridge','column','service'));
