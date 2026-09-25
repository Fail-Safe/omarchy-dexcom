# Development

Technical notes for working on **failsafe.dexcom**. End-user install and everyday use live in [README.md](README.md).

## Local development install

Clone or symlink this repo into the Omarchy plugins directory:

```sh
# example: symlink from a checkout
ln -sfn /path/to/omarchy-dexcom ~/.config/omarchy/plugins/failsafe.dexcom

omarchy plugin validate ~/.config/omarchy/plugins/failsafe.dexcom
omarchy-shell shell rescanPlugins
omarchy plugin enable failsafe.dexcom --section right
```

`DexcomModel.js` is a QML `.pragma library` — after changing it, run `omarchy-restart-shell` (or `omarchy restart shell`) so the singleton reloads.

## Credentials (dev)

Same file as end users: `~/.config/omarchy/dexcom-share.json` (mode `600`, regular file, not a symlink). Example:

```sh
cp dexcom-share.example.json ~/.config/omarchy/dexcom-share.json
chmod 600 ~/.config/omarchy/dexcom-share.json
```

Optional override:

```sh
omarchy bar set failsafe.dexcom credentialsPath /path/to/creds.json
```

## IPC

```sh
omarchy-shell failsafe.dexcom status
omarchy-shell failsafe.dexcom refresh
omarchy-shell failsafe.dexcom pause
omarchy-shell failsafe.dexcom resume
```

## Settings reference

Options are stored on the bar entry in `~/.config/omarchy/shell.json`. There is no settings GUI; use `omarchy bar set`:

```sh
omarchy bar set failsafe.dexcom glucoseUnit mmol/L
omarchy bar set failsafe.dexcom glucoseUnit mg/dL

omarchy bar set failsafe.dexcom lowMgdl 70
omarchy bar set failsafe.dexcom highMgdl 180
omarchy bar set failsafe.dexcom urgentLowMgdl 54
omarchy bar set failsafe.dexcom urgentHighMgdl 250

omarchy bar set failsafe.dexcom credentialsPath ~/.config/omarchy/dexcom-share.json
omarchy bar set failsafe.dexcom refreshIntervalSec 60
```

| Key | Default | Notes |
|-----|---------|--------|
| `glucoseUnit` | `mg/dL` | `mg/dL` or `mmol/L` — display only (÷ 18) |
| `lowMgdl` | `70` | Low threshold, always mg/dL |
| `highMgdl` | `180` | High threshold, always mg/dL |
| `urgentLowMgdl` | `54` | Urgent low, always mg/dL |
| `urgentHighMgdl` | `250` | Urgent high, always mg/dL |
| `refreshIntervalSec` | `60` | 30–600 |
| `credentialsPath` | _(empty)_ | Empty → `~/.config/omarchy/dexcom-share.json` |

Rough mmol/L equivalents: 54 → 3.0, 70 → 3.9, 180 → 10.0, 250 → 13.9.

## Tests

No network required. Needs `node` and `python3`:

```sh
./tests/run.sh
# or:
node tests/test_model.js
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Covers `DexcomModel.js` (trends, units, payload parsing, range-colored segments) and `dexcom_fetch.py` (credentials, normalize, session cache, mocked login/glucose).

## Architecture notes

- Share fetches go through `dexcom_fetch.py` (Python 3 stdlib only). Password stays in the credentials file — never on argv beyond the file path.
- Credential and session-cache files use no-follow open checks (owner / mode / size); session cache is written via temp file + atomic replace under `~/.cache/omarchy-dexcom/`.
- HTTP responses are size-capped; each exchange also has a wall-clock deadline so a trickling peer cannot leave the service stuck in `checking`.
- Uses the community Dexcom Share publisher API (same class of approach as Nightscout / pydexcom). Dexcom may change or break that API at any time.
- Chart colors follow each historical value’s range (not only the current reading). Share’s `Flat` trend is shown as **Steady**.

## Previews

- Marketplace hero: root `preview.png`
- Extra README shots: `docs/preview-steady.png`, `docs/preview-1h-low.png`

When replacing screenshots, prefer a tight panel crop (optional thin bar strip with the glucose chip) and avoid wallpaper chrome.
