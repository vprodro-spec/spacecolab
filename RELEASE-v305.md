# v305 — Charge corrections, economics and supplier correspondence

## Delivered

- HQ can cancel a planned charge or enter a partial/full credit for a finalized charge, with mandatory reason, review and explicit confirmation. Original rows and linked correction history remain available. Server-side revision checks, idempotent requests and remaining-balance validation prevent duplicate or excessive credits.
- Monetary corrections do not change the programme, Product Me completion or previously consumed free customizations. Cancellations survive subsequent charge finalization. Pharmacy and HQ receive the same adjusted rows; finalized exports use the displayed totals.
- Pharmacy economics opens stored revenue/cost breakdowns by position, month and action. Confirmed future agreements in the selected year count; preagreements do not. Free-customization usage is shown per screen/year.
- Annual estimate restores the existing full-year scenario, dynamic turnover/screen-based prices and comparison with reference prices. Assumptions and cost breakdown are explicit; saved actual results appear separately. Scenario prices are not editable.
- Supplier proposal and confirmation are friendly formal pharmacy letters, with period, products, commercial amount, orientation, dimensions, silent MP4 or static JPEG, exact alternative filenames and 14-day delivery dates. Copy and print/PDF output are supported; no email is sent automatically.
- A one-month agreement hides the per-month-content selector. Shortening an existing agreement preserves its stored content fields.

## Validation

- Build and 115 automated tests passed, including PostgreSQL corrections, expiry/idempotency, same HQ/pharmacy totals, retained programme/completion, exports, one-month/multiple-month interaction, both orientations and letter output.
- Supabase migration `charge_adjustments` applied on 2026-10-21 (remote version 20261021184514).
- New correction table uses RLS with no direct anon/authenticated grants. The RPC retains the existing HQ authorization guard and an empty search path.
- Live desktop visual review follows deployment. Phone viewport is not yet visually verified.

## Deferred by agreement

HQ access security remains the final separate step. The existing shared-key model is unchanged; this is not a security certification. Supabase continues to flag public SECURITY DEFINER RPC execution under that model, including the guarded new RPC ([advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable)).
