#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
node tests/test_model.js
python3 -m unittest discover -s tests -p 'test_*.py' -v
printf '%s\n' "All tests passed"
