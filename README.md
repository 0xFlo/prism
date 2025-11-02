# GscAnalytics

## Getting Started

- Install dependencies and prepare the database with `mix setup`
- Start the development server via `mix phx.server`
- Visit http://localhost:4000 after logging in through the generated auth flow

Running `mix precommit` executes compilation, formatting, and the test suite before opening a pull request.

## Google OAuth Configuration

Personal Google connections are managed from `http://localhost:4000/users/settings#connections`. Configure the following environment variables before starting the server:

```bash
export GOOGLE_OAUTH_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export GOOGLE_OAUTH_CLIENT_SECRET="your-client-secret"
export GOOGLE_OAUTH_REDIRECT_URI="http://localhost:4000/auth/google/callback"
# Required outside dev/test to encrypt stored refresh tokens
export CLOAK_KEY="ZzkKpsL01gl7QvRP1ThEmypkny/XrLaM/3FrfIjtNuA="
```

`CLOAK_KEY` must be a stable, Base64-encoded 32-byte value (run `mix phx.gen.secret 32` to generate one). Production nodes will refuse to boot if the variable is missing so that encrypted OAuth tokens remain readable after deploys.

The redirect URI must match the value registered in the Google Cloud Console for the OAuth client (typically `http://localhost:4000/auth/google/callback` in development).

Alternatively, you can drop the downloaded Google OAuth JSON bundle into the project root (for example `client_secret_97774....json`). The runtime will auto-detect the file if `GOOGLE_OAUTH_CLIENT_ID` / `_SECRET` are not set. Keep the file out of version control—it is already covered by `.gitignore`.

## Search Console Account Configuration

Account metadata is driven by `config :gsc_analytics, :gsc_accounts`:

- Account 1 (Scrapfly) always uses the bundled service account located at `priv/production-284316-43f352dd1cda.json`
- `GSC_ACCOUNT_1_NAME` / `GSC_ACCOUNT_2_NAME` override the display labels shown in settings (defaults: `Workspace 1`, `Workspace 2`)
- `GSC_ACCOUNT_2_SERVICE_ACCOUNT_FILE` (optional) re-enables the legacy service-account fallback for Account 2; leave it unset to require OAuth
- `GSC_ACCOUNT_2_PROPERTY` seeds the initial default property for Account 2. Once connected via OAuth you can pick (and store) the property from *Settings ▸ Search Console Connections*.

All paths can be absolute or relative to the project root.

After exporting the variables, restart the Phoenix server to pick up the new configuration and connect Google accounts from the settings page.
