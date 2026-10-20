# SpaceCoLab v296 — Pharmacy corrections

This patch responds to the v295 review. It restores the existing blue/black SpaceCoLab visual language and the annual timeline with one row per position and twelve month columns. The simplified information remains: device code, format, current/next month, distinct content types and sponsorship/preagreement labels. Every page now shares the header's container, fixing the mismatched widths.

Pharmaplus has a separate «Προβολή προγράμματος» action and explicitly states that HQ manages it. It exposes no local editor. Initial programme locking and legacy initial/custom/agreement/sponsorship entry points also reject the HQ position, independent of the stored lock flag.

Customization uses one eligibility rule per position/month, with precise explanations for initial programme requirements, service dates, prior periods, supplier agreements and the 15th-of-previous-month deadline. The existing rule is preserved: on 20 October 2026, November has passed its 15 October deadline and December remains editable until 15 November. Both local positions of the pharmacy shown in the review opened successfully for December in the live v295 reproduction.

The editor now names its position and year, shows only active months with a restriction reason, and resets unsaved choices to the confirmed programme when a user confirms discard. Switching positions does not carry a prior draft into another position. No database migration or stored programme/charge changes are included.

Verification adds focused integration cases for all Pharmaplus editor entry points and for switching two local positions, closed November/open December, supplier-agreement blocking, pending initial programme, draft discard, zero writes during exploration and the twelve-column timeline. The existing full test suite remains required by publication.
