# Dexcom Share for Omarchy (unofficial)

Unofficial Omarchy bar widget for **followers and caregivers** who already use Dexcom Share. Best-effort community visibility on the desktop — not a Dexcom product, not affiliated with Dexcom, and not meant to compete with or harm Dexcom.

Shows live glucose (mg/dL), trend arrow, history chart (1h / 4h / 12h / 24h), and snap-to hover readout.

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

Thresholds live on the bar entry in `~/.config/omarchy/shell.json` (`lowMgdl`, `highMgdl`, `urgentLowMgdl`, `urgentHighMgdl`).

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

## Disclaimer

**Not a medical device.** For informational monitoring only — do not use for treatment decisions. Always follow your clinician’s guidance and your CGM/pump’s own alerts.

**Not affiliated with Dexcom, Inc.** Dexcom® and Dexcom Share® are trademarks of their respective owners. This project is an independent, good-faith community effort for people who use Dexcom CGM (or follow a loved one) and want desktop visibility under Omarchy.

## License

MIT
