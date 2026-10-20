# SpaceCoLab v294 — Φαρμακεία και Οθόνες

The HQ registry now owns the installation lifecycle. Existing official registry entries and current pharmacy data are retained; this release does not deactivate or delete any pharmacy automatically.

- Active/inactive directory, four registry fields and billing-code search remain. New entries remain inactive until explicitly activated.
- Activation opens screen configuration. Access links are delivered through «Πρόσβαση» after configuration; the token is inside expandable details.
- Cards show local and Pharmaplus screens, service start and initial programme progress for the selected year. Progress excludes Pharmaplus and positions with no active months in that year.
- Stable naming: surname-based prefix, ADV0 Pharmaplus, ADV1 Θέση 1, etc. Prefix collisions across active pharmacies are rejected with a request to add an area or billing code.
- HQ can add positions, or pause an existing position from a future month. Position IDs and ordinals are never reused. Previous schedules and finalized charges remain; future operational rows, variable costs and revenue respect the pause.
- «Διόρθωση εγκατάστασης» changes player prefix/orientation from the current month, retaining the prior configuration for historical month lookups. A before/after code preview states that Product Me needs manual changes.
- Deactivation requires the exact pharmacy name and current registry revision. It revokes the old token, clears activation data via the existing guarded deletion, removes completion records and restores the inactive registry identity. Reactivation creates fresh access.
- CSV export supports all or selected pharmacies, with Device, Content, orientation, start and pause. Already paused screens are excluded.

## Implementation and validation

`src/scl294-installation.js` replaces the existing embedded v290 installation module through `scripts/build-v294.py`, retaining the single-file HTML delivery and existing programme/library integration. The v294 Supabase migration extends existing RPCs and adds guarded correction/deactivation RPCs and a private installation history table.

Tests cover activation without installation, stable codes, authoritative orientation, duplicate prefixes, paused-month work and financial rows, immutable prior charges, stale versions, correction history, full deactivation/reactivation, UI activation routing, programme progress and selected CSV export. The existing library, finance, deadlines, reset approval and full-application tests remain in the suite.

HQ access security remains the separately agreed final package. Pharmacy onboarding/card simplification and the remaining form/HQ redesign packages are not declared complete by this release. No Product Me action is automated.
