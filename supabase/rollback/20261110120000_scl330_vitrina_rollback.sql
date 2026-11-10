-- Αναίρεση του v330.0 «Βιτρίνα». Σβήνει ΜΟΝΟ ό,τι δημιούργησε η migration 20261110120000_scl330_vitrina.
-- Δεν αγγίζει καμία υπάρχουσα συνάρτηση ή πίνακα. Ο πίνακας scl_private.backup_v330_functions μένει ως αντίγραφο.
-- Προσοχή: διαγράφονται και όλες οι όψεις και κρατήσεις Βιτρίνας που έχουν καταχωριστεί από τα φαρμακεία.
DROP FUNCTION IF EXISTS
 public.scl330_vitrina_get(text),
 public.scl330_vitrina_activate(text),
 public.scl330_vitrina_save_facade(text,integer,bigint,text,jsonb),
 public.scl330_vitrina_delete_facade(text,integer,bigint),
 public.scl330_vitrina_add_booking(text,integer,text,text,date,date,text,numeric,text),
 public.scl330_vitrina_delete_booking(text,uuid);
DROP FUNCTION IF EXISTS
 scl_private.vitrina_state(uuid),
 scl_private.vitrina_lock(uuid),
 scl_private.vitrina_period_ok(date,date),
 scl_private.vitrina_check_design(jsonb),
 scl_private.vitrina_position_ids(jsonb);
DROP TABLE IF EXISTS scl_private.vitrina_bookings,scl_private.vitrina_facades,scl_private.vitrina_settings;
