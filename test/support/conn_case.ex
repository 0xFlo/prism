defmodule GscAnalyticsWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use GscAnalyticsWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint GscAnalyticsWeb.Endpoint

      use GscAnalyticsWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import GscAnalyticsWeb.ConnCase
    end
  end

  setup tags do
    GscAnalytics.DataCase.setup_sandbox(tags)
    conn = Phoenix.ConnTest.build_conn()
    conn = Phoenix.ConnTest.init_test_session(conn, %{})
    {:ok, conn: conn}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection, a registered user, a workspace, and an active property
  in the test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = GscAnalytics.AuthFixtures.user_fixture()
    workspace = GscAnalytics.AccountsFixtures.workspace_fixture(user: user)

    # Create an active property for the workspace
    {:ok, property} =
      GscAnalytics.Repo.insert(%GscAnalytics.Schemas.WorkspaceProperty{
        id: Ecto.UUID.generate(),
        workspace_id: workspace.id,
        property_url: "sc-domain:test-#{System.unique_integer([:positive])}.com",
        display_name: "Test Property",
        is_active: true
      })

    scope = GscAnalytics.Auth.Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{
      conn: log_in_user(conn, user, opts),
      user: user,
      scope: scope,
      workspace: workspace,
      property: property
    }
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = GscAnalytics.Auth.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    GscAnalytics.AuthFixtures.override_token_authenticated_at(token, authenticated_at)
  end

  @doc """
  Follows a LiveView redirect or live_redirect to the final destination.

  This helper allows tests to handle redirects transparently, testing the
  observable behavior (user sees properties) rather than implementation details
  (routing logic).

  ## Examples

      {:ok, view, html} = follow_live_redirect(conn, ~p"/dashboard")
      assert html =~ "expected content"
  """
  defmacro follow_live_redirect(conn, path) do
    quote do
      import Phoenix.LiveViewTest

      case live(unquote(conn), unquote(path)) do
        {:ok, view, html} ->
          {:ok, view, html}

        {:error, {:redirect, %{to: redirect_path}}} ->
          live(unquote(conn), redirect_path)

        {:error, {:live_redirect, %{to: redirect_path}}} ->
          live(unquote(conn), redirect_path)
      end
    end
  end
end
