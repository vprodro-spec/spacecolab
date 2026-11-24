-- Rollback του scl374b: ξαναφτιάχνει το «DR.ALTHEA» (949) και του επιστρέφει τις δύο υποκατηγορίες του.
INSERT INTO scl_private.mk_brand OVERRIDING SYSTEM VALUE SELECT (jsonb_populate_record(NULL::scl_private.mk_brand, j)).* FROM scl_private.backup_v374_brand_merge WHERE kind='brand' AND (j->>'id')::int=949;
UPDATE scl_private.mk_brand_scope s SET brand_id=949 FROM scl_private.backup_v374_brand_merge k WHERE k.kind='scope' AND (k.j->>'brand_id')::int=949 AND s.id=(k.j->>'id')::bigint;
DROP TABLE scl_private.backup_v374_brand_merge;
