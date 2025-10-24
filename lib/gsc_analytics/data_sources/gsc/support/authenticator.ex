defmodule GscAnalytics.DataSources.GSC.Support.Authenticator do
  @moduledoc """
  Manages Google Search Console API authentication using service accounts.

  The authenticator now supports multiple service accounts by keeping a per-account
  credential and token cache. Tokens are refreshed proactively and retries are
  automatically scheduled when refreshes fail.
  """

  use GenServer
  require Logger

  alias GscAnalytics.DataSources.GSC.Accounts
  alias GscAnalytics.DataSources.GSC.Telemetry.AuditLogger

  @google_token_url "https://oauth2.googleapis.com/token"
  @google_auth_scope "https://www.googleapis.com/auth/webmasters.readonly"

  @type account_id :: Accounts.account_id()

  @type account_state :: %{
          credentials: map() | nil,
          token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          refresh_timer: reference() | nil,
          retry_timers: %{optional(atom()) => reference()},
          last_error: term() | nil
        }

  # Public API ----------------------------------------------------------------

  def start_link(opts) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Retrieve a valid OAuth token for the given account.
  """
  @spec get_token(account_id()) ::
          {:ok, String.t()} | {:error, :no_token | :account_disabled | :unknown_account | term()}
  def get_token(account_id) when is_integer(account_id) do
    GenServer.call(__MODULE__, {:get_token, account_id})
  end

  @doc """
  Force a token refresh for the given account.
  """
  @spec refresh_token(account_id()) ::
          {:ok, String.t()} | {:error, :missing_credentials | :unknown_account | term()}
  def refresh_token(account_id) when is_integer(account_id) do
    GenServer.call(__MODULE__, {:refresh_token, account_id})
  end

  @doc """
  Load new credentials from a JSON string for the given account.
  Primarily used in tests or when rotating keys without disk access.
  """
  @spec load_credentials(account_id(), String.t()) ::
          :ok | {:error, term()}
  def load_credentials(account_id, credentials_json)
      when is_integer(account_id) and is_binary(credentials_json) do
    GenServer.call(__MODULE__, {:load_credentials, account_id, credentials_json})
  end

  # GenServer callbacks -------------------------------------------------------

  @impl true
  def init(_opts) do
    state = %{accounts: %{}}
    {:ok, state, {:continue, :bootstrap_accounts}}
  end

  @impl true
  def handle_continue(:bootstrap_accounts, state) do
    new_state =
      Accounts.list_accounts()
      |> Enum.reduce(state, fn account, acc ->
        acc_with_creds =
          acc
          |> ensure_account_entry(account.id)
          |> maybe_load_credentials_from_disk(account.id, account.service_account_file)

        # Handle the tuple return from maybe_fetch_token
        case maybe_fetch_token(acc_with_creds, account.id) do
          {updated_state, _result} -> updated_state
        end
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_token, account_id}, _from, state) do
    with {:ok, _account} <- Accounts.fetch_account(account_id) do
      case Map.get(state.accounts, account_id) do
        nil ->
          {:reply, {:error, :unknown_account}, state}

        %{token: token, expires_at: expires_at} ->
          cond do
            is_nil(token) ->
              case maybe_fetch_token(state, account_id) do
                {new_state, {:ok, new_token}} -> {:reply, {:ok, new_token}, new_state}
                {new_state, {:error, reason}} -> {:reply, {:error, reason}, new_state}
              end

            token_expired?(expires_at) ->
              case maybe_fetch_token(state, account_id, force?: true) do
                {new_state, {:ok, new_token}} -> {:reply, {:ok, new_token}, new_state}
                {new_state, {:error, reason}} -> {:reply, {:error, reason}, new_state}
              end

            true ->
              {:reply, {:ok, token}, state}
          end
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:refresh_token, account_id}, _from, state) do
    case maybe_fetch_token(state, account_id, force?: true) do
      {new_state, {:ok, token}} -> {:reply, {:ok, token}, new_state}
      {new_state, {:error, reason}} -> {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:load_credentials, account_id, credentials_json}, _from, state) do
    with {:ok, credentials} <- JSON.decode(credentials_json) do
      state =
        state
        |> ensure_account_entry(account_id)
        |> put_account(account_id, %{
          credentials: credentials,
          last_error: nil
        })
        |> cancel_retry(account_id, :load_credentials)

      case maybe_fetch_token(state, account_id, force?: true) do
        {new_state, {:ok, _token}} -> {:reply, :ok, new_state}
        {new_state, {:error, reason}} -> {:reply, {:error, reason}, new_state}
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:retry, :load_credentials, account_id}, state) do
    with {:ok, account} <- Accounts.fetch_account(account_id) do
      state_with_creds =
        state
        |> ensure_account_entry(account_id)
        |> maybe_load_credentials_from_disk(account_id, account.service_account_file)

      # Handle the tuple return from maybe_fetch_token
      {new_state, _result} = maybe_fetch_token(state_with_creds, account_id)

      {:noreply, new_state}
    else
      {:error, reason} ->
        Logger.error("GSC account #{account_id} unavailable during retry: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:retry, :fetch_token, account_id}, state) do
    {new_state, _result} = maybe_fetch_token(state, account_id, force?: true)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:refresh_token, account_id}, state) do
    case maybe_fetch_token(state, account_id, force?: true) do
      {new_state, {:ok, _token}} ->
        {:noreply, new_state}

      {new_state, {:error, reason}} ->
        Logger.error(
          "Failed to refresh GSC token for account #{account_id}: #{inspect(reason)}"
        )

        {:noreply, new_state}
    end
  end

  # Internal helpers ----------------------------------------------------------

  defp maybe_load_credentials_from_disk(state, account_id, nil) do
    Logger.warning(
      "GSC account #{account_id} is enabled but no service account file is configured"
    )

    put_account(state, account_id, %{credentials: nil, last_error: :missing_credentials})
    |> schedule_retry(account_id, :load_credentials, 60_000)
  end

  defp maybe_load_credentials_from_disk(state, account_id, path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        case JSON.decode(content) do
          {:ok, credentials} ->
            Logger.info("Loaded GSC credentials for account #{account_id}")

            state
            |> put_account(account_id, %{credentials: credentials, last_error: nil})
            |> cancel_retry(account_id, :load_credentials)

          {:error, reason} ->
            Logger.error(
              "Failed to decode GSC credentials for account #{account_id}: #{inspect(reason)}"
            )

            state
            |> put_account(account_id, %{credentials: nil, last_error: reason})
            |> schedule_retry(account_id, :load_credentials, 30_000)
        end

      {:error, reason} ->
        Logger.error(
          "Failed to read GSC credentials for account #{account_id} from #{path}: #{inspect(reason)}"
        )

        state
        |> put_account(account_id, %{credentials: nil, last_error: reason})
        |> schedule_retry(account_id, :load_credentials, 30_000)
    end
  end

  defp maybe_fetch_token(state, account_id, opts \\ []) do
    state = ensure_account_entry(state, account_id)

    with {:ok, %{credentials: credentials}} when is_map(credentials) <-
           fetch_account_state(state, account_id) do
      fetch_with_credentials(state, account_id, credentials, opts)
    else
      {:ok, %{credentials: nil}} ->
        {state, {:error, :missing_credentials}}

      {:error, reason} ->
        {state, {:error, reason}}
    end
  end

  defp fetch_with_credentials(state, account_id, credentials, _opts) do
    case fetch_access_token(credentials) do
      {:ok, token, expires_in} ->
        expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

        AuditLogger.log_auth_event("token_refresh_success", %{
          account_id: account_id,
          expires_at: DateTime.to_iso8601(expires_at),
          expires_in_seconds: expires_in
        })

        Logger.info(
          "Authenticated with GSC for account #{account_id}; token expires #{format_expiry_window(expires_in)}"
        )

        state =
          state
          |> put_account(account_id, %{
            token: token,
            expires_at: expires_at,
            last_error: nil
          })
          |> cancel_retry(account_id, :fetch_token)
          |> schedule_token_refresh(account_id, expires_in)

        {state, {:ok, token}}

      {:error, reason} ->
        AuditLogger.log_auth_event("token_refresh_failed", %{
          account_id: account_id,
          error: inspect(reason),
          retry_in_seconds: 30
        })

        Logger.error(
          "Failed to obtain GSC token for account #{account_id}: #{inspect(reason)}"
        )

        state =
          state
          |> put_account(account_id, %{last_error: reason, token: nil, expires_at: nil})
          |> schedule_retry(account_id, :fetch_token, 30_000)

        {state, {:error, reason}}
    end
  end

  defp fetch_account_state(state, account_id) do
    case Map.fetch(state.accounts, account_id) do
      {:ok, account_state} -> {:ok, account_state}
      :error -> {:error, :unknown_account}
    end
  end

  defp ensure_account_entry(state, account_id) do
    Map.update(state, :accounts, %{}, fn accounts ->
      Map.put_new(accounts, account_id, %{
        credentials: nil,
        token: nil,
        expires_at: nil,
        refresh_timer: nil,
        retry_timers: %{},
        last_error: nil
      })
    end)
  end

  defp put_account(state, account_id, updates) do
    update_in(state, [:accounts, account_id], fn existing ->
      (existing || %{
         credentials: nil,
         token: nil,
         expires_at: nil,
         refresh_timer: nil,
         retry_timers: %{},
         last_error: nil
       })
      |> Map.merge(updates)
    end)
  end

  defp schedule_token_refresh(state, account_id, expires_in) do
    refresh_in = max((expires_in - 600) * 1000, 60_000)

    state
    |> cancel_refresh(account_id)
    |> put_account(account_id, %{
      refresh_timer: Process.send_after(self(), {:refresh_token, account_id}, refresh_in)
    })
  end

  defp cancel_refresh(state, account_id) do
    case get_in(state, [:accounts, account_id, :refresh_timer]) do
      nil ->
        state

      timer ->
        Process.cancel_timer(timer)
        put_account(state, account_id, %{refresh_timer: nil})
    end
  end

  defp schedule_retry(state, account_id, type, delay_ms) when is_atom(type) do
    state_after_cancel = cancel_retry(state, account_id, type)
    retry_timers = get_in(state_after_cancel, [:accounts, account_id, :retry_timers]) || %{}

    timer = Process.send_after(self(), {:retry, type, account_id}, delay_ms)

    put_account(state_after_cancel, account_id, %{
      retry_timers: Map.put(retry_timers, type, timer)
    })
  end

  defp cancel_retry(state, account_id, type) when is_atom(type) do
    retry_timers = get_in(state, [:accounts, account_id, :retry_timers]) || %{}

    case Map.pop(retry_timers, type) do
      {nil, _rest} ->
        state

      {timer, rest} ->
        Process.cancel_timer(timer)
    put_account(state, account_id, %{retry_timers: rest})
    end
  end

  defp token_expired?(nil), do: true

  defp token_expired?(expires_at) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  # OAuth helpers -------------------------------------------------------------

  defp fetch_access_token(credentials) do
    with {:ok, jwt} <- generate_jwt_assertion(credentials) do
      request_access_token(jwt)
    end
  end

  defp generate_jwt_assertion(credentials) do
    now = System.os_time(:second)

    claims = %{
      "iss" => credentials["client_email"],
      "scope" => @google_auth_scope,
      "aud" => @google_token_url,
      "iat" => now,
      "exp" => now + 3600
    }

    sign_jwt(claims, credentials["private_key"])
  end

  defp sign_jwt(claims, private_key_pem) do
    try do
      jwk = JOSE.JWK.from_pem(private_key_pem)
      {_, jwt} = JOSE.JWT.sign(jwk, %{"alg" => "RS256"}, claims) |> JOSE.JWS.compact()
      {:ok, jwt}
    rescue
      error -> {:error, error}
    end
  end

  defp request_access_token(jwt) do
    body =
      URI.encode_query(%{
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion" => jwt
      })

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Accept", "application/json"}
    ]

    request = {
      String.to_charlist(@google_token_url),
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end),
      ~c"application/x-www-form-urlencoded",
      body
    }

    case :httpc.request(:post, request, [], []) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        case JSON.decode(to_string(response_body)) do
          {:ok, %{"access_token" => token, "expires_in" => expires_in}} ->
            {:ok, token, expires_in}

          {:ok, response} ->
            {:error, {:unexpected_response, response}}

          {:error, reason} ->
            {:error, {:decode_error, reason}}
        end

      {:ok, {{_, status, _}, _, response_body}} ->
        {:error, {:oauth_error, status, to_string(response_body)}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp format_expiry_window(expires_in) when is_integer(expires_in) and expires_in > 0 do
    cond do
      expires_in < 60 ->
        "in ~#{expires_in}s"

      expires_in < 3600 ->
        minutes = Float.round(expires_in / 60, 1)
        "in ~#{minutes} min"

      true ->
        hours = Float.round(expires_in / 3600, 2)
        "in ~#{hours} h"
    end
  end

  defp format_expiry_window(_), do: "at an unknown time"
end
