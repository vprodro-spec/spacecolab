# SpaceCoLab v297 — Pharmacy actions

This release completes the detailed pharmacy form package, continuing v296's visual language. The user requested that the comprehensive visual review take place after the functional packages; no browser visual certification is claimed for this release.

## Customization

- Select one or more editable months, search the shared theme library and inspect products or the existing planogram before applying a theme.
- Show the basic programme, current confirmed selection and new selection. Preserve the single eligibility rule, with Pharmaplus read-only, installation/pause dates, deadlines and supplier-agreement exclusion.
- Return selected months to their basic programme without resetting the position or unrelated months.
- Review each old → new choice and the expected free/paid block allocation before final confirmation. Identify shelf sponsorships that will be removed by a changed theme.

## Supplier agreements

- Supplier and brand are both required for final confirmation. Optional series/subseries and products remain. Select start month, duration within the selected year, and fixed or monthly content. Remove promotion mechanics, generic message fields, notes and reports from these forms.
- Retain the existing suggested-price calculation and allow an explicit final monthly amount. Show pharmacy revenue, agreement management cost and difference. Consecutive identical content is counted once, matching the database's block calculation.
- Saving a preagreement, including editing one, never confirms it. Only final confirmation replaces selected customizations and sponsorships, after a review showing affected months.
- Provide a proposal and, after confirmation, an on-demand supplier confirmation with copy and print/PDF actions. It names the pharmacy, position, orientation/specifications, period and price; requests delivery to emitropoulou@pharmaplus.gr 14 calendar days before the applicable month. Monthly files include year/month and orientation. The pharmacy sends it; no email is sent by the app.
- Store material-request metadata with the confirmed agreement for the later HQ task package. This release does not add the HQ material-state controls or automate Product Me.

## Shelf sponsorship

- Brand, series/products, 1/2/4 shelves from the top, start/duration and free monthly amount. Existing legacy shelf choices remain readable when editing.
- Keep the existing suggested price, show the €55 reference and the corresponding suggested supplier-agreement price; €55 is informational, not enforced.
- Explicit save only; opening or experimenting with the form creates no record, revenue, HQ task or charge. Supplier-agreement months are excluded. A closed part of a multi-month sponsorship is preserved when a future month is edited or removed.

## Persistence and verification

`SCL297` holds temporary form state outside the persisted pharmacy cards. Saving waits for the existing versioned save RPC; a failed save restores the previous cards and keeps the draft for retry. Duplicate confirmation is blocked. Existing snapshot history and immutable charge events are retained. No migration, live pharmacy data rewrite or access change is required.

Tests exercise multi-month customization, selective return to basic, discard, failed writes, duplicate clicks, preagreement editing without activation, replacement warnings, free sponsorship prices including decimal values, partial sponsorship removal, file deadlines, and required fields. A PostgreSQL integration test runs actual form payloads through the existing migrations and save/finance functions, checks preview amounts against database charges, verifies that sponsorship leaves charges unchanged, and confirms that historical charges and previous sponsorship snapshots survive agreement replacement.

Remaining packages: multi-month Pharmaplus campaigns; HQ overview, operational changes and material states; remaining economics/charge tools; final visual review and HQ access security. Product Me remains manual.
