-- scl361 · SpaceCoLLab Market: όλα τα φαρμακεία του δικτύου ως ανώνυμες κουκκίδες στον χάρτη.
-- ΜΟΝΟ ΠΡΟΣΘΗΚΕΣ: (1) συντεταγμένες κατά προσέγγιση για φαρμακεία του μητρώου χωρίς οθόνες, (2) μία νέα συνάρτηση.
-- Καμία υπάρχουσα συνάρτηση ή πίνακας δεν αλλάζει. Η συνάρτηση δεν επιστρέφει όνομα, διεύθυνση ή κωδικό· μόνο σημείο, στρογγυλεμένο στα ~100 μ.
-- (1) Οι συντεταγμένες (δεδομένα) δεν μπαίνουν στο δημόσιο repo. Μπήκαν στον πίνακα scl_private.mk_pharmacy με geo_source 'scl361 · κατά προσέγγιση (mockup)'.


CREATE OR REPLACE FUNCTION public.scl361_mk_dots(p_key text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
BEGIN
 PERFORM scl_private.mk_access_id(p_key);
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('lat',round(g.lat::numeric,3),'lng',round(g.lng::numeric,3)) ORDER BY g.lat,g.lng)
  FROM public.scl290_registry r JOIN scl_private.mk_pharmacy g ON g.registry_id=r.id
  WHERE g.lat IS NOT NULL AND g.lng IS NOT NULL
    AND (r.pharmacy_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.scl290_installations i WHERE i.pharmacy_id=r.pharmacy_id))),'[]'::jsonb);
END $function$;
REVOKE ALL ON FUNCTION public.scl361_mk_dots(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scl361_mk_dots(text) TO anon, authenticated;
