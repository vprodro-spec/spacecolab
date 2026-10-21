# v299 — Continuous content periods and explicit agreement status

Consecutive months with the same confirmed content now render as a single spanning timeline cell. A change of content, interruption, installation boundary or separate supplier agreement starts another period. Preagreements and shelf sponsorship remain visible with their own month ranges without creating video changes or supplier activation charges.

HQ local-position changes are derived from the saved programme using the same content identity as the pharmacy block calculator. The old `monthlyContentChanges` flag alone no longer creates a task every month. Existing stored monthly rows are corrected when displayed; future saves also carry corrected flags. Pharmaplus resolution and explicit library media replacement tasks remain intact. Obsolete asynchronous custom-row enrichment can no longer reinstall its duplicate-month logic.

The production diagnostic found a January–March 2027 agreement with identical monthly content: the existing database grouped it correctly, but stored operational rows incorrectly requested three changes. The charging rules and immutable historical charge ledger have not been changed. Both HQ and pharmacy financial tables now display the complete projection period beside the one charge, with an explicit charge-month filter and an explanation of continuous-period charging.

Supplier forms distinguish a new unsaved entry, saved preagreement and definitive agreement. Users can save a preagreement, register a definitive agreement directly, or explicitly convert a preagreement through review and final confirmation. Supplier material delivery remains a separate operational step. Identical consecutive monthly material requests now share one file requirement and a full period.

Validation: 73 automated tests, including real PostgreSQL agreement A/A/A, A/B/A and A/A/B block comparisons, preserved historical charges, preagreement promotion, spanning timeline cells, existing-state HQ reconstruction after reload, and billing-period display. Browser visual validation requires an authenticated session; no live programme data was changed during this fix.
