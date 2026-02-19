# BPB Panel API Reference

This document records the BPB Worker Panel routes exposed by the worker.

Source of truth used for this reference:
- `BPB Panel Source/src/worker.ts`
- `BPB Panel Source/src/common/handlers.ts`
- `BPB Panel Source/src/auth.ts`
- `BPB Panel Source/src/common/common.ts`

## Response Format

Most JSON API routes use this envelope:

```json
{
  "success": true,
  "status": 200,
  "message": null,
  "body": {}
}
```

Auth failures usually return `401` with `success: false`.

## Authentication Model

- Login route: `POST /login/authenticate`
- Credential: plain text panel password in request body
- Session: `jwtToken` cookie (`HttpOnly`, `Secure`)
- Protected routes require `Cookie: jwtToken=...`
- JWT expiration is `24h` in token claims

## Route Index

### Core Entry Points

- `GET /panel` — render panel UI (HTML). If password is set and no valid session, redirects to `/login`.
- `GET /login` — render login UI (HTML). If already authenticated, redirects to `/panel`.
- `POST /login/authenticate` — login and set `jwtToken` cookie.
- `GET /logout` — clear session cookie.
- `GET /secrets` — render secrets page (HTML).
- `GET /favicon.ico` — icon asset.

### Panel Settings API

- `GET /panel/settings`  
  Auth: required  
  Returns:
  - `body.proxySettings`
  - `body.isPassSet`
  - `body.subPath`

- `PUT /panel/update-settings`  
  Auth: required  
  Body: full panel settings object (`proxySettings` shape)  
  Behavior: updates dataset in KV and returns updated settings in `body`.

- `POST /panel/reset-settings`  
  Auth: required  
  Behavior: resets settings to defaults and writes to KV.

- `POST /panel/reset-password`  
  Auth: required if old password exists  
  Body: new password as plain text  
  Behavior: updates stored password and clears session cookie.

### Panel Utilities

- `/panel/my-ip`  
  Auth: none  
  Method: not restricted in handler  
  Body: IP string  
  Behavior: performs geo lookup via `ip-api.com` and returns result in `body`.

- `POST /panel/update-warp`  
  Auth: required  
  Behavior: refreshes warp accounts/config data.

- `/panel/get-warp-configs`  
  Auth: required  
  Method: not restricted in handler  
  Behavior: returns ZIP file of generated warp configs (`application/zip`).

### Subscription Endpoints

All subscription routes are path-based and use configured `subPath`:

- `GET /sub/normal/{subPath}`
- `GET /sub/fragment/{subPath}`
- `GET /sub/warp/{subPath}`
- `GET /sub/warp-pro/{subPath}`

Client type is selected with query `app=...`:

- `app=xray`
- `app=sing-box`
- `app=clash`
- `app=xray-knocker` (warp-pro path)

### DNS Route

- `/dns-query/{subPath}`  
  Proxies to configured DoH upstream.

### WebSocket Tunnel Route

- Encoded path (base64 JSON in path segment), parsed to protocol/mode/IP settings:
  - protocol `vl` or `tr`
  - dispatched to corresponding WS handler

## Notes For App Integrations

For automated clean IP updates, the minimal flow is:

1. `POST /login/authenticate` (store `jwtToken` cookie)
2. `GET /panel/settings`
3. Replace `proxySettings.cleanIPs`
4. `PUT /panel/update-settings` with full settings object

This is exactly what BPB Automation Panel API mode uses.

