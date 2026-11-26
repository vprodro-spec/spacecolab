-- scl381 · Κ3γ διορθώσεις ονομάτων αρχείων
-- 1) Αν αλλάξει ο πρώτος μήνας του υλικού, δίνεται νέο όνομα (το όνομα περιέχει τον μήνα).
-- 2) Νέο όνομα → σβήνει το «Στάλθηκε» της συμφωνίας, για να ξανασταλεί.
-- 3) Υλικά που έφυγαν από τη συμφωνία αποσύρονται.
-- 4) Οι λίστες (φαρμακείο, Κεντρικά) δείχνουν μόνο ονόματα συμφωνιών που υπάρχουν στο πρόγραμμα (όχι ακυρωμένων).
INSERT INTO scl_private.backup_v380_functions(name,def)
SELECT 'v381:'||p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p
WHERE p.oid IN ('public.scl380_ph_reserve(text,integer,text,text,jsonb,jsonb)'::regprocedure,'public.scl380_ph_materials(text,integer)'::regprocedure,'public.scl380_hq_materials(text,integer)'::regprocedure)
ON CONFLICT(name) DO NOTHING;

CREATE OR REPLACE FUNCTION public.scl380_ph_reserve(p_token text, p_year integer, p_position_id text, p_deal_id text, p_items jsonb, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token); it jsonb; g integer; fm integer; sc text; bc text; v_ym text; cur scl_private.material_file; n integer; base text; out jsonb:='[]'; k text:=coalesce(p_meta->>'kind','local'); nm text;
BEGIN
 IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2200 OR nullif(btrim(coalesce(p_deal_id,'')),'') IS NULL OR length(p_deal_id)>80 THEN RAISE EXCEPTION 'K3C:bad_request' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.scl290_installations i, jsonb_array_elements(i.positions) p WHERE i.pharmacy_id=pid AND p->>'id'=p_position_id) THEN RAISE EXCEPTION 'K3C:position' USING ERRCODE='22023'; END IF;
 IF k NOT IN ('local','market') OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'K3C:bad_request' USING ERRCODE='22023'; END IF;
 FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  g:=(it->>'grp')::integer; fm:=(it->>'first_month')::integer; sc:=upper(coalesce(it->>'supplier_code','')); bc:=upper(coalesce(it->>'brand_code',''));
  IF g IS NULL OR g NOT BETWEEN 0 AND 11 OR fm IS NULL OR fm NOT BETWEEN 0 AND 11 OR sc !~ '^[A-Z0-9]{2,20}$' OR bc !~ '^[A-Z0-9]{2,20}$' THEN RAISE EXCEPTION 'K3C:bad_item' USING ERRCODE='22023'; END IF;
  v_ym:=lpad((fm+1)::text,2,'0')||'_'||p_year;
  SELECT * INTO cur FROM scl_private.material_file WHERE pharmacy_id=pid AND year=p_year AND deal_id=p_deal_id AND grp=g AND replaced_at IS NULL FOR UPDATE;
  IF cur.id IS NOT NULL AND cur.supplier_code=sc AND cur.brand_code=bc AND cur.first_month=fm THEN
   out:=out||jsonb_build_array(jsonb_build_object('grp',g,'base',cur.file_base,'new',false)); CONTINUE;
  END IF;
  IF cur.id IS NOT NULL THEN UPDATE scl_private.material_file SET replaced_at=now() WHERE id=cur.id; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('scl380:'||sc||':'||v_ym));
  SELECT coalesce(max(seq),0)+1 INTO n FROM scl_private.material_file WHERE supplier_code=sc AND ym=v_ym;
  IF n>99 THEN RAISE EXCEPTION 'K3C:full' USING ERRCODE='22023'; END IF;
  base:=v_ym||'_'||sc||'_'||bc||'_'||lpad(n::text,2,'0');
  INSERT INTO scl_private.material_file(pharmacy_id,year,position_id,deal_id,grp,first_month,supplier_code,brand_code,ym,seq,file_base,kind,request_id)
  VALUES(pid,p_year,p_position_id,p_deal_id,g,fm,sc,bc,v_ym,n,base,k,nullif(p_meta->>'request_id','')::uuid);
  out:=out||jsonb_build_array(jsonb_build_object('grp',g,'base',base,'new',true));
  -- Νέο όνομα: το «Στάλθηκε» αφορούσε το παλιό, άρα πρέπει να ξανασταλεί.
  DELETE FROM scl_private.material_sent WHERE pharmacy_id=pid AND year=p_year AND deal_id=p_deal_id;
 END LOOP;
 -- Υλικά που δεν υπάρχουν πια στη συμφωνία (λιγότερα θέματα): το όνομά τους αποσύρεται.
 UPDATE scl_private.material_file SET replaced_at=now() WHERE pharmacy_id=pid AND year=p_year AND deal_id=p_deal_id AND replaced_at IS NULL
  AND grp NOT IN (SELECT (x->>'grp')::integer FROM jsonb_array_elements(p_items) x);
 -- Νέος προμηθευτής / Brand με το χέρι → «Από φαρμακεία» (μόνο για τοπικές, μόνο τώρα που γίνεται οριστική).
 IF k='local' THEN
  nm:=nullif(btrim(coalesce(p_meta#>>'{supplier,name}','')),'');
  IF nm IS NOT NULL AND (p_meta#>>'{supplier,new}')='true' THEN
   INSERT INTO scl_private.ph_registry_pending(kind,name,code,supplier_name,brand_names,pharmacy_id,year,deal_id,position_id,months)
   VALUES('supplier',left(nm,120),scl_private.k3c_first_code(nm),nm,ARRAY(SELECT jsonb_array_elements_text(coalesce(p_meta->'brands','[]'))),pid,p_year,p_deal_id,p_position_id,ARRAY(SELECT jsonb_array_elements_text(coalesce(p_meta->'months','[]')))::integer[])
   ON CONFLICT DO NOTHING;
  END IF;
  FOR nm IN SELECT btrim(value) FROM jsonb_array_elements_text(coalesce(p_meta->'brand_free','[]')) WHERE btrim(value)<>'' LOOP
   INSERT INTO scl_private.ph_registry_pending(kind,name,code,supplier_name,brand_names,pharmacy_id,year,deal_id,position_id,months)
   VALUES('brand',left(nm,120),scl_private.mk_code_from(nm),nullif(btrim(coalesce(p_meta#>>'{supplier,name}','')),''),ARRAY[nm],pid,p_year,p_deal_id,p_position_id,ARRAY(SELECT jsonb_array_elements_text(coalesce(p_meta->'months','[]')))::integer[])
   ON CONFLICT DO NOTHING;
  END LOOP;
 END IF;
 RETURN jsonb_build_object('ok',true,'files',out);
END $function$;

CREATE OR REPLACE FUNCTION public.scl380_ph_materials(p_token text, p_year integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE pid uuid:=public.scl290_token_id(p_token);
BEGIN
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('deal_id',m.deal_id,'position_id',m.position_id,'grp',m.grp,'first_month',m.first_month,'base',m.file_base,'kind',m.kind,
   'sent',CASE WHEN s.deal_id IS NOT NULL THEN jsonb_build_object('how',s.how,'by',s.by_name,'at',s.at) END) ORDER BY m.first_month,m.position_id,m.grp)
  FROM scl_private.material_file m LEFT JOIN scl_private.material_sent s ON s.pharmacy_id=m.pharmacy_id AND s.year=m.year AND s.deal_id=m.deal_id
  WHERE m.pharmacy_id=pid AND m.year=p_year AND m.replaced_at IS NULL AND EXISTS(SELECT 1 FROM public.scl290_snapshots sn
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(sn.state_json->'cards')='array' THEN sn.state_json->'cards' ELSE '[]'::jsonb END) c
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(c->'confirmedDeals')='array' THEN c->'confirmedDeals' ELSE '[]'::jsonb END) d
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(d#>'{k3,files}')='array' THEN d#>'{k3,files}' ELSE '[]'::jsonb END) f
    WHERE sn.pharmacy_id=m.pharmacy_id AND sn.year=m.year AND f->>'base'=m.file_base)),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.scl380_hq_materials(p_hq_key text, p_year integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.scl290_assert_hq(p_hq_key);
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('pharmacy_id',m.pharmacy_id,'pharmacy',g.name,'pharmacy_code',g.pharmacy_code,'position_id',m.position_id,'deal_id',m.deal_id,'grp',m.grp,
   'first_month',m.first_month,'base',m.file_base,'kind',m.kind,'supplier_code',m.supplier_code,'brand_code',m.brand_code,'created_at',m.created_at,
   'sent',CASE WHEN s.deal_id IS NOT NULL THEN jsonb_build_object('how',s.how,'by',s.by_name,'at',s.at) END) ORDER BY m.first_month,g.name,m.position_id)
  FROM scl_private.material_file m JOIN public.scl290_registry g ON g.pharmacy_id=m.pharmacy_id
  LEFT JOIN scl_private.material_sent s ON s.pharmacy_id=m.pharmacy_id AND s.year=m.year AND s.deal_id=m.deal_id
  WHERE m.year=p_year AND m.replaced_at IS NULL AND EXISTS(SELECT 1 FROM public.scl290_snapshots sn
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(sn.state_json->'cards')='array' THEN sn.state_json->'cards' ELSE '[]'::jsonb END) c
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(c->'confirmedDeals')='array' THEN c->'confirmedDeals' ELSE '[]'::jsonb END) d
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(d#>'{k3,files}')='array' THEN d#>'{k3,files}' ELSE '[]'::jsonb END) f
    WHERE sn.pharmacy_id=m.pharmacy_id AND sn.year=m.year AND f->>'base'=m.file_base)),'[]'::jsonb);
END $function$;
