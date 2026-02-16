# Cloudflare Setup Guide

This guide explains how to obtain the Cloudflare credentials for BPB Automation.

## When Do You Need Credentials?

**Credentials are OPTIONAL.** You only need them if you want to automatically update your BPB Panel.

- **Without credentials**: You can scan and view clean IP lists
- **With credentials**: You can scan AND automatically update BPB Panel

## Required Information

You need three pieces of information:

1. **API Token** - For authentication
2. **Account ID** - Your Cloudflare account identifier
3. **KV Namespace ID** - The Workers KV namespace used by BPB Panel

## Step 1: Get Your Account ID

### Method 1: From Dashboard
1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Click on "Workers & Pages" in the left sidebar
3. Your Account ID is displayed in the right sidebar under "Account Details"

### Method 2: From URL
1. Go to any page in Cloudflare Dashboard
2. Look at the URL: `https://dash.cloudflare.com/{ACCOUNT_ID}/...`
3. The long alphanumeric string is your Account ID

**Example:** `0ab756f850d5aa60717a4c4df4e87f0a`

## Step 2: Find Your KV Namespace ID

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Click "Workers & Pages" in sidebar
3. Click "KV" in the submenu
4. Find your BPB Panel KV namespace (usually named like `kv-2026-02-12-18-54-28`)
5. Click on it
6. The Namespace ID is shown at the top

**Example:** `7e1cf251226d449697c75059fb236437`

### Alternative: From Workers Settings
1. Go to "Workers & Pages"
2. Click on your BPB Panel worker (e.g., `vmk4ji0z2sou4-ijd77ifxu0luu3rmrb`)
3. Go to "Settings" tab
4. Scroll to "Variables and Secrets" section
5. Look for KV Namespace Bindings
6. The ID is shown next to the namespace name

## Step 3: Create API Token

### Important Security Note
The API token gives access to your Cloudflare account. Keep it secure and never share it.

### Steps:
1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token"
3. Click "Create Custom Token"

### Token Configuration:

**Permissions:**
- Account → Workers KV Storage → Edit

**Account Resources:**
- Include → Your specific account

**Optional Settings:**
- Client IP Address Filtering: Add your IP for extra security
- TTL: Set expiration date (recommended)

### Template Configuration Example:
```
Token Name: BPB Clean IP Updater
Permissions:
  - Account | Workers KV Storage | Edit
Account Resources:
  - Include | [Your Account Name]
Client IP Address Filtering:
  - (Optional) Your IP address
TTL:
  - (Optional) 1 year
```

4. Click "Continue to summary"
5. Review permissions
6. Click "Create Token"
7. **COPY THE TOKEN IMMEDIATELY** - You won't be able to see it again

**Token Format:** Starts with letters and contains alphanumeric characters
**Example:** `4720857f4b06d8949bc9cc8e9bbcdf890`

## Step 4: Verify Your Credentials

You can test your credentials using curl:

```bash
# Test API token validity
curl -X GET "https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/storage/kv/namespaces/{NAMESPACE_ID}/values/proxySettings" \
  -H "Authorization: Bearer {API_TOKEN}" \
  -H "Content-Type: application/json"
```

Replace:
- `{ACCOUNT_ID}` with your Account ID
- `{NAMESPACE_ID}` with your KV Namespace ID
- `{API_TOKEN}` with your API Token

If successful, you'll receive the current proxySettings JSON.

## Step 5: Enter Credentials in App

1. Open BPB Automation
2. Go to Settings
3. Enter:
   - **Cloudflare API Token**: Paste your API token
   - **Account ID**: Paste your account ID
   - **KV Namespace ID**: Paste your namespace ID
4. Click "Save"
5. The app will validate the credentials

## Troubleshooting

### Error: Invalid API Token
- Check that you copied the full token
- Verify the token hasn't expired
- Ensure the token has Workers KV Storage Edit permission

### Error: Namespace Not Found
- Verify the Namespace ID is correct
- Check that the namespace belongs to the specified account
- Ensure your BPB Panel is properly set up

### Error: Permission Denied
- The API token needs "Workers KV Storage - Edit" permission
- Check that the token is for the correct account

### Error: Network Error
- Check your internet connection
- If using a VPN, try disabling it
- Cloudflare API might be temporarily unavailable

## Security Best Practices

1. **Never share your API token** - Treat it like a password
2. **Use IP filtering** - Restrict token to your IP addresses
3. **Set expiration** - Rotate tokens regularly
4. **Revoke if compromised** - Immediately revoke and create a new token
5. **Minimal permissions** - Only grant Workers KV Edit, nothing more

## Revoking a Token

If your token is compromised:

1. Go to [API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Find the token in the list
3. Click the three dots menu
4. Click "Revoke"
5. Create a new token following the steps above
6. Update the app with the new token

## Additional Resources

- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [Workers KV API Reference](https://developers.cloudflare.com/api/operations/workers-kv-namespace-list-namespaces)
- [BPB Panel Documentation](https://bia-pain-bache.github.io/BPB-Worker-Panel/)
