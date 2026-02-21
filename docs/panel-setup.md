# BPB Panel API Setup Guide

This guide explains how to configure BPB Automation to update your panel using the BPB Panel API.

## When to Use This Method

Use Panel API mode when you prefer logging in to your panel directly (base URL + panel password) instead of creating a Cloudflare API token.

In the app, this is **Settings > Update Method > Panel API**.

## Required Information

You need two values:

1. **Panel Base URL** — your worker root URL (no path)
2. **Panel Password** — the password you use on the BPB panel login page

## Step 1: Find Your Panel Base URL

Use your worker root URL only:

```text
https://your-worker.workers.dev
```

Do not include `/panel` or other paths.  
If you paste a URL like `https://your-worker.workers.dev/panel`, the app auto-removes `/panel`.

## Step 2: Confirm Panel Password

Use the same password used for BPB panel login.

If you forgot it, reset it from the panel workflow and then update the app with the new password.

## Step 3: Enter in App

1. Open **Settings**
2. Set **Update Method** to **Panel API**
3. Enter:
   - **Panel Base URL**
   - **Panel Password**
4. Tap **Validate**
5. Tap **Save**

## Panel API Advanced Options

In **Settings > Update Method = Panel API**, these controls are available:

1. **Use proxy for panel update (Experimental)**
- Routes panel API requests through Xray + clean IP candidates.
- Use when direct panel calls are blocked or unstable.
- Marked Experimental because behavior depends heavily on network filtering quality.

2. **Enable panel proxy diagnostics**
- Runs extra checks (`GET /`, `GET /panel`, `POST /login/authenticate`) through the proxy route.
- Useful for debugging only.
- Increases apply time and log volume.

3. **Force clean IPs for panel when proxy is off**
- When proxy mode is OFF, panel API requests are sent directly to panel host using forced clean-IP rotation.
- Tries candidates until one succeeds.
- Useful when DNS/default routing is bad but direct TLS to selected clean IPs can work.

Recommended usage:
- Start with all advanced options OFF.
- If Panel API update fails on your network:
  1. Try **Force clean IPs for panel when proxy is off**
  2. If still failing, try **Use proxy for panel update (Experimental)**
  3. Enable diagnostics temporarily to collect logs, then disable it again

## How It Works

When you tap **Update BPB Panel** on the results screen, the app:

1. Calls `POST /login/authenticate`
2. Calls `GET /panel/settings`
3. Replaces `proxySettings.cleanIPs`
4. Calls `PUT /panel/update-settings`

The panel then writes updated settings to KV internally.

## Session Expiration

Panel JWT sessions can expire. The app handles this automatically:

- If update returns `401`, the app re-authenticates and retries once.

## Troubleshooting

### Validate fails

- Check base URL is correct and reachable
- Confirm password is correct
- Ensure URL is the worker root, not a path

### Update fails with unauthorized/session expired

- Re-validate in Settings
- Save again
- Retry update

### Web build issues

On Flutter Web, browser CORS/cookie restrictions can block Panel API calls.  
If this happens, switch to **Cloudflare API** mode in Settings.
