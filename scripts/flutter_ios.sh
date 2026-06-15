#!/usr/bin/env bash
# CocoaPods on macOS system Ruby 2.6 needs Logger before ActiveSupport.
# Use scripts/pod (see scripts/pod) so `flutter run` can find a working `pod`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/scripts:$PATH"
cd "$ROOT"
exec flutter "$@"
