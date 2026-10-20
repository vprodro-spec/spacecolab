-- Certification fixes. Keep approved initial submissions possible, but protect
-- already finalized months on every later save, including an aged HQ approval.
CREATE FUNCTION scl_private.month_signature(p_card jsonb,p_month integer) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
WITH deals AS (
 SELECT d FROM jsonb_array_elements(CASE
  WHEN jsonb_array_length(coalesce(p_card->'confirmedDeals','[]'))>0 THEN p_card->'confirmedDeals'
  WHEN p_card->'negotiation'->>'confirmed'='true' THEN jsonb_build_array(p_card->'negotiation') ELSE '[]'::jsonb END) d
 WHERE d->>'confirmed'='true' AND p_month>=coalesce((d->>'startMonth')::integer,0)
 AND p_month<coalesce((d->>'startMonth')::integer,0)+greatest(1,coalesce((d->>'duration')::integer,1))
), values_for_month AS (
 SELECT jsonb_build_object('supplier',coalesce(d->>'supplier',''),'brand',coalesce(d->>'brand',''),
 'subline',coalesce(d->>'subline',''),'products',coalesce(d->>'products',''),
 'price',coalesce((d->>'soldMonthlyPrice')::numeric,0),
 'report',coalesce(d->>'reportMode',CASE WHEN d->>'reportEnabled'='true' THEN 'total' ELSE 'none' END),
 'content',CASE WHEN d->>'monthlyContentChanges' IS DISTINCT FROM 'false' THEN jsonb_build_array(
 coalesce(d->'schedule'->>p_month,''),coalesce(d->'monthlySublines'->>p_month,''),coalesce(d->'monthlyProducts'->>p_month,''),
 coalesce(d->'mechanisms'->>p_month,'Χωρίς μηχανισμό')) ELSE 'null'::jsonb END) v FROM deals
)
SELECT jsonb_build_object(
 'basic',coalesce(p_card->'basicSchedule'->>p_month,''),
 'selection',CASE WHEN p_card->>'simpleConfirmed'='true' THEN coalesce(nullif(p_card->'simpleSchedule'->>p_month,''),p_card->'basicSchedule'->>p_month,'') ELSE coalesce(p_card->'basicSchedule'->>p_month,'') END,
 'mechanism',CASE WHEN p_card->>'simpleConfirmed'='true' THEN coalesce(nullif(p_card->'simpleMechanism'->>p_month,''),'Χωρίς μηχανισμό') ELSE 'Χωρίς μηχανισμό' END,
 'deals',(SELECT coalesce(jsonb_agg(v ORDER BY v::text),'[]') FROM values_for_month));
$$;

CREATE FUNCTION scl_private.deadline_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE before_card jsonb; after_card jsonb; m integer;
BEGIN
 FOR before_card IN SELECT value FROM jsonb_array_elements(OLD.state_json->'cards') LOOP
  IF before_card->>'type'='hq' OR before_card->>'initialPlanLocked' IS DISTINCT FROM 'true' THEN CONTINUE; END IF;
  SELECT value INTO after_card FROM jsonb_array_elements(NEW.state_json->'cards') WHERE value->>'id'=before_card->>'id';
  IF after_card IS NULL THEN CONTINUE; END IF; -- Existing snapshot guard rejects removals.
  FOR m IN 0..11 LOOP
   IF scl_private.today()>scl_private.cutoff(OLD.year,m)
    AND scl_private.month_signature(before_card,m) IS DISTINCT FROM scl_private.month_signature(after_card,m) THEN
    RAISE EXCEPTION 'HISTORY_LOCKED: Η προθεσμία για τον μήνα %/% έχει περάσει. Το αποθηκευμένο πρόγραμμα και οι Συμφωνίες του διατηρούνται.',m+1,OLD.year;
   END IF;
  END LOOP;
 END LOOP;
 RETURN NEW;
END $$;
CREATE TRIGGER scl292_deadline_guard BEFORE UPDATE ON public.scl290_snapshots FOR EACH ROW EXECUTE FUNCTION scl_private.deadline_guard();
REVOKE ALL ON FUNCTION scl_private.month_signature(jsonb,integer),scl_private.deadline_guard() FROM PUBLIC,anon,authenticated;

-- Creation is only reachable through the existing HQ-authorized activation RPC.
-- The SECURITY DEFINER owner can still call create_pharmacy internally.
DO $$ BEGIN
 IF to_regprocedure('public.create_pharmacy(text)') IS NOT NULL THEN
  REVOKE EXECUTE ON FUNCTION public.create_pharmacy(text) FROM PUBLIC,anon,authenticated;
 END IF;
END $$;
