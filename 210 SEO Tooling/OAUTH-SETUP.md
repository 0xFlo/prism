# Google OAuth Setup for GSC Analytics

## Overview

This guide explains how to set up Google OAuth2 credentials for Account 2 (Alba Analytics) to access GSC properties via your i@alba.cc Google account.

## Step 1: Create OAuth 2.0 Credentials in Google Cloud Console

1. **Go to Google Cloud Console**
   - Navigate to: https://console.cloud.google.com/
   - Select project: `alba-analytics-475918`

2. **Enable Required APIs**
   - Go to "APIs & Services" → "Enable APIs and Services"
   - Search for and enable: **Google Search Console API**

3. **Create OAuth 2.0 Client ID**
   - Go to "APIs & Services" → "Credentials"
   - Click "+ CREATE CREDENTIALS" → "OAuth client ID"
   - Application type: **Web application**
   - Name: `GSC Analytics Dashboard - Development`

4. **Configure Authorized Redirect URIs**
   Add these URIs:
   - Development: `http://localhost:4000/auth/google/callback`
   - Production: `https://your-production-domain.com/auth/google/callback` (add later)

5. **Download Credentials**
   - After creating, you'll see a modal with your:
     - **Client ID**: `XXXXXXXXX.apps.googleusercontent.com`
     - **Client secret**: `GOCSPX-XXXXXXXXXXXXXXXXX`
   - Keep these secret!

## Step 2: Configure OAuth in Your Application

1. **Create `config/dev.secret.exs`** (this file is gitignored):

```elixir
import Config

# Google OAuth2 credentials for GSC Analytics
config :gsc_analytics, :google_oauth,
  client_id: "YOUR_CLIENT_ID_HERE.apps.googleusercontent.com",
  client_secret: "YOUR_CLIENT_SECRET_HERE",
  redirect_uri: "http://localhost:4000/auth/google/callback"
```

2. **Import the secret config in `config/dev.exs`**:

Add at the end of `config/dev.exs`:
```elixir
# Import secret OAuth credentials (not committed to git)
import_config "dev.secret.exs"
```

3. **Add to `.gitignore`** (ensure these lines exist):
```
/config/dev.secret.exs
/config/prod.secret.exs
```

## Step 3: Production Setup (Later)

For production, use environment variables instead of config files:

```elixir
# config/runtime.exs
config :gsc_analytics, :google_oauth,
  client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_OAUTH_CLIENT_SECRET"),
  redirect_uri: System.get_env("GOOGLE_OAUTH_REDIRECT_URI")
```

Set these environment variables on your production server:
```bash
export GOOGLE_OAUTH_CLIENT_ID="your_client_id"
export GOOGLE_OAUTH_CLIENT_SECRET="your_client_secret"
export GOOGLE_OAUTH_REDIRECT_URI="https://yourdomain.com/auth/google/callback"
export CLOAK_KEY="your_base64_encoded_encryption_key"
```

## OAuth Scopes

The application requests these scopes:
- `https://www.googleapis.com/auth/webmasters.readonly` - Read-only GSC access
- `email` - Identify which Google account is connected

## Security Notes

✅ **Encryption**: Refresh tokens are encrypted at rest using AES-GCM
✅ **HTTPS Only**: OAuth flow MUST use HTTPS in production
✅ **Gitignored**: Never commit client_secret to version control
✅ **Per-Account**: One Google account per dashboard account (Account 2 = i@alba.cc)

## Testing the Setup

1. Register a user account at `/users/register`
2. Log in at `/users/log-in`
3. Visit Account 2 settings (once UI is built)
4. Click "Connect Google Account"
5. Authorize as i@alba.cc
6. Verify token is stored and you can access Alba clients' GSC properties

## Troubleshooting

**"redirect_uri_mismatch" error:**
- Check that the redirect URI in Google Cloud Console EXACTLY matches the one in your config
- Common mistake: `http://` vs `https://`, trailing slash, port number

**"invalid_client" error:**
- Verify client_id and client_secret are correct
- Check that the OAuth credentials are for the correct Google Cloud project

**"access_denied" error:**
- User clicked "Cancel" during authorization
- Try the flow again

## Next Steps

After OAuth is set up:
1. Modify `Authenticator` to support OAuth token flow
2. Build Account Settings UI with "Connect Google Account" button
3. Test syncing Account 2 data via OAuth
4. Verify data isolation between Account 1 (service account) and Account 2 (OAuth)
