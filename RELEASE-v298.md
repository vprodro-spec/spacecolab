# SpaceCoLab v298 — Save feedback and next-year scenarios

Confirmation now closes the action form after the versioned server save succeeds. Supplier documents remain available from the agreement's explicit document button; saving no longer opens a second modal automatically. Review and save operations show progress, reject repeated clicks, and keep draft values available when a save fails. Error messages are brought into view. Rendering after a successful save is separate from persistence and cannot roll back the saved card. The same separation applies to initial programmes.

The next-year shortcut targets the next calendar year, reopens an existing programme, and does not create 2028/2029/etc. on repeated clicks. Current-year navigation remains explicit. Deadlines and the actual date are unchanged. January–February 2027 can be programmed through the normal initial-programme and agreement flows.

Forms reuse the existing action buttons, numbered agreement sections, black position context and green financial summary. No replacement design system or full redesign is introduced. Visual checks are part of this release, with final cross-application refinements still pending.

Validation: 69 automated tests pass, including a PostgreSQL-backed January–February 2027 workflow, one €30 charge for continuous fixed content, year reopening without duplicate years, preservation of prior-year charges, server failure with retained draft, double confirmation while another save is pending, and successful persistence despite a subsequent rendering error.

The live v297 investigation confirmed that the test agreement was stored and the editor closed, then a supplier-document modal opened automatically. That controlled test entry was removed through the normal versioned save, preserving history. Live v298 browser verification is performed after deployment. HQ access security and the remaining HQ feature packages are not part of this fix.
