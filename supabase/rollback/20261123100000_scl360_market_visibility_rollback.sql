-- Αναίρεση του scl360 (Market, Κ1 Ορατότητα). Βγάζει ΜΟΝΟ τα νέα αντικείμενα. Τίποτα υπάρχον δεν αγγίζεται.
-- Προσοχή: σβήνει τις ρυθμίσεις ορατότητας, τις αποδοχές όρων και τα σημεία χάρτη που έχουν αποθηκευτεί.
DROP FUNCTION IF EXISTS public.scl360_mk_pharmacy(text,uuid);
DROP FUNCTION IF EXISTS public.scl360_mk_list(text);
DROP FUNCTION IF EXISTS public.scl360_hq_market_preview(text,uuid);
DROP FUNCTION IF EXISTS public.scl360_hq_market_overview(text);
DROP FUNCTION IF EXISTS public.scl360_market_set(text,text,boolean,boolean,boolean);
DROP FUNCTION IF EXISTS public.scl360_market_get(text);
DROP FUNCTION IF EXISTS scl_private.mk_pharmacy_view(uuid);
DROP FUNCTION IF EXISTS scl_private.mk_access_id(text);
DROP FUNCTION IF EXISTS scl_private.mk_card(uuid);
DROP FUNCTION IF EXISTS scl_private.mk_base_positions(uuid);
DROP FUNCTION IF EXISTS scl_private.mk_position_view(uuid,jsonb);
DROP FUNCTION IF EXISTS scl_private.mk_month_free(jsonb,jsonb,integer,integer);
DROP FUNCTION IF EXISTS scl_private.mk_covers(jsonb,integer);
DROP FUNCTION IF EXISTS scl_private.mk_band(numeric);
DROP FUNCTION IF EXISTS scl_private.mk_price(numeric,numeric);
DROP FUNCTION IF EXISTS scl_private.mk_num(jsonb);
DROP TABLE IF EXISTS scl_private.mk_access;
DROP TABLE IF EXISTS scl_private.mk_settings_history;
DROP TABLE IF EXISTS scl_private.mk_position_settings;
DROP TABLE IF EXISTS scl_private.mk_pharmacy;
DROP TABLE IF EXISTS scl_private.backup_v360_functions;
