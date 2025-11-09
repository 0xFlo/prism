defmodule GscAnalytics.DataSources.GSC.Support.Authenticator do
  @moduledoc """
  Manages Google Search Console API authentication using OAuth 2.0.

  The authenticator maintains a per-workspace token cache with automatic refresh.
  Tokens are refreshed proactively before expiration to ensure uninterrupted API access.

  ## Architecture

  Workspaces are stored in the database (see `GscAnalytics.Schemas.Workspace`).
  OAuth tokens are managed by `GscAnalytics.Auth` module.
  This GenServer provides a caching layer to minimize database lookups.

  ## Token Management

  - Tokens are cached in memory with expiry tracking
  - Auto-refresh is scheduled 5 minutes before token expiration
  - Failed refreshes trigger automatic retries
  """

  use GenServer
  require Logger

  alias GscAnalytics.Auth
  alias GscAnalytics.DataSources.GSC.Telemetry.AuditLogger
  alias GscAnalytics.Workspaces

  @type workspace_id :: Workspaces.workspace_id()

  @refresh_leading_time 300_000

  @type workspace_state :: %{
          token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          refresh_timer: reference() | nil,
          retry_timer: reference() | nil,
          last_error: term() | nil
        }

  # Public API ----------------------------------------------------------------

  def start_link(opts) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Retrieve a valid OAuth token for the given workspace.

  Returns `{:ok, token}` if available, `{:error, reason}` otherwise.
  """
  @spec get_token(workspace_id()) ::
          {:ok, String.t()} | {:error, :no_token | :workspace_not_found | term()}
  def get_token(workspace_id) when is_integer(workspace_id) do
    GenServer.call(__MODULE__, {:get_token, workspace_id})
  end

  @doc """
  Force a token refresh for the given workspace.
  """
  @spec refresh_token(workspace_id()) :: {:ok, String.t()} | {:error, term()}
  def refresh_token(workspace_id) when is_integer(workspace_id) do
    GenServer.call(__MODULE__, {:refresh_token, workspace_id})
  end

  # GenServer callbacks -------------------------------------------------------

  @impl true
  def init(_opts) do
    state = %{workspaces: %{}}
    {:ok, state}
  end

  @impl true
  def handle_call({:get_token, workspace_id}, _from, state) do
    case get_workspace_state(state, workspace_id) do
      nil ->
        # Workspace not in cache, try to fetch from database
        case fetch_token(state, workspace_id) do
          {new_state, {:ok, token}} -> {:reply, {:ok, token}, new_state}
          {new_state, {:error, reason}} -> {:reply, {:error, reason}, new_state}
        end

      %{token: token, expires_at: expires_at} ->
        cond do
          is_nil(token) || token_expired?(expires_at) ->
            case fetch_token(state, workspace_id, force?: true) do
              {new_state, {:ok, new_token}} -> {:reply, {:ok, new_token}, new_state}
              {new_state, {:error, reason}} -> {:reply, {:error, reason}, new_state}
            end

          true ->
            {:reply, {:ok, token}, state}
        end
    end
  end

  @impl true
  def handle_call({:refresh_token, workspace_id}, _from, state) do
    case fetch_token(state, workspace_id, force?: true) do
      {new_state, {:ok, token}} -> {:reply, {:ok, token}, new_state}
      {new_state, {:error, reason}} -> {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_info({:refresh_oauth_token, workspace_id}, state) do
    case refresh_oauth_token(state, workspace_id) do
      {new_state, {:ok, _token}} ->
        {:noreply, new_state}

      {new_state, {:error, reason}} ->
        Logger.error(
          "Failed to refresh OAuth token for workspace #{workspace_id}: #{inspect(reason)}"
        )

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:retry, :fetch_token, workspace_id}, state) do
    {new_state, _result} = fetch_token(state, workspace_id, force?: true)
    {:noreply, new_state}
  end

  # Internal helpers ----------------------------------------------------------

  defp fetch_token(state, workspace_id, opts \\ []) do
    force_refresh? = Keyword.get(opts, :force?, false)

    case Auth.get_oauth_token(nil, workspace_id) do
      {:ok, oauth_token} ->
        # Check if token needs re-authentication (invalid or expired status)
        if GscAnalytics.Auth.OAuthToken.needs_reauth?(oauth_token) do
          Logger.error(
            "OAuth token for workspace #{workspace_id} needs re-authentication (status: #{oauth_token.status})"
          )

          {state, {:error, :oauth_token_invalid}}
        else
          if needs_oauth_refresh?(oauth_token, force_refresh?) do
            refresh_oauth_token(state, workspace_id)
          else
            handle_oauth_success(state, workspace_id, oauth_token)
          end
        end

      {:error, :not_found} ->
        Logger.warning("No OAuth token found for workspace #{workspace_id}")
        {state, {:error, :oauth_not_configured}}

      {:error, reason} ->
        Logger.error("OAuth error for workspace #{workspace_id}: #{inspect(reason)}")
        {state, {:error, {:oauth_error, reason}}}
    end
  end

  defp needs_oauth_refresh?(oauth_token, force_refresh?) do
    force_refresh? ||
      token_expired?(oauth_token.expires_at) ||
      not present_access_token?(oauth_token.access_token)
  end

  defp refresh_oauth_token(state, workspace_id) do
    case Auth.refresh_oauth_access_token(nil, workspace_id) do
      {:ok, refreshed} ->
        handle_oauth_success(state, workspace_id, refreshed)

      {:error, :oauth_token_invalid} = error ->
        # Token has been revoked/expired - database already updated by Auth module
        Logger.error(
          "OAuth token is invalid for workspace #{workspace_id} - re-authentication required"
        )

        state =
          state
          |> cancel_refresh(workspace_id)
          |> put_workspace(workspace_id, %{
            last_error: :oauth_token_invalid,
            token: nil,
            expires_at: nil
          })

        {state, error}

      {:error, reason} ->
        Logger.error(
          "OAuth token refresh failed for workspace #{workspace_id}: #{inspect(reason)}"
        )

        state =
          state
          |> cancel_refresh(workspace_id)
          |> put_workspace(workspace_id, %{last_error: reason, token: nil, expires_at: nil})

        {state, {:error, {:oauth_refresh_failed, reason}}}
    end
  end

  defp handle_oauth_success(state, workspace_id, %{access_token: access_token} = token)
       when is_binary(access_token) and access_token != "" do
    expires_at = token.expires_at

    AuditLogger.log_auth_event("oauth_token_available", %{
      account_id: workspace_id,
      expires_at: maybe_iso8601(expires_at)
    })

    Logger.info(
      "Using OAuth token for workspace #{workspace_id}; token expires #{format_expiry_from_datetime(expires_at)}"
    )

    state =
      state
      |> put_workspace(workspace_id, %{
        token: access_token,
        expires_at: expires_at,
        last_error: nil
      })
      |> cancel_retry(workspace_id)
      |> schedule_oauth_refresh(workspace_id, expires_at)

    {state, {:ok, access_token}}
  end

  defp handle_oauth_success(state, workspace_id, _token) do
    Logger.error("OAuth token for workspace #{workspace_id} is missing an access token")

    state =
      state
      |> cancel_refresh(workspace_id)
      |> put_workspace(workspace_id, %{
        last_error: :missing_access_token,
        token: nil,
        expires_at: nil
      })

    {state, {:error, :missing_access_token}}
  end

  # State management helpers --------------------------------------------------

  defp get_workspace_state(state, workspace_id) do
    Map.get(state.workspaces, workspace_id)
  end

  defp put_workspace(state, workspace_id, updates) do
    update_in(state, [:workspaces, workspace_id], fn existing ->
      (existing ||
         %{
           token: nil,
           expires_at: nil,
           refresh_timer: nil,
           retry_timer: nil,
           last_error: nil
         })
      |> Map.merge(updates)
    end)
  end

  defp schedule_oauth_refresh(state, workspace_id, %DateTime{} = expires_at) do
    now = DateTime.utc_now()
    time_until_expiry = max(DateTime.diff(expires_at, now, :millisecond), 0)
    refresh_in = max(time_until_expiry - @refresh_leading_time, 0)

    state
    |> cancel_refresh(workspace_id)
    |> put_workspace(workspace_id, %{
      refresh_timer: Process.send_after(self(), {:refresh_oauth_token, workspace_id}, refresh_in)
    })
  end

  defp schedule_oauth_refresh(state, _workspace_id, _expires_at), do: state

  defp cancel_refresh(state, workspace_id) do
    case get_in(state, [:workspaces, workspace_id, :refresh_timer]) do
      nil ->
        state

      timer ->
        Process.cancel_timer(timer)
        put_workspace(state, workspace_id, %{refresh_timer: nil})
    end
  end

  defp cancel_retry(state, workspace_id) do
    case get_in(state, [:workspaces, workspace_id, :retry_timer]) do
      nil ->
        state

      timer ->
        Process.cancel_timer(timer)
        put_workspace(state, workspace_id, %{retry_timer: nil})
    end
  end

  # Token validation helpers --------------------------------------------------

  defp token_expired?(nil), do: true

  defp token_expired?(%DateTime{} = expires_at) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end

  defp present_access_token?(nil), do: false
  defp present_access_token?(""), do: false
  defp present_access_token?(token) when is_binary(token), do: true

  # Formatting helpers --------------------------------------------------------

  defp format_expiry_from_datetime(nil), do: "never"

  defp format_expiry_from_datetime(datetime) do
    case DateTime.compare(datetime, DateTime.utc_now()) do
      :lt -> "expired"
      _ -> "at #{DateTime.to_iso8601(datetime)}"
    end
  end

  defp maybe_iso8601(nil), do: nil
  defp maybe_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
