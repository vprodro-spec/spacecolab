-- Synthetic fixture only. Always execute the whole transaction, including ROLLBACK.
-- No existing pharmacy tokens, programmes or financial data are read.
BEGIN;
DO $$
DECLARE pid uuid; tok text; y integer:=extract(year FROM scl_private.today());
 m integer:=extract(month FROM scl_private.today())::integer-1; fm integer;
 schedule jsonb; card jsonb; st jsonb; cfg jsonb; f jsonb; result jsonb; next_year jsonb;
 blocked boolean:=false; expected numeric; actual numeric;
BEGIN
 SELECT p.id,p.token INTO pid,tok FROM public.create_pharmacy('CERTIFICATION — transactional fixture') p LIMIT 1;
 INSERT INTO public.scl290_registry(pharmacy_id,name,billing_code,address,area)
 VALUES(pid,'CERTIFICATION — transactional fixture','CERT-'||pid,'Synthetic','Synthetic');
 cfg:=jsonb_build_array(jsonb_build_object('id','base-1','type','base','title','Test screen','startsOn',make_date(y,m+1,1),'screenFormat','vertical'));
 INSERT INTO public.scl290_installations(pharmacy_id,service_from,positions) VALUES(pid,make_date(y,m+1,1),cfg);
 SELECT jsonb_agg('A'::text) INTO schedule FROM generate_series(1,12);
 card:=jsonb_build_object('id','base-1','type','base','title','Test screen','installationStart',make_date(y,m+1,1),
 'initialPlanLocked',true,'basicSchedule',schedule,'simpleSchedule',schedule,'simpleConfirmed',true,'confirmedDeals','[]'::jsonb);
 st:=jsonb_build_object('cards',jsonb_build_array(card),'turnover',500000);
 INSERT INTO public.scl290_snapshots(pharmacy_id,year,state_json) VALUES(pid,y,st);
 f:=public.scl292_finance(y,tok,NULL);
 SELECT sum((v->>'amount')::numeric) INTO actual FROM jsonb_array_elements(f->'rows') v WHERE v->>'category'='base';
 expected:=round(485.0*(12-m)/12,2);
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'CERT_FAIL: proration'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(f->'rows') v WHERE v->>'pharmacy_id'<>pid::text) THEN RAISE EXCEPTION 'CERT_FAIL: tenant isolation'; END IF;
 BEGIN
  PERFORM public.scl290_save_program(tok,y,1,1,jsonb_set(st,ARRAY['cards','0','simpleSchedule',m::text],'"REWRITE"'::jsonb),'[]','[]');
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'HISTORY_LOCKED:%' THEN blocked:=true; ELSE RAISE; END IF;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'CERT_FAIL: closed month changed'; END IF;
 SELECT min(i) INTO fm FROM generate_series(m+1,11) i WHERE scl_private.today()<=scl_private.cutoff(y,i);
 IF fm IS NOT NULL THEN
  result:=public.scl290_save_program(tok,y,1,1,jsonb_set(st,ARRAY['cards','0','simpleSchedule',fm::text],'"FUTURE"'::jsonb),'[]','[]');
  IF (result->>'snapshot_revision')::integer<>2 THEN RAISE EXCEPTION 'CERT_FAIL: future save'; END IF;
 END IF;
 next_year:=public.scl290_get_pharmacy(tok,y+1);
 IF next_year->'state_json'->'cards'->0->>'initialPlanLocked'<>'false' THEN RAISE EXCEPTION 'CERT_FAIL: new year locked'; END IF;
 PERFORM set_config('certification.result',jsonb_build_object('synthetic_fixture',true,'prorated_base',actual,
 'tenant_isolation',true,'closed_month_rejected',blocked,'future_save',fm IS NOT NULL,'next_year_unlocked',true,'rolled_back',true)::text,true);
END $$;
SELECT current_setting('certification.result')::jsonb AS certification;
ROLLBACK;
