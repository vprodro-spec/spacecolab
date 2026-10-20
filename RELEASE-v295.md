# SpaceCoLab v295 — Pharmacy navigation and initial programme

This release simplifies the pharmacy workspace around the screens configured by HQ. It retains existing programmes, prices, financial history and the library; it does not modify any pharmacy record during deployment.

- Five clear sections: Προγραμματισμός, Το φαρμακείο μου, Οικονομικά, Εκτίμηση εσόδων and Οδηγός. Returning pharmacies open in programming. A new pharmacy must explicitly choose turnover before programming, using the existing price calculation.
- HQ screen identity, orientation and installation date are read-only. Compact cards show the device code and the current and next calendar month, including December/January across years.
- Initial programmes start blank or from a selected ready programme. Every active month through December must be filled before finalizing a position. Planograms can be previewed with the HQ-defined orientation and all three existing setups. Selections are kept in memory only and discarded with a warning on exit; no draft is saved.
- Finalization waits for the server and restores the unlocked state if saving fails. Each position locks independently. Existing programmes require the established HQ-approved reset flow.
- The annual view and position details use agreed Greek vocabulary. Preagreements and shelf sponsorships have distinct labels. Inactive months are grouped and historical entries remain readable and viewable.
- Customization opens directly. Agreements use one creation button and a compact list. The detailed form redesign is a later package.
- Recorded economics and the existing estimate are separate pages. Editing turnover changes future suggestions without changing stored agreement or sponsorship amounts. This release does not revise the estimate model.

## Implementation and verification

`src/scl295-pharmacy.js` is appended by `scripts/build-v295.py`. Initial-library choices remain in `src/scl293-ui.js`; the v294 save fingerprint now runs after payload normalization, preventing a duplicate write after initial finalization.

Migration `20261020195653_pharmacy_onboarding_guard.sql` adds a private trigger that requires positive turnover when a local programme becomes locked. It leaves already locked programmes and existing records untouched and does not broaden access.

The 57-test suite covers mandatory turnover, no writes while browsing or trying selections, per-position completeness, planogram previews, cancellation, save failures, a single successful write, unchanged stored prices, December/January display, historical read-only sponsorships, and existing registry/library/finance/reset behavior. Browser verification follows deployment.

Remaining agreed packages include detailed Customization/Agreement/Sponsorship forms, multi-month Pharmaplus campaigns, HQ overview/tasks and initial-deadline management, remaining economics/charge adjustments, and HQ access security last. Product Me remains a manual workflow.
