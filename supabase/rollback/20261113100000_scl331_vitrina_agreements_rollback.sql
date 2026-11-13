-- Αναίρεση του v331.4: επαναφέρει τον ΠΑΛΙΟ κανόνα (καμία επικάλυψη, ούτε προσυμφωνίες) και σβήνει τη νέα συνάρτηση.
-- Δεν αγγίζει δεδομένα. Προσοχή: αν στο μεταξύ έχουν γραφτεί επικαλυπτόμενες προσυμφωνίες, μένουν ως έχουν.
DROP FUNCTION IF EXISTS public.scl331_vitrina_update_booking(text,uuid,text,date,date,text,numeric,text);

CREATE OR REPLACE FUNCTION public.scl330_vitrina_add_booking(p_token text, p_facade_no integer, p_position_id text, p_brand text, p_start date, p_end date, p_status text, p_amount numeric, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token);dsg jsonb;b text:=btrim(coalesce(p_brand,''));n text:=btrim(coalesce(p_note,''));clash record;
BEGIN
 PERFORM scl_private.vitrina_lock(pid);
 SELECT f.design INTO dsg FROM scl_private.vitrina_facades f WHERE f.pharmacy_id=pid AND f.facade_no=p_facade_no;
 IF NOT FOUND THEN RAISE EXCEPTION 'Η όψη δεν υπάρχει. Ανανεώστε τη σελίδα.';END IF;
 IF p_position_id IS NULL OR NOT (p_position_id=ANY(scl_private.vitrina_position_ids(dsg))) THEN RAISE EXCEPTION 'Η θέση δεν υπάρχει πια στην όψη. Ανανεώστε τη σελίδα.';END IF;
 IF length(b) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Γράψτε τον προμηθευτή ή τη μάρκα (έως 80 χαρακτήρες)';END IF;
 IF length(n)>300 THEN RAISE EXCEPTION 'Η σημείωση δεν μπορεί να ξεπερνά τους 300 χαρακτήρες';END IF;
 IF p_status IS NULL OR p_status NOT IN ('discussion','closed') THEN RAISE EXCEPTION 'Μη έγκυρη κατάσταση κράτησης';END IF;
 IF p_amount IS NOT NULL AND (p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<0 OR p_amount<>round(p_amount,2) OR p_amount>=10000000000) THEN RAISE EXCEPTION 'Το ποσό πρέπει να είναι αριθμός με έως δύο δεκαδικά';END IF;
 IF NOT scl_private.vitrina_period_ok(p_start,p_end) THEN RAISE EXCEPTION 'Η κράτηση γίνεται για ολόκληρους μήνες ή ολόκληρες εβδομάδες (Δευτέρα έως Κυριακή)';END IF;
 SELECT k.brand,k.start_on,k.end_on INTO clash FROM scl_private.vitrina_bookings k WHERE k.pharmacy_id=pid AND k.facade_no=p_facade_no AND k.position_id=p_position_id AND k.start_on<=p_end AND k.end_on>=p_start ORDER BY k.start_on LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Η θέση έχει ήδη κράτηση (%) στο διάστημα που διαλέξατε',clash.brand;END IF;
 IF (SELECT count(*) FROM scl_private.vitrina_bookings WHERE pharmacy_id=pid)>=1000 THEN RAISE EXCEPTION 'Έχετε φτάσει το όριο των 1000 κρατήσεων';END IF;
 INSERT INTO scl_private.vitrina_bookings(pharmacy_id,facade_no,position_id,brand,start_on,end_on,status,amount,note) VALUES(pid,p_facade_no,p_position_id,b,p_start,p_end,p_status,p_amount,n);
 RETURN scl_private.vitrina_state(pid);
END $function$;

-- Αντίγραφο δεδομένων πριν το v331.4 (13/11/2026, μόνο ανάγνωση· η migration δεν τα αλλάζει):
-- vitrina_bookings: 3 γραμμές, vitrina_facades: 1, vitrina_settings: 2
--  c471b210-026f-4bdb-8dcc-5a0af562d39b | όψη 1 | p9.0 | λορεαλ     | 2026-01-01..2026-02-28 | closed     | 9000.00 | σαφσαφασφασ
--  dcc653e8-3446-481c-aa9a-6029b0c9595c | όψη 1 | p3.0 | ξκγηκηγκγηκ | 2026-03-01..2026-03-31 | discussion | null    |
--  9fd9e501-3388-41bd-b145-36c4f98b7767 | όψη 1 | p9.0 | σαασφασφ    | 2027-08-01..2027-08-31 | discussion | null    |
-- scl290_registry: 99 γραμμές (12 legacy, 87 όχι) · pharmacies: 7 · pharmacy_position_months: 180
