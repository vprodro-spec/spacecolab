-- Επαναφορά scl379 (Κ3β). Προσοχή: σβήνει τις χρεώσεις Market που έχουν γραφτεί (κατηγορία 'market')
-- και τους κωδικούς εταιριών/Brands. Οι συμφωνίες Market που υπάρχουν στα προγράμματα μένουν ως απλές συμφωνίες.
DROP TRIGGER IF EXISTS scl379_market_guard ON public.scl290_snapshots;
DROP TRIGGER IF EXISTS mk_request_months ON scl_private.mk_request;
DROP TRIGGER IF EXISTS mk_company_code ON scl_private.mk_company;
DROP TRIGGER IF EXISTS mk_brand_code ON scl_private.mk_brand;

-- οι παλιές εκδόσεις των συναρτήσεων που άλλαξαν
DO $do$ DECLARE r record; BEGIN
 FOR r IN SELECT def FROM scl_private.backup_v379_functions LOOP EXECUTE r.def; END LOOP;
END $do$;

DROP FUNCTION IF EXISTS public.scl379_ph_request_accept(text,uuid,integer,bigint,bigint,jsonb,jsonb,jsonb,text);
DROP FUNCTION IF EXISTS public.scl379_hq_deal_cancel(text,uuid,text,text);
DROP FUNCTION IF EXISTS public.scl379_mk_cancel_ask(text,uuid,text);
DROP FUNCTION IF EXISTS public.scl379_hq_cancel_ask_decline(text,uuid,text);
DROP FUNCTION IF EXISTS public.scl379_hq_codes(text,uuid);
DROP FUNCTION IF EXISTS public.scl379_hq_set_code(text,text,text,text);
DROP FUNCTION IF EXISTS scl_private.market_guard();
DROP FUNCTION IF EXISTS scl_private.market_deals(jsonb);
DROP FUNCTION IF EXISTS scl_private.market_deal_sig(jsonb);
DROP FUNCTION IF EXISTS scl_private.k3b_set12(jsonb,integer,jsonb);
DROP FUNCTION IF EXISTS scl_private.mk_req_themes(scl_private.mk_request);
DROP FUNCTION IF EXISTS scl_private.mk_plan_index(jsonb,integer);
DROP FUNCTION IF EXISTS scl_private.mk_request_months_guard();
DROP FUNCTION IF EXISTS scl_private.mk_code_default();
DROP FUNCTION IF EXISTS scl_private.mk_code_unique(text,text,text);
DROP FUNCTION IF EXISTS scl_private.mk_code_from(text);
DROP FUNCTION IF EXISTS scl_private.market_planned_rows(uuid,integer);
DROP FUNCTION IF EXISTS scl_private.capture_market_charges(uuid,integer,jsonb,bigint);
DROP FUNCTION IF EXISTS scl_private.market_blocks(integer,jsonb);

DELETE FROM public.scl292_charge_events WHERE category='market';
ALTER TABLE public.scl292_charge_events DROP CONSTRAINT scl292_charge_events_category_check;
ALTER TABLE public.scl292_charge_events ADD CONSTRAINT scl292_charge_events_category_check CHECK (category = ANY (ARRAY['custom','deal','report']));

DELETE FROM scl_private.price_list WHERE item='market_fee';
ALTER TABLE scl_private.price_list DROP CONSTRAINT price_list_item_check;
ALTER TABLE scl_private.price_list ADD CONSTRAINT price_list_item_check CHECK (item = ANY (ARRAY['platform','base_program','extra_position','free_changes','extra_change','deal']));

DELETE FROM scl_private.mk_request_log WHERE action IN ('partly_cancelled','cancel_asked','cancel_ask_declined');
ALTER TABLE scl_private.mk_request_log DROP CONSTRAINT mk_request_log_action_check;
ALTER TABLE scl_private.mk_request_log ADD CONSTRAINT mk_request_log_action_check CHECK (action = ANY (ARRAY['sent','seen','declined','expired','withdrawn','cancelled','answer_seen','accepted']));

ALTER TABLE scl_private.mk_request DROP CONSTRAINT IF EXISTS mk_request_cancel_ask_note_check;
ALTER TABLE scl_private.mk_request DROP COLUMN IF EXISTS accepted_by, DROP COLUMN IF EXISTS deal_id, DROP COLUMN IF EXISTS prior_months,
 DROP COLUMN IF EXISTS cancelled_months, DROP COLUMN IF EXISTS cancelled_by, DROP COLUMN IF EXISTS cancel_asked_at,
 DROP COLUMN IF EXISTS cancel_ask_note, DROP COLUMN IF EXISTS cancel_ask_by;
ALTER TABLE scl_private.mk_company DROP COLUMN IF EXISTS code;
ALTER TABLE scl_private.mk_brand DROP COLUMN IF EXISTS code;
