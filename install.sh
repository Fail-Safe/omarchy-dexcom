#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_real="$(realpath -m "$repo_dir")"
plugin_id="$(jq -r .id "$repo_dir/manifest.json")"
target_dir="$HOME/.config/omarchy/plugins/$plugin_id"
creds="$HOME/.config/omarchy/dexcom-share.json"

omarchy plugin validate "$repo_dir"
mkdir -p "$(dirname "$target_dir")"
if [[ "$repo_real" != "$(realpath -m "$target_dir")" ]]; then
  if [[ -e "$target_dir" && ! -L "$target_dir" ]]; then
    echo "Refusing to replace existing non-symlink: $target_dir" >&2
    exit 1
  fi
  ln -sfn "$repo_dir" "$target_dir"
fi

if [[ ! -f "$creds" ]]; then
  cp "$repo_dir/dexcom-share.example.json" "$creds"
  chmod 600 "$creds"
  echo "Created $creds — edit accountName/password before use."
fi

omarchy-shell shell rescanPlugins >/dev/null || true
omarchy plugin enable "$plugin_id" --section right --before omarchy.network || omarchy plugin enable "$plugin_id" --section right
echo "Installed $plugin_id"
