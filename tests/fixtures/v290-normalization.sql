-- Existing v290 normalization functions; no credentials or pharmacy data.
CREATE OR REPLACE FUNCTION public.scl290_merge_state(p_pid uuid,p_year integer,p_state jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE cfg public.scl290_installations; pos jsonb; card jsonb; result jsonb:='[]'; st jsonb:=coalesce(p_state,'{}'); fmt text;
BEGIN
  SELECT * INTO cfg FROM public.scl290_installations WHERE pharmacy_id=p_pid;
  IF NOT FOUND THEN RETURN st; END IF;
  FOR pos IN SELECT value FROM jsonb_array_elements(cfg.positions) LOOP
    IF nullif(pos->>'startsOn','')::date > make_date(p_year,12,31) THEN CONTINUE; END IF;
    SELECT value INTO card FROM jsonb_array_elements(coalesce(st->'cards','[]')) WHERE value->>'id'=pos->>'id' LIMIT 1;
    card:=coalesce(card,jsonb_build_object('initialPlanLocked',pos->>'type'='hq','basicSchedule','[]'::jsonb,
      'simpleSchedule','[]'::jsonb,'pendingSimpleSchedule','[]'::jsonb,'pendingInitialSchedule','[]'::jsonb,
      'confirmedDeals','[]'::jsonb,'preagreements','[]'::jsonb,'sponsoredShelves','[]'::jsonb));
    -- Preserve historical years' existing format. Installation is authoritative from its setup year.
    fmt:=pos->>'screenFormat';
    IF p_year < coalesce((pos->>'configuredYear')::integer,p_year) AND nullif(card->>'screenFormat','') IS NOT NULL THEN fmt:=card->>'screenFormat'; END IF;
    card:=card||jsonb_build_object('id',pos->>'id','type',pos->>'type','title',pos->>'title',
      'screenFormat',fmt,'pendingScreenFormat',fmt,'playerCode',pos->>'playerCode','contentCode',pos->>'contentCode',
      'installationStart',pos->'startsOn','installationManaged',true);
    result:=result||jsonb_build_array(card);
  END LOOP;
  RETURN st||jsonb_build_object('cards',result,'totalCounters',jsonb_array_length(result),'setupLocked',true,
    '_scl290InstallationVersion',cfg.version,'_scl290ServiceFrom',cfg.service_from);
END $$;

CREATE OR REPLACE FUNCTION public.scl290_clean_months(p_pid uuid,p_year integer,p_state jsonb,p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE row jsonb; card jsonb; result jsonb:='[]'; m integer; nm text;
BEGIN
  SELECT name INTO nm FROM public.scl290_registry WHERE pharmacy_id=p_pid;
  FOR row IN SELECT value FROM jsonb_array_elements(coalesce(p_rows,'[]')) LOOP
    m:=(row->>'month')::integer;
    IF m NOT BETWEEN 0 AND 11 THEN CONTINUE; END IF;
    SELECT value INTO card FROM jsonb_array_elements(coalesce(p_state->'cards','[]'))
      WHERE value->>'id'=row->>'position_id' OR (value->>'type'='hq' AND row->>'position_id'='pharmaplus') LIMIT 1;
    IF card IS NULL OR (card->>'type'<>'hq' AND coalesce((card->>'initialPlanLocked')::boolean,false)=false) THEN CONTINUE; END IF;
    IF nullif(card->>'installationStart','')::date > make_date(p_year,m+1,1) THEN CONTINUE; END IF;
    result:=result||jsonb_build_array(row||jsonb_build_object('pharmacy_id',p_pid,'pharmacy_name',nm,'year',p_year,
      'position_id',card->>'id','position_name',card->>'title',
      'position_type',CASE card->>'type' WHEN 'hq' THEN 'pharmaplus' WHEN 'extra' THEN 'extra' ELSE 'pharmacy' END,
      'position_orientation',card->>'screenFormat','player_code',card->>'playerCode','content_code',card->>'contentCode'));
  END LOOP;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.scl290_clean_deals(p_pid uuid,p_year integer,p_state jsonb,p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE row jsonb; card jsonb; result jsonb:='[]'; m integer; nm text;
BEGIN
  SELECT name INTO nm FROM public.scl290_registry WHERE pharmacy_id=p_pid;
  FOR row IN SELECT value FROM jsonb_array_elements(coalesce(p_rows,'[]')) LOOP
    SELECT value INTO card FROM jsonb_array_elements(coalesce(p_state->'cards','[]')) WHERE value->>'id'=row->>'position_id' LIMIT 1;
    IF card IS NULL OR card->>'type'='hq' OR coalesce((card->>'initialPlanLocked')::boolean,false)=false THEN CONTINUE; END IF;
    m:=(row->>'start_month')::integer;
    IF m NOT BETWEEN 0 AND 11 OR nullif(card->>'installationStart','')::date>make_date(p_year,m+1,1) THEN
      RAISE EXCEPTION 'Η συμφωνία ξεκινά πριν από τη λειτουργία της θέσης';
    END IF;
    result:=result||jsonb_build_array(row||jsonb_build_object('pharmacy_id',p_pid,'pharmacy_name',nm,'year',p_year,
      'position_id',card->>'id','position_name',card->>'title','position_type',CASE card->>'type' WHEN 'extra' THEN 'extra' ELSE 'pharmacy' END));
  END LOOP;
  RETURN result;
END $$;
