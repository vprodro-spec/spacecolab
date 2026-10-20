-- Apply the HQ pause to the legacy shelf-sponsorship path as well.
CREATE OR REPLACE FUNCTION scl_private.paused_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b jsonb; a jsonb; m integer;
BEGIN
 FOR b IN SELECT value FROM jsonb_array_elements(OLD.state_json->'cards') LOOP
  IF b->>'type'='hq' OR b->>'initialPlanLocked' IS DISTINCT FROM 'true' THEN CONTINUE; END IF;
  SELECT value INTO a FROM jsonb_array_elements(NEW.state_json->'cards') WHERE value->>'id'=b->>'id';
  FOR m IN 0..11 LOOP
   IF nullif(a->>'stopsOn','')::date<=make_date(NEW.year,m+1,1) AND (scl_private.month_signature(b,m) IS DISTINCT FROM scl_private.month_signature(a,m) OR (SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]') FROM jsonb_array_elements(coalesce(b->'sponsoredShelves','[]')) x WHERE (x->>'month')::integer=m) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]') FROM jsonb_array_elements(coalesce(a->'sponsoredShelves','[]')) x WHERE (x->>'month')::integer=m)) THEN RAISE EXCEPTION 'POSITION_PAUSED: Η θέση έχει παύσει για τον επιλεγμένο μήνα'; END IF;
  END LOOP;
 END LOOP;
 RETURN NEW;
END $$;
