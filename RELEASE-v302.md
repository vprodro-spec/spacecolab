# v302 — HQ overview

- Replace legacy setup/report counters with active pharmacies, per-position programme completion, local and Pharmaplus changes, and a deduplicated open-work list.
- Use the same local operational-row reconstruction and completion keys as Changes. The canonical Pharmaplus resolver supplies programme participation and actual changes. Legacy Pharmaplus tasks are no longer added a second time.
- Separate overdue work across months and years. A supplier task awaiting material is counted once. Pharmacy-only sponsorships and retired reporting tasks do not become HQ work.
- Counters open their corresponding lists. Work details show pharmacy, position, device, file, orientation, reason and completion control. The completion control still uses the existing persisted operation, without changing charge calculation.
- Remember overview month and year; current/next month actions cross year boundaries. Campaign and thematic counts respect active Pharmaplus positions and monthly participation. A valid thematic is not a warning.
- Add HQ-set initial-programme deadlines with revision checks and history. No dates are invented for existing pharmacies. Pending initial programmes disappear automatically when finalized; there is no manual completion tick for them.
- Initial deadline tables are private, RLS-enabled and inaccessible directly to client roles. RPCs preserve the existing HQ authorization check. Deactivation removes deadline data through the pharmacy foreign key.
- Preserve the existing neutral HQ panels, buttons and layout. Retired reporting is removed from daily navigation and counters; underlying historical records are retained.

Validation: 95 automated tests passed, including cross-year overdue work, no duplicate material task, inactive-pharmacy exclusion, independent position completion, shared task keys, failed completion rollback, December-to-January navigation, and SQL deadline authorization/concurrency/history rules. The migration was applied and direct table access remained denied. No live pharmacy programme, deadline or completion tick was changed for release testing. Live visual verification is recorded after publication.

Deferred as agreed: HQ authentication replacement. The v301 live temporary-campaign save test remains unperformed because it was blocked by automatic approval review; this overview release does not claim to have performed it.
