# v300 — Annual Pharmaplus programme

HQ retains the existing month-card layout with separate Campaign and Thematic sections. A campaign has one identity and a period of whole months, including periods crossing a year boundary. Each month independently retains its thematic, campaign content and optional participation override. All/selected/excluded pharmacy participation uses stable registry identities and begins with the Pharmaplus position installation.

Future campaign changes can apply to one month or the remaining months of that campaign. Cancellation clears the campaign only and restores the underlying thematic. Current and past programme months are read-only. The original monthly data is archived intact; saved mutations preserve before/after history. No test campaign is added to the live programme during release validation.

Every write requires a server-generated impact preview showing months, affected pharmacies, device codes and previous/new content. A fingerprint prevents committing a stale preview. Overlapping campaigns require explicit replacement. Multi-month writes are atomic. Old write RPCs are retired and legacy read RPCs resolve the same canonical programme.

The pharmacy timeline uses the same resolved campaign or thematic and groups consecutive identical content. HQ work instructions compare the previous month across years, so January does not create a duplicate task for a continuous November–February campaign. A monthly participation exception or a real content change starts a new period. Library media replacements and corrections remain distinct. Pharmaplus remains non-billable.

Validation before publication: 86 automated tests passed, including real PostgreSQL migration, Nov–Feb creation, overlap confirmation, monthly participation, edit/cancel scope, past-month protection, stale preview, installation boundaries, legacy reads, permissions, UI preview/save/retry and pharmacy spanning cells. The migration was applied successfully; all 12 existing monthly records were retained and archived. Live browser verification follows publication.

HQ authentication replacement remains the separately agreed final security task. This release does not finish the broader HQ overview and terminology cleanup outside the annual programme.
