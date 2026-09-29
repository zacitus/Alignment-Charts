#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/alignment-collaboration-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
sources_dir="$project_dir/Alignment Charts MessagesExtension"
xcrun swiftc -parse-as-library \
  "$sources_dir/Models/ChartCell.swift" \
  "$sources_dir/Models/ChartState.swift" \
  "$sources_dir/Models/TierState.swift" \
  "$sources_dir/Models/ChartContent.swift" \
  "$sources_dir/Daily/DailyModels.swift" \
  "$sources_dir/Models/ChartMerge.swift" \
  "$sources_dir/Models/ChartSync.swift" \
  "$sources_dir/Persistence/ChartHistoryStore.swift" \
  "$project_dir/Tests/CollaborationTests.swift" \
  -o "$test_dir/collaboration-tests"
"$test_dir/collaboration-tests"
