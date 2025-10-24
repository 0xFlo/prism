# Repository Guidelines

## Project Structure & Module Organization

Elixir application code lives in `lib/gsc_analytics`, while LiveViews, components, and routing stay under `lib/gsc_analytics_web`. Static assets and Tailwind/ESBuild entrypoints are in `assets`, database scripts and seeds sit in `priv/repo`, and integration fixtures plus support helpers are under `test` and `test/support`. Mix configuration lives in `mix.exs`; runtime configuration is managed through the files in `config/`.

## Build, Test, and Development Commands

- `mix setup` — install dependencies, prepare the database, and build frontend assets.
- `mix phx.server` — boot the Phoenix dev server with code reloading.
- `mix assets.build` — recompile Tailwind and ESBuild bundles without running the server.
- `mix ecto.migrate` — apply pending migrations; pair with `mix ecto.reset` when reseeding locally.
- `mix precommit` — run compilation with warnings-as-errors, purge unused dependency locks, format, and execute the test suite.

## Coding Style & Naming Conventions

Follow the default Elixir formatter via `mix format`; keep two-space indentation and pipeline-friendly function ordering (pure helpers above public API). Web modules should follow the `GscAnalyticsWeb.FooLive` / `GscAnalyticsWeb.FooHTML` naming convention, and always wrap LiveView templates with `<Layouts.app flash={@flash} current_scope={@current_scope}>`. Prefer the built-in `<.input>`, `<.icon>`, and `Req` HTTP client, and style UI exclusively with Tailwind utility classes.

## Testing Guidelines

Use `mix test` for the full suite and `mix test --failed` to re-run the last failures. Feature tests rely on `Phoenix.LiveViewTest` plus `LazyHTML`; target elements by stable IDs (`#report-form`, `#metrics-table`) rather than brittle text assertions. When streaming collections, assert against `@streams.*` renders and include coverage for empty-state helpers. Add fixtures or factories in `test/support` to keep scenarios isolated.

## Commit & Pull Request Guidelines

Match the existing Conventional Commit style (`feat:`, `fix:`, `refactor:`). Each PR should link relevant issues, outline user-visible changes, and include screenshots or GIFs for LiveView/UI updates. Ensure `mix precommit` passes before pushing, note any skipped steps, and call out migrations or config changes in the PR description.

## Security & Configuration Tips

Keep secrets in environment variables consumed by `config/runtime.exs`; never commit `.env` files. HTTP integrations must use the bundled `Req` client with scoped OAuth tokens stored securely. Review rate-limited flows (`Hammer`) when adding new API calls and document required environment keys in `README.md`.

✅ ALWAYS use built-in JSON module (Elixir v1.18+)
❌ NEVER use Jason
❌ NEVER alias Jason as JSON

Jason is only a transitive dependency (Phoenix brings it in). Since we have native JSON support, we should
use it exclusively.


<!-- phoenix-gen-auth-start -->
## Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `phx.gen.auth` creates multiple router plugs and `live_session` scopes:
  - A plug `:fetch_current_scope_for_user` that is included in the default browser pipeline
  - A plug `:require_authenticated_user` that redirects to the log in page when the user is not authenticated
  - A `live_session :current_user` scope - for routes that need the current user but don't require authentication, similar to `:fetch_current_scope_for_user`
  - A `live_session :require_authenticated_user` scope - for routes that require authentication, similar to the plug with the same name
  - In both cases, a `@current_scope` is assigned to the Plug connection and LiveView socket
  - A plug `redirect_if_user_is_authenticated` that redirects to a default path in case the user is authenticated - useful for a registration page that should only be shown to unauthenticated users
- **Always let the user know in which router scopes, `live_session`, and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `current_scope` assign - it **does not assign a `current_user` assign**
- Always pass the assign `current_scope` to context modules as first argument. When performing queries, use `current_scope.user` to filter the query results
- To derive/access `current_user` in templates, **always use the `@current_scope.user`**, never use **`@current_user`** in templates or LiveViews
- **Never** duplicate `live_session` names. A `live_session :current_user` can only be defined __once__ in the router, so all routes for the `live_session :current_user`  must be grouped in a single block
- Anytime you hit `current_scope` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct plug and `live_session` as described below**

### Routes that require authentication

LiveViews that require login should **always be placed inside the __existing__ `live_session :require_authenticated_user` block**:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      live_session :require_authenticated_user,
        on_mount: [{GscAnalyticsWeb.UserAuth, :require_authenticated}] do
        # phx.gen.auth generated routes
        live "/users/settings", UserLive.Settings, :edit
        live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
        # our own routes that require logged in user
        live "/", MyLiveThatRequiresAuth, :index
      end
    end

Controller routes must be placed in a scope that sets the `:require_authenticated_user` plug:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      get "/", MyControllerThatRequiresAuth, :index
    end

### Routes that work with or without authentication

LiveViews that can work with or without authentication, **always use the __existing__ `:current_user` scope**, ie:

    scope "/", MyAppWeb do
      pipe_through [:browser]

      live_session :current_user,
        on_mount: [{GscAnalyticsWeb.UserAuth, :mount_current_scope}] do
        # our own routes that work with or without authentication
        live "/", PublicLive
      end
    end

Controllers automatically have the `current_scope` available if they use the `:browser` pipeline.

<!-- phoenix-gen-auth-end -->