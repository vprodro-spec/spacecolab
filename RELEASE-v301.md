# v301 — Pharmaplus save and pharmacy access fixes

- Fix the production `UPDATE requires a WHERE clause` error: all three Pharmaplus singleton revision updates now explicitly target `WHERE singleton=true`. The database's safe-update protection and existing authorization remain intact.
- Generate pharmacy access links against `https://vprodro-spec.github.io/spacecolab/` from every maintained and legacy link helper. Downloaded HTML no longer uses a temporary signed file URL or `file:` path. Existing pharmacy tokens remain unchanged and are URL-encoded.
- Preserve campaign preview, atomic save, conflict checks, history, monthly participation, and pharmacy layout.

## Validation

- 91 automated checks passed, including campaign saves across years, cancellation/fallback, library triggers, and access-link copy/open from local files, temporary storage, and the published site.
- Live migration applied; all three production function definitions contain the qualified singleton update. A live revision-update transaction was rolled back; the 12 original programme months, revision 1, and empty change history remained intact.
- A live browser save of a temporary campaign was blocked by automatic approval review because it would persist test data. No campaign was created. This release does not claim a completed live browser save.

The previously deferred HQ authentication redesign is outside this patch.
