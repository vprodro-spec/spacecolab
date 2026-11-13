-- v331.4 «Βιτρίνα όπως οι οθόνες»: προσυμφωνία και οριστική συμφωνία.
-- Κανόνας: η προσυμφωνία (status 'discussion') ΔΕΝ δεσμεύει τον μήνα· μόνο η οριστική συμφωνία (status 'closed') τον δεσμεύει.
--  • Πολλές προσυμφωνίες επιτρέπονται στην ίδια θέση και στο ίδιο διάστημα.
--  • Δύο οριστικές συμφωνίες δεν επικαλύπτονται.
--  • Νέα προσυμφωνία δεν γίνεται πάνω σε μήνα που έχει ήδη οριστική συμφωνία.
--  • Η οριστική συμφωνία γράφεται και πάνω από υπάρχουσες προσυμφωνίες (αυτές μένουν, το φαρμακείο τις σβήνει όποτε θέλει).
-- Αλλαγές: (1) νέος κανόνας στην scl330_vitrina_add_booking (ίδια υπογραφή), (2) ΝΕΑ συνάρτηση scl331_vitrina_update_booking
-- για αλλαγή στοιχείων και μετατροπή προσυμφωνίας σε οριστική συμφωνία. Κανένας πίνακας, καμία γραμμή και καμία άλλη συνάρτηση δεν αλλάζει.

-- 1. Προσθήκη: μόνο οριστική συμφωνία δημιουργεί σύγκρουση.
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
 IF p_status IS NULL OR p_status NOT IN ('discussion','closed') THEN RAISE EXCEPTION 'Μη έγκυρη κατάσταση συμφωνίας';END IF;
 IF p_amount IS NOT NULL AND (p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<0 OR p_amount<>round(p_amount,2) OR p_amount>=10000000000) THEN RAISE EXCEPTION 'Το ποσό πρέπει να είναι αριθμός με έως δύο δεκαδικά';END IF;
 IF NOT scl_private.vitrina_period_ok(p_start,p_end) THEN RAISE EXCEPTION 'Η συμφωνία γίνεται για ολόκληρους μήνες ή ολόκληρες εβδομάδες (Δευτέρα έως Κυριακή)';END IF;
 SELECT k.brand,k.start_on,k.end_on INTO clash FROM scl_private.vitrina_bookings k WHERE k.pharmacy_id=pid AND k.facade_no=p_facade_no AND k.position_id=p_position_id AND k.status='closed' AND k.start_on<=p_end AND k.end_on>=p_start ORDER BY k.start_on LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Η θέση έχει ήδη οριστική συμφωνία (%) στο διάστημα που διαλέξατε',clash.brand;END IF;
 IF (SELECT count(*) FROM scl_private.vitrina_bookings WHERE pharmacy_id=pid)>=1000 THEN RAISE EXCEPTION 'Έχετε φτάσει το όριο των 1000 συμφωνιών';END IF;
 INSERT INTO scl_private.vitrina_bookings(pharmacy_id,facade_no,position_id,brand,start_on,end_on,status,amount,note) VALUES(pid,p_facade_no,p_position_id,b,p_start,p_end,p_status,p_amount,n);
 RETURN scl_private.vitrina_state(pid);
END $function$;

-- 2. Αλλαγή στοιχείων και μετατροπή προσυμφωνίας σε οριστική συμφωνία.
-- Η θέση και η όψη δεν αλλάζουν. Η οριστική δεν γυρίζει σε προσυμφωνία (σβήνεται και γράφεται νέα προσυμφωνία).
CREATE OR REPLACE FUNCTION public.scl331_vitrina_update_booking(p_token text, p_booking_id uuid, p_brand text, p_start date, p_end date, p_status text, p_amount numeric, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token);cur scl_private.vitrina_bookings;b text:=btrim(coalesce(p_brand,''));n text:=btrim(coalesce(p_note,''));clash record;
BEGIN
 PERFORM scl_private.vitrina_lock(pid);
 SELECT k.* INTO cur FROM scl_private.vitrina_bookings k WHERE k.id=p_booking_id AND k.pharmacy_id=pid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Η συμφωνία δεν βρέθηκε. Ανανεώστε τη σελίδα.';END IF;
 IF length(b) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Γράψτε τον προμηθευτή ή τη μάρκα (έως 80 χαρακτήρες)';END IF;
 IF length(n)>300 THEN RAISE EXCEPTION 'Η σημείωση δεν μπορεί να ξεπερνά τους 300 χαρακτήρες';END IF;
 IF p_status IS NULL OR p_status NOT IN ('discussion','closed') THEN RAISE EXCEPTION 'Μη έγκυρη κατάσταση συμφωνίας';END IF;
 IF cur.status='closed' AND p_status='discussion' THEN RAISE EXCEPTION 'Η οριστική συμφωνία δεν γίνεται ξανά προσυμφωνία. Διαγράψτε την και καταχωρίστε νέα προσυμφωνία.';END IF;
 IF p_amount IS NOT NULL AND (p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<0 OR p_amount<>round(p_amount,2) OR p_amount>=10000000000) THEN RAISE EXCEPTION 'Το ποσό πρέπει να είναι αριθμός με έως δύο δεκαδικά';END IF;
 IF NOT scl_private.vitrina_period_ok(p_start,p_end) THEN RAISE EXCEPTION 'Η συμφωνία γίνεται για ολόκληρους μήνες ή ολόκληρες εβδομάδες (Δευτέρα έως Κυριακή)';END IF;
 -- Έλεγχος σύγκρουσης με ΑΛΛΗ οριστική συμφωνία. Προσυμφωνία που μένει προσυμφωνία με ίδιο διάστημα (αλλαγή μόνο ποσού/σημείωσης/προμηθευτή) δεν ελέγχεται.
 IF NOT (cur.status='discussion' AND p_status='discussion' AND p_start=cur.start_on AND p_end=cur.end_on) THEN
  SELECT k.brand,k.start_on,k.end_on INTO clash FROM scl_private.vitrina_bookings k WHERE k.pharmacy_id=pid AND k.facade_no=cur.facade_no AND k.position_id=cur.position_id AND k.id<>cur.id AND k.status='closed' AND k.start_on<=p_end AND k.end_on>=p_start ORDER BY k.start_on LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'Η θέση έχει ήδη οριστική συμφωνία (%) στο διάστημα που διαλέξατε',clash.brand;END IF;
 END IF;
 UPDATE scl_private.vitrina_bookings SET brand=b,start_on=p_start,end_on=p_end,status=p_status,amount=p_amount,note=n WHERE id=cur.id;
 RETURN scl_private.vitrina_state(pid);
END $function$;

REVOKE ALL ON FUNCTION public.scl331_vitrina_update_booking(text,uuid,text,date,date,text,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl331_vitrina_update_booking(text,uuid,text,date,date,text,numeric,text) TO anon,authenticated;
