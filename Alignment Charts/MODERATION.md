# Content Moderation Notes (App Store Review Guideline 1.2)

This document describes, factually and grounded in the current code, what
user-generated content Alignment Charts can place in shared iCloud storage and
what controls exist around it.

## What user content reaches shared storage

The app is an iMessage extension. When a user shares or collaborates on a
chart, `CloudKitChartService` writes to the CloudKit **public database** of
container `iCloud.name.zachsmith.Alignment-Charts`:

- A `Chart` record: the chart's JSON payload (grid text, labels, image
  references), addressed directly by the chart's UUID as the record name.
  Tier charts are stored the same way, as `Chart` records whose payload is
  the kind-tagged `ChartContent.tier` JSON (tier labels, items, and image
  references), addressed by the tier chart's UUID as the record name.
- `ChartImage` records: photo assets attached to chart cells. Cell images can
  come from the device camera, the photo library, or the built-in
  Wikipedia/Wikimedia Commons image search.

There is no public browse, search, or discovery surface: records are fetchable
only by their exact record ID, and IDs are distributed through an iMessage
collaboration link — i.e., participants are people the user already messages
with. Charts are not listed anywhere publicly.

## Controls that exist in the code

- **Payload validation on download** (`CloudKitChartService.decode`): a fetched
  record is rejected unless it decodes to a `ChartState` where `chart.isValid`
  holds and the chart UUID matches the record name. Malformed records never
  render.
- **Payload validation on tier download** (`CloudKitChartService.decodeTier`):
  a fetched record is rejected unless it decodes to a kind-tagged
  `ChartContent.tier` whose `TierState` `isValid` holds (2–8 tiers, unique
  tier/item IDs, item caps) and whose UUID matches the record name.
- **Merge instead of overwrite on co-edited tier charts** (`TierMerge`): when
  two participants edit the same tier chart, the upload three-way merges
  against the editing base with compare-and-swap retries. Concurrent edits
  that cannot be reconciled (same title, tier, or item changed both ways;
  item moved to two places; tier deleted on one side and changed on the
  other) surface a review where the user picks which version to keep; nothing
  uploads until every conflict is resolved. Merge results are re-validated
  before upload, so a merged chart can never place an invalid chart in shared
  storage.
- **Local hide** (`ChartHistoryStore.hide(_:in:)`): hides a chart from the
  history view for a given conversation scope. Local-only; it does not affect
  shared storage or other devices.
- **Local delete** (`ChartHistoryStore.delete(_:)`): deletes the chart's local
  history file. Local-only; it does not delete the shared CloudKit records.
- **Licensed-image filtering in search** (`ImageSearchService`): the Wikipedia
  query passes `pilicense=free` so only freely-licensed thumbnails are
  returned; Wikimedia Commons hosts only freely-licensed media by policy.
- **Conversation-level blocking**: iMessage participants can block each other
  via the OS Messages app; the extension has no user-level block list.

## Reporting path — known gap

The app has **no in-app reporting flow** for objectionable content: there is
no "report" button, no moderation queue, and no user-triggered deletion of
shared CloudKit records. The only code that deletes records is the
`#if DEBUG` schema bootstrap, which deletes only its own test records.

Consequences, stated honestly:

1. A user who receives objectionable content in a shared chart cannot report
   it from inside the app; the practical recourses are local hide/delete
   (which only affect their own device) and OS-level Messages blocking.
2. A hidden or locally deleted chart remains in the CloudKit public database
   under its record ID; there is no user-facing way to remove the shared copy.

If App Store review requires an in-app report action, one will need to be
built (e.g. a "Report chart" control that flags a record ID for review by the
developer), and this document updated to describe it. Until then, the intended
path is contacting the developer directly.

Last verified against the `build/1.0-24` source, Sep 27, 2026.
