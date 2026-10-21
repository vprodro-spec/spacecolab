# v304 — Connected HQ workflow and consistent presentation

## Delivered

- One persisted pharmacy/month/year context across Overview, Changes, Charges, Pharmacies and Statistics. Each operational/financial status filter remains independent.
- Missing filenames open their exact source: library theme and orientation, Pharmaplus campaign/own theme, or supplier agreement material. Successful saves refresh related displays and return to the prior tab with the selection intact.
- Supplier confirmation and HQ instructions include the exact requested filename, device, period and 14-day deadline. No automatic email sending or video uploading.
- HQ agreement material details store the actual filename and awaiting/received/ready status independently of the programme, completion and charges. Optimistic revisions protect concurrent edits.
- Readable completion/material history and prior programme comparisons, including pharmacy access to its own history.
- Shared presentation across HQ/pharmacy tabs, forms and dialogs. Portrait/landscape labels, Greek workflow terminology, clear completion and financial labels, responsive layouts and print styling.
- Correcting an existing Pharmaplus filename preserves content identity and completion. Replacing actual content remains a separate operation.

## Validation

- Build completed; all 105 automated tests pass.
- PGlite database tests cover authorization, stale revision rejection, idempotent material changes, history, unchanged programme/charges/completion, cross-year filename correction and deactivation cleanup.
- Supabase migration applied on 2026-10-21 (`hq_materials_and_history`, remote version 20261021150925). New private tables have RLS and no direct anon access.
- Live visual review follows the deployment; its results will be recorded here.

## Deliberately separate next work

- Credits/cancellations and the detailed actual-economics/estimate package. This version does not change pricing rules or estimate assumptions.
- HQ access security remains the final separately agreed step. Existing authorization is retained; this release is not a security certification.
