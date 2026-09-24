# Dexcom Share for Omarchy (unofficial)

Unofficial Omarchy bar widget for **followers and caregivers** who already use Dexcom Share. Best-effort community visibility on the desktop — not a Dexcom product, not affiliated with Dexcom, and not meant to compete with or harm Dexcom.

Shows live glucose (**mg/dL** or **mmol/L**), trend arrow, history chart (1h / 4h / 12h / 24h), and snap-to hover readout.

![Dexcom Share panel with range-colored 12h chart and Single-Down reading](preview.png)

![Dexcom Share panel with Steady reading and in-range history](docs/preview-steady.png)

![Dexcom Share 1h chart ending low with Single-Down](docs/preview-1h-low.png)

## Install

```sh
omarchy plugin add https://github.com/Fail-Safe/omarchy-dexcom.git --enable
```

Then create Share credentials (never commit this file):

```sh
cp ~/.config/omarchy/plugins/failsafe.dexcom/dexcom-share.example.json ~/.config/omarchy/dexcom-share.json
chmod 600 ~/.config/omarchy/dexcom-share.json
# edit accountName, password, region (us or ous)
```

The credentials file must be a regular file owned by your user, mode `600` (not group/world-readable, not a symlink).

For local development, clone this repo into `~/.config/omarchy/plugins/failsafe.dexcom` (or symlink it), then:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/failsafe.dexcom
omarchy-shell shell rescanPlugins
omarchy plugin enable failsafe.dexcom --section right
```

## Use

- Left click: detail panel (chart + ranges)
- Middle click: refresh
- Right click: pause/resume

```sh
omarchy-shell failsafe.dexcom status
omarchy-shell failsafe.dexcom refresh
```

## Settings

There is no settings GUI for this widget. Options live on the bar entry in
`~/.config/omarchy/shell.json` and are changed with `omarchy bar set`:

```sh
# Display unit: mg/dL (default) or mmol/L (÷ 18)
omarchy bar set failsafe.dexcom glucoseUnit mmol/L
omarchy bar set failsafe.dexcom glucoseUnit mg/dL

# Thresholds (always stored in mg/dL, even when displaying mmol/L)
omarchy bar set failsafe.dexcom lowMgdl 70
omarchy bar set failsafe.dexcom highMgdl 180
omarchy bar set failsafe.dexcom urgentLowMgdl 54
omarchy bar set failsafe.dexcom urgentHighMgdl 250

# Optional credentials path (default: ~/.config/omarchy/dexcom-share.json)
omarchy bar set failsafe.dexcom credentialsPath ~/.config/omarchy/dexcom-share.json

# Refresh interval in seconds (30–600)
omarchy bar set failsafe.dexcom refreshIntervalSec 60
```

| Key | Default | Notes |
|-----|---------|--------|
| `glucoseUnit` | `mg/dL` | `mg/dL` or `mmol/L` — display only |
| `lowMgdl` | `70` | Low threshold, always mg/dL |
| `highMgdl` | `180` | High threshold, always mg/dL |
| `urgentLowMgdl` | `54` | Urgent low, always mg/dL |
| `urgentHighMgdl` | `250` | Urgent high, always mg/dL |
| `refreshIntervalSec` | `60` | 30–600 |
| `credentialsPath` | _(empty)_ | Empty → `~/.config/omarchy/dexcom-share.json` |

Rough mmol/L equivalents: 54 → 3.0, 70 → 3.9, 180 → 10.0, 250 → 13.9.

## Remove

```sh
omarchy plugin remove failsafe.dexcom --yes
```

## Notes

- Uses the community Dexcom Share publisher API (same approach as Nightscout / pydexcom). Dexcom may change or break that API at any time.
- Password is read from the credentials file only — never passed on the process command line beyond the file path.
- Credential and session-cache files are opened with no-follow checks (owner/mode/size); the session cache is written via exclusive temp + atomic replace.
- Remote Share responses are size-capped while reading.
- Session id is cached under `~/.cache/omarchy-dexcom/`.

## Tests

No network required. Needs `node` and `python3`:

```sh
./tests/run.sh
# or individually:
node tests/test_model.js
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Covers `DexcomModel.js` helpers (trends, units, payload parsing) and `dexcom_fetch.py` (credentials, normalize, session cache, mocked login/glucose).

## Disclaimer

**Not a medical device.** For informational monitoring only — do not use for treatment decisions. Always follow your clinician’s guidance and your CGM/pump’s own alerts.

**Not affiliated with Dexcom, Inc.** Dexcom® and Dexcom Share® are trademarks of their respective owners. This project is an independent, good-faith community effort for people who use Dexcom CGM (or follow a loved one) and want desktop visibility under Omarchy.

## License

MIT
