#!/usr/bin/env bash
set -euo pipefail
plugin_id="failsafe.dexcom"
omarchy plugin remove "$plugin_id" --yes
