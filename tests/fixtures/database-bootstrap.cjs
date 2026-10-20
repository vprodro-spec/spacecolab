const bootstrap=`
CREATE ROLE anon;CREATE ROLE authenticated;
CREATE TABLE pharmacies(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text,token text);
CREATE TABLE scl290_registry(id uuid DEFAULT gen_random_uuid(),pharmacy_id uuid,name text,billing_code text,address text,area text,source_key text,legacy boolean);
CREATE TABLE scl290_installations(pharmacy_id uuid PRIMARY KEY,version bigint DEFAULT 1,service_from date,positions jsonb,updated_at timestamptz DEFAULT now());
CREATE TABLE scl290_snapshots(pharmacy_id uuid,year integer,revision bigint DEFAULT 1,state_json jsonb,months_json jsonb DEFAULT '[]',deals_json jsonb DEFAULT '[]',updated_at timestamptz DEFAULT now(),PRIMARY KEY(pharmacy_id,year));
CREATE TABLE pharmacy_state(pharmacy_id uuid,year integer,state_json jsonb,PRIMARY KEY(pharmacy_id,year));
CREATE TABLE hq_changes_done(id uuid DEFAULT gen_random_uuid(),change_key text PRIMARY KEY,done boolean,updated_at timestamptz DEFAULT now());
CREATE FUNCTION scl290_assert_hq(k text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF k IS DISTINCT FROM 'test-hq' THEN RAISE EXCEPTION 'Unauthorized HQ';END IF;END $$;
CREATE FUNCTION scl290_token_id(t text) RETURNS uuid LANGUAGE plpgsql AS $$ DECLARE p uuid;BEGIN SELECT id INTO p FROM public.pharmacies WHERE token=t;IF p IS NULL THEN RAISE EXCEPTION 'Invalid token';END IF;RETURN p;END $$;
CREATE FUNCTION upsert_pharmacy_state_by_token(t text,y integer,s jsonb) RETURNS void LANGUAGE sql AS $$INSERT INTO public.pharmacy_state VALUES(public.scl290_token_id(t),y,s) ON CONFLICT(pharmacy_id,year) DO UPDATE SET state_json=excluded.state_json$$;
`;
module.exports={bootstrap};
