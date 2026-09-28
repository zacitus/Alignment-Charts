# Collaboration verification

Run `./Tests/run-collaboration-tests.sh` from the Alignment Charts project directory. This compiles the production merge/save engine and history store into a standalone Swift test executable; it needs Xcode command-line tools and no CloudKit account. Tests use a unique temporary history record and remove it afterward.

Coverage includes independent cell and field edits; simultaneous photo replacement and removal; labels and axes; identical edits; resize versus retained/deleted cell edits; all supported grid sizes; explicit conflict resolution; a newer change arriving after resolution; missing ancestors and old image/history decoding; draft persistence; simulated conditional-save races, bounded retries, missing records, and network errors. The executable is separate from the app target.

## Two-device acceptance check before release

Use two devices with separate iCloud accounts and the updated app on both. These checks require the deployed CloudKit permissions/schema and cannot be validated by the standalone tests.

1. Open the same chart on both devices. Edit different cells, then tap Update on both. Reopen the chart and confirm both edits and the merged message preview.
2. Edit the same caption differently. Save one, then the other. Verify the second device shows both versions; Cancel retains its draft; Continue requires a choice and preserves unrelated contributions.
3. Replace the same photo with different images. Verify both image alternatives appear and the chosen image survives reopening. Repeat with remove versus replace, and text versus photo in the same cell.
4. Remove a row/column on one device while editing a removed cell on the other. Verify a grid comparison appears. Repeat with an edit to a retained cell: that should merge automatically.
5. Leave a local edit unsent, receive another chart update, close/reopen the extension, and open its message. The local edit must remain; sharing should merge it with the newest server chart.
6. While one device is reviewing a conflict, save another conflicting edit from the other device. Continue the first review; the newer conflict must be shown again.
7. Interrupt networking during fetch/upload and retry. The draft must remain; a failed fetch must never be treated as a new chart; an incomplete asset upload must not publish a new chart payload.
8. Open an older saved draft that has no editing baseline. If its contents differ from the shared chart, verify an explicit whole-chart comparison appears.

## Compatibility and storage

The existing `Chart.payload` and `ChartImage.asset` schema is reused. New image replacements have immutable UUID references inside the payload. Legacy images still resolve through their original cell IDs. Old image records are intentionally retained because other devices' drafts and conflict previews may still refer to them; safe garbage collection would need a separate retention design.

All collaborators must update: older app builds still perform unconditional whole-chart writes and do not understand the new image references. This client change cannot prevent an older build from overwriting CloudKit records. Message previews represent a successfully committed chart snapshot; tapping a message loads the shared chart (or resumes a pending local draft).

CloudKit saves happen when adding/updating the message, as before; canceling the Messages compose field does not roll back an already committed chart.

## Home screen

The home screen shows the completed-charts carousel and the New Alignment Chart button. In-progress charts can be reopened from their Messages bubbles; their local history is retained but has no home-screen carousel. The recent automatic history refresh and separate shared-preview cache have been removed.


## Daily templates and streaks

Run `bash Tests/run-daily-tests.sh` from the project directory. This suite covers UTC reset boundaries, duplicate days, gaps and best streaks, the 14 launch templates, fallback rotation, legacy decoding, and daily identity during merges. CloudKit setup and the physical-device acceptance checklist are in `Daily Templates/README.md`.
