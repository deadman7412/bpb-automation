# macOS Scheduler Adapter (launchd)

Use `launchd` to run the same headless worker command on macOS.

## Files

- `com.bpb.automation.autoscan.plist` template LaunchAgent.
- `install-launchd.sh` helper to install/start/update the LaunchAgent.
- `uninstall-launchd.sh` helper to stop/remove the LaunchAgent.

## Quick Setup

1. Edit your `.env` file with real values (`BPB_SCAN_CMD`, tokens, etc.).
2. Run:

```bash
chmod +x backend/deploy/schedulers/macos/install-launchd.sh
backend/deploy/schedulers/macos/install-launchd.sh \
  --workspace /Users/<you>/bpb-automation \
  --env-file /Users/<you>/.config/bpb-autoscan.env \
  --interval-hours 6
```

3. Check status:

```bash
launchctl print gui/$(id -u)/com.bpb.automation.autoscan
```

## Notes

- LaunchAgent runs in the logged-in user session.
- For 24/7 unattended scheduling on servers, use Linux `systemd` instead.
- `launchd` timing is best-effort and not guaranteed to run at exact second.
