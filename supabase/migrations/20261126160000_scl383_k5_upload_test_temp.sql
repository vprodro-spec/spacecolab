-- ΠΡΟΣΩΡΙΝΟ: δοκιμή ανεβάσματος βίντεο (Κ5). Κλειστός χώρος, μόνο ανέβασμα, MP4 έως 50 MB.
-- Rollback: DROP POLICY scl383_k5_test_insert ON storage.objects; άδειασμα και σβήσιμο του bucket scl383-k5-test.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('scl383-k5-test','scl383-k5-test',false,52428800,ARRAY['video/mp4'])
ON CONFLICT(id) DO NOTHING;
CREATE POLICY scl383_k5_test_insert ON storage.objects FOR INSERT TO anon
WITH CHECK (bucket_id='scl383-k5-test' AND name ~ '^test/[0-9]{13}_[A-Za-z0-9_]{1,60}\.mp4$');
