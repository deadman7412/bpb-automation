# Android Scheduler Adapter Plan (WorkManager)

Use Android WorkManager for periodic background execution.

## Goal

Trigger the same logical operation as server `run-once`:

1. Run scan flow
2. Apply updates if configured
3. Persist run metadata/history
4. Write logs with retention policy

## Implementation Outline

1. Add a background worker entrypoint in Flutter (plugin-backed).
2. Schedule periodic work (`15m+` minimum interval; practical: `6h`).
3. In worker:
   - enforce single active run guard
   - call internal scan orchestration service
   - persist run summary in same schema as server mode
4. Respect battery/network constraints:
   - require network connectivity
   - avoid running in low battery mode unless charging

## Notes

- Android scheduling is best-effort and can be deferred by OS power policy.
- Do not rely on exact execution minute.
- Keep run id/status schema aligned with backend API schema for UI consistency.
