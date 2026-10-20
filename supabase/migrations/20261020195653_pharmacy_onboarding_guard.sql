-- A new local programme can only be finalized after turnover is supplied.
-- Existing programmes, schedules, financial history and installation data are untouched.
CREATE FUNCTION scl_private.onboarding_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE c jsonb; before_card jsonb; turnover numeric;
BEGIN
 FOR c IN SELECT value FROM jsonb_array_elements(NEW.state_json->'cards') LOOP
  IF c->>'type'='hq' OR c->>'initialPlanLocked' IS DISTINCT FROM 'true' THEN CONTINUE; END IF;
  before_card:=NULL;
  IF TG_OP='UPDATE' THEN
   SELECT value INTO before_card FROM jsonb_array_elements(OLD.state_json->'cards') WHERE value->>'id'=c->>'id';
  END IF;
  IF before_card->>'initialPlanLocked'='true' THEN CONTINUE; END IF;
  BEGIN turnover:=coalesce((NEW.state_json->>'turnover')::numeric,0);
  EXCEPTION WHEN invalid_text_representation THEN turnover:=0; END;
  IF turnover<=0 THEN RAISE EXCEPTION 'TURNOVER_REQUIRED: Συμπληρώστε τον ετήσιο τζίρο πριν οριστικοποιήσετε το αρχικό πρόγραμμα'; END IF;
 END LOOP;
 RETURN NEW;
END $$;
CREATE TRIGGER scl295_onboarding_guard BEFORE INSERT OR UPDATE ON public.scl290_snapshots
 FOR EACH ROW EXECUTE FUNCTION scl_private.onboarding_guard();
REVOKE ALL ON FUNCTION scl_private.onboarding_guard() FROM PUBLIC,anon,authenticated;
