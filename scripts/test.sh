#!/bin/bash
# Warnings-as-errors build of both targets, then the automated (permission-free) test suite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$ROOT" -Xswiftc -warnings-as-errors
swift test --package-path "$ROOT"
