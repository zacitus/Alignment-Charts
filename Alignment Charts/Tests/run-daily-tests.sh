#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/alignment-daily-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
sources_dir="$project_dir/Alignment Charts MessagesExtension"
xcrun swiftc -parse-as-library \
  "$sources_dir/Models/ChartCell.swift" \
  "$sources_dir/Models/ChartState.swift" \
  "$sources_dir/Models/TierState.swift" \
  "$sources_dir/Models/ChartMerge.swift" \
  "$sources_dir/Models/TierMerge.swift" \
  "$sources_dir/Daily/DailyModels.swift" \
  "$project_dir/Tests/DailyTests.swift" \
  -o "$test_dir/daily-tests"
"$test_dir/daily-tests" "$sources_dir/Daily/DailyTemplates.json"
