-- v301: qualify singleton updates for API sessions running safeupdate.
-- Keep authentication, permissions, fingerprint checks and atomic transactions intact.

CREATE OR REPLACE FUNCTION public.scl300_pp_save(p_hq_key text,p_request jsonb,p_fingerprint text,p_replace boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE preview jsonb;p jsonb;a jsonb;rev bigint;BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);PERFORM pg_advisory_xact_lock(300,1);
 SELECT revision INTO rev FROM scl_private.pp_meta FOR UPDATE;
 preview:=scl_private.pp_preview(p_request);
 IF p_fingerprint IS NULL OR preview->>'fingerprint'<>p_fingerprint THEN RAISE EXCEPTION 'Η προεπισκόπηση άλλαξε. Ελέγξτε ξανά τους μήνες και τα φαρμακεία πριν αποθηκεύσετε.';END IF;
 IF jsonb_array_length(preview->'patches')=0 THEN RAISE EXCEPTION 'Δεν υπάρχουν αλλαγές για αποθήκευση';END IF;
 IF jsonb_array_length(preview->'conflicts')>0 AND NOT coalesce(p_replace,false) THEN RAISE EXCEPTION 'Απαιτείται ρητή επιβεβαίωση αντικατάστασης υπάρχουσας καμπάνιας';END IF;
 IF preview->>'action'='create' THEN INSERT INTO scl_private.pp_campaigns VALUES((preview->>'campaign_id')::uuid,(preview->>'starts_on')::date,(preview->>'ends_on')::date);END IF;
 FOR p IN SELECT value FROM jsonb_array_elements(preview->'patches') LOOP
  a:=p->'after';
  INSERT INTO scl_private.pp_history(revision,action,month_on,before_data,after_data) VALUES(rev+1,preview->>'action',(p->>'month_on')::date,p->'before',a);
  INSERT INTO scl_private.pp_months(month_on,campaign_id,campaign,scope_override,thematic) VALUES((a->>'month_on')::date,(a->>'campaign_id')::uuid,a->'campaign',nullif(a->'scope_override','null'::jsonb),a->'thematic') ON CONFLICT(month_on) DO UPDATE SET campaign_id=excluded.campaign_id,campaign=excluded.campaign,scope_override=excluded.scope_override,thematic=excluded.thematic,updated_at=now();
 END LOOP;
 UPDATE scl_private.pp_meta SET revision=rev+1 WHERE singleton=true;
 RETURN jsonb_build_object('revision',rev+1,'campaign_id',preview->>'campaign_id','months',preview->'months');
END $$;

CREATE OR REPLACE FUNCTION scl_private.pp_library_sync() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE changed integer;BEGIN
 UPDATE scl_private.pp_months SET thematic=thematic||jsonb_build_object('title',NEW.data->>'title','files',NEW.data->'files'),updated_at=now() WHERE month_on>=date_trunc('month',scl_private.today())::date AND thematic->>'theme_id'=NEW.id AND (thematic->>'title' IS DISTINCT FROM NEW.data->>'title' OR thematic->'files' IS DISTINCT FROM NEW.data->'files');
 GET DIAGNOSTICS changed=ROW_COUNT;IF changed>0 THEN UPDATE scl_private.pp_meta SET revision=revision+1 WHERE singleton=true;END IF;RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION scl_private.pp_media_sync() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN UPDATE scl_private.pp_months SET thematic=jsonb_set(thematic,'{media_revision}',coalesce(thematic->'media_revision','{}')||jsonb_build_object(NEW.orientation,NEW.id::text)),updated_at=now() WHERE month_on>=date_trunc('month',scl_private.today())::date AND thematic->>'theme_id'=NEW.theme_id;UPDATE scl_private.pp_meta SET revision=revision+1 WHERE singleton=true;RETURN NEW;END $$;
