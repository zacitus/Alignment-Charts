# Daily templates and streaks

Implemented September 6, 2026. Daily windows use midnight UTC (7 p.m. Chicago daylight time; 6 p.m. standard time). The launch collection covers September 6–19, 2026. Because implementation took place after the September 6 UTC reset, the first current template is September 7. September 6 has not been backdated for streak credit.

## CloudKit setup completed

Container: `iCloud.name.zachsmith.Alignment-Charts`.

The additive schema in `cloudkit-development.ckdb` was validated and imported into Development, then deployed to Production through CloudKit Console. Existing Chart, ChartImage, and Users fields and permissions were preserved. The 14 `DailyTemplate` records were created and verified in the **Production public database**, with names `daily-2026-09-06` through `daily-2026-09-19`.

Development builds use the same bundled launch collection. Remote editorial records are independent in Development and Production; the Production records do not automatically copy to Development.

## Autumn schedule extension — September 22, 2026

The app bundle now contains a continuous September 6–November 30 schedule (86 days). `Autumn 2026.json` contains the 70 new templates for September 22–November 30; `Autumn 2026.md` is the readable schedule. Today's replacement is **Cozy Season**, as requested. September 20–21 retain their original fallback content. Existing charts and streak claims are not modified.

**Published September 22, 2026:** all 70 templates were created in the Production public database through CloudKit Console. Each saved record was verified, then a fresh page reload and query returned 84 total records (14 original + 70 new). All 70 new record names and complete JSON payloads matched the prepared schedule, with no missing dates from September 22 through November 30. No new app build was required or distributed.

Each object is published as `DailyTemplate` with record name `daily-<day>` and the JSON object encoded in the `payload` String. The existing app downloads these records on refresh without a new App Store release. Users with an existing daily draft may continue that draft; replacing the template does not rewrite charts already created.

Validation: 542 daily/calendar/streak/template checks and 95 collaboration checks passed with the expanded catalog, including consecutive dates, unique daily IDs, 70 distinct new titles, serialization, and fallback after November 30.

## Scheduling another day

1. Open CloudKit Console → this container → Production → Public Database → Records.
2. Select `DailyTemplate` and query records to inspect the schedule.
3. Add a `DailyTemplate` record named `daily-YYYY-MM-DD`.
4. Set its `payload` String to a single template JSON object, matching that date. Use an existing record or `Daily/DailyTemplates.json` in the extension as an example.
5. Save. The app refreshes when activated, at reset while visible, and when the user taps Refresh.

Template fields: `day`, `title`, `prompt`, `rowAxisTitle`, `columnAxisTitle`, `rowLabels`, `columnLabels`. Grid size follows label counts (2–6 supported); the launch collection uses 3 × 3. Schedule ahead; editing an already-active template may leave people with different cached versions until they refresh. Prefer updating future dates.

Normal app users can read templates but cannot create or edit them. Author via the console using the developer team account. Do not grant ordinary iCloud users template write permissions.

## Behavior

- Starting a daily creates a new chart with fresh chart/cell IDs. Its daily identity is carried in the shared chart and preserved through collaboration. Daily title and layout are fixed; cell contents are editable.
- The app downloads up to 14 dated templates and caches them. A deterministic bundled rotation fills unscheduled dates after the launch date, including offline. Claims still require an iCloud connection before reset.
- A complete upload writes a separate `DailyCompletion` receipt in the public database. The original server creation time persists after subsequent chart edits.
- Merely editing, uploading, or inserting into the composer earns no personal credit. Completed outgoing messages carry a daily completion marker. The sender's send callback attempts a claim; a recipient tapping that completed message attempts their own claim. A passive receive or local-history open does not claim. If the sender's extension is suspended, they can tap the sent chart to retry.
- Each person's claim is a `DailyClaim` in their **private database**, named `claim-YYYY-MM-DD`. Repeat taps, different chats, and concurrent devices converge on the same day record. Claim history is paginated and cached by iCloud account identity.
- Both receipt and claim server creation times must fall in the scheduled day. Exactly midnight is too late. Requests that reach Apple after midnight do not count, and offline claims aren't backdated.
- Previous credit is not revoked when the chart changes. Current streak includes yesterday's run until today's claim window closes. Best streak survives a missed day.
- Opening a past daily chart remains possible but cannot grant new credit. Custom charts never grant daily credit.

## Validation

- Debug and Release simulator builds passed.
- All 108 daily/calendar/streak/template checks and 95 existing collaboration checks passed. Run `bash Tests/run-daily-tests.sh` and `bash Tests/run-collaboration-tests.sh` from the project directory.
- CloudKit Console verified the deployed schema and all 14 production templates.
- Signed simulator UI checks verified the current daily card, full 3 × 3 editor, visible close/share controls, reset countdown, and returning to “Continue today’s chart.” This simulator could not sync a personal iCloud streak, so no end-to-end personal claim is reported as verified.

Before distributing a release, test with two physical devices using different iCloud accounts: send a partial daily, have either person finish and send it, tap the completed bubble as a noncontributor, verify one claim per day across chats, retry a claim, and check that editing later doesn't revoke credit. Also verify the send callback on-device, account switching, offline retry before reset, and claims at/after reset. Simulator/unit tests do not establish real Messages delivery or private iCloud synchronization.

## Trust boundary

This is a casual streak feature backed by CloudKit, not a tamper-proof rewards system. Apple's server timestamps prevent normal late/backdated claims, but CloudKit does not execute custom server-side checks linking a private claim to a public completion or proving group membership. Official clients enforce that flow when opening completed Messages bubbles. Modified clients, fabricated public records, or forwarded completed bubbles cannot be cryptographically distinguished without additional server-side validation. No contact identifiers are stored for streaks.
