# v293 — Shared HQ library

The HQ **Βιβλιοθήκη** tab manages themes and ready programmes, backed by Supabase RPCs. It replaces hard-coded new selections with the shared catalogue. The existing Pharmaplus theme title field also offers available library titles; the broader campaign redesign remains in its own package.

- Lossless import: 38 unique themes (32 existing programme titles + 6 commercial themes), 39 planogram variants, all 36 legacy programme/month mappings. The two different Πόνος variants remain separate.
- Draft themes visible only at HQ; explicit publication, withdrawal/restoration. No theme completeness gate beyond required title/valid data shape. Ready programmes require 12 available theme selections before publication.
- Create/edit/copy/withdraw programmes. Stable storage identity plus per-month variant references preserve finalized pharmacy schedules. Legacy cards resolve the original variant through immutable programme/month mappings.
- Unified searchable selection and planogram preview in initial scheduling and Custom. Initial scheduling supports blank or a ready programme as the starting point. Previews never insert synthetic cards or persist a draft.
- Theme editor retains all original products and the three existing setup styles, adds editable four-shelf allocation and filename fields for both orientations. No video upload. Renaming does not rewrite schedules or billing identity.
- File name correction does not invalidate completion. Explicit replacement records a media revision and adds an operational task, using the existing centralized completion mechanism. It never creates a Custom charge. Existing files had no central filename catalogue: filename fields begin empty and are filled with the actual Product Me names by HQ.
- Existing pharmacy state and billing tables are not modified by this migration. HQ access security remains the explicitly deferred last package.

Validation before publication: 44 passing tests, including real PostgreSQL library migration/permissions/optimistic concurrency, draft/publication/withdrawal, media revision semantics, seed parity, and full application HQ/pharmacy integration. Visual deployment checks recorded after publication below.

Visual review on the deployed application (20 Oct 2026): HQ search/editor, both Πόνος variants, vertical and horizontal previews, hybrid shelf arrangement, and pharmacy unified theme search in editable December verified. No pharmacy programme was confirmed during this review. The pre-existing corrupted display title “Home Pharmacy Βασικό Πρόγραμμαs” was corrected through the HQ editor to “Home Pharmacy Basics”; its immutable schedule key remains unchanged. A media-task regression check ensures an October replacement does not become a new task merely because the current month changes. Mobile viewport has not been visually certified.

Database fingerprint before/after migration: snapshots `8d9f0c2787cfaa237d6996b04983d0d6`, charges `ead7d7ba5c0c6ae424e497ed5d62ec6b` unchanged. New tables deliberately deny direct client access; RPCs use the existing HQ/token guards. Supabase advisor notices about callable SECURITY DEFINER functions reflect that existing access architecture, which remains scheduled for the final security package.
