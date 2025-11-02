defmodule GscAnalyticsWeb.GoogleAuth do
  @moduledoc """
  Handles the Google OAuth2 flow used to connect Search Console accounts.
  """

  use GscAnalyticsWeb, :controller

  alias GscAnalytics.Auth
  alias GscAnalytics.Auth.Scope
  alias GscAnalytics.Workspaces

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @oauth_scope "https://www.googleapis.com/auth/webmasters.readonly email openid"
  @state_max_age 600

  @doc """
  Initiates OAuth flow for a workspace.

  - If `workspace_id` is provided, reconnects existing workspace
  - If `workspace_id` is "new", creates a new workspace on callback
  """
  def request(conn, workspace_id) when is_integer(workspace_id) or workspace_id == "new" do
    current_scope = conn.assigns.current_scope

    with %Scope{} = scope <- current_scope,
         {:ok, oauth_config} <- oauth_config() do
      state = generate_state(scope, workspace_id)
      callback_url = url(~p"/auth/google/callback")

      query =
        %{
          client_id: oauth_config.client_id,
          redirect_uri: callback_url,
          response_type: "code",
          scope: @oauth_scope,
          access_type: "offline",
          prompt: "consent",
          state: state
        }
        |> URI.encode_query()

      redirect(conn, external: "#{@google_auth_url}?#{query}")
    else
      nil ->
        unauthorized_redirect(conn)

      {:error, :missing_oauth_config} ->
        conn
        |> put_flash(
          :error,
          "Google OAuth configuration is missing. Set GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET, then restart the server."
        )
        |> redirect(to: ~p"/accounts")
    end
  end

  def callback(conn, params) when is_map(params) do
    current_scope = conn.assigns.current_scope

    with %Scope{} = scope <- current_scope,
         {:ok, state_token} <- fetch_state_param(params),
         {:ok, state_data} <- verify_state(state_token, scope),
         {:ok, code} <- fetch_code_param(params),
         {:ok, tokens} <- exchange_code_for_tokens(code),
         google_email <- extract_email_safely(tokens),
         {:ok, workspace} <- ensure_workspace_exists(scope, state_data, google_email),
         refreshed_scope <- Scope.reload(scope),
         {:ok, _stored_token} <- store_tokens(refreshed_scope, workspace.id, tokens) do
      conn
      |> put_flash(:info, success_message(google_email))
      |> redirect(to: ~p"/")
    else
      nil ->
        unauthorized_redirect(conn)

      {:error, :unauthorized_account} ->
        unauthorized_redirect(conn)

      {:error, :missing_state} ->
        conn
        |> put_flash(:error, "OAuth callback is missing the required state parameter.")
        |> redirect(to: ~p"/")

      {:error, :invalid_state} ->
        conn
        |> put_flash(:error, "Invalid OAuth state. Please start the connection again.")
        |> redirect(to: ~p"/")

      {:error, :state_mismatch} ->
        conn
        |> put_flash(:error, "OAuth session has expired. Please try again.")
        |> redirect(to: ~p"/")

      {:error, :missing_code} ->
        conn
        |> put_flash(:error, "Google did not return an authorization code.")
        |> redirect(to: ~p"/")

      {:error, :missing_oauth_config} ->
        conn
        |> put_flash(
          :error,
          "Google OAuth configuration is missing. Set GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET, then restart the server."
        )
        |> redirect(to: ~p"/")

      {:error, {:http_error, status, body}} ->
        conn
        |> put_flash(:error, "Google OAuth failed (status #{status}): #{inspect(body)}")
        |> redirect(to: ~p"/")

      {:error, :missing_refresh_token} ->
        conn
        |> put_flash(
          :error,
          "Google did not provide a refresh token. Please grant offline access."
        )
        |> redirect(to: ~p"/")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Google OAuth failed: #{inspect(reason)}")
        |> redirect(to: ~p"/")
    end
  end

  def generate_state(current_scope, workspace_id) do
    Phoenix.Token.sign(
      GscAnalyticsWeb.Endpoint,
      "oauth_state",
      %{
        workspace_id: workspace_id,
        user_id: current_scope.user.id
      }
    )
  end

  def verify_state(state_token, current_scope) when is_binary(state_token) do
    case Phoenix.Token.verify(GscAnalyticsWeb.Endpoint, "oauth_state", state_token,
           max_age: @state_max_age
         ) do
      {:ok, %{user_id: user_id} = data} ->
        if current_scope && current_scope.user && current_scope.user.id == user_id do
          {:ok, normalize_state_data(data)}
        else
          {:error, :state_mismatch}
        end

      {:error, _} ->
        {:error, :invalid_state}
    end
  end

  def verify_state(_state_token, _current_scope), do: {:error, :missing_state}

  defp ensure_workspace_exists(current_scope, %{workspace_id: "new"}, google_email) do
    # Create new workspace
    user_id = current_scope.user.id

    Workspaces.create_workspace(user_id, %{
      name: google_email,
      google_account_email: google_email,
      enabled: true
    })
  end

  defp ensure_workspace_exists(current_scope, %{workspace_id: workspace_id}, google_email)
       when is_integer(workspace_id) do
    # Reconnect existing workspace - verify ownership and update email
    user_id = current_scope.user.id

    case Workspaces.fetch_workspace(user_id, workspace_id) do
      {:ok, workspace} ->
        # Update google_account_email in case it changed
        Workspaces.update_workspace(workspace, %{google_account_email: google_email})

      {:error, :not_found} ->
        {:error, :workspace_not_found}
    end
  end

  defp ensure_workspace_exists(_scope, _state_data, _email) do
    {:error, :invalid_workspace_id}
  end

  defp fetch_state_param(%{"state" => state}) when is_binary(state), do: {:ok, state}
  defp fetch_state_param(%{state: state}) when is_binary(state), do: {:ok, state}
  defp fetch_state_param(_), do: {:error, :missing_state}

  defp fetch_code_param(%{"code" => code}) when is_binary(code), do: {:ok, code}
  defp fetch_code_param(%{code: code}) when is_binary(code), do: {:ok, code}
  defp fetch_code_param(_), do: {:error, :missing_code}

  defp oauth_config do
    config =
      Application.get_env(:gsc_analytics, :google_oauth, %{})
      |> normalize_oauth_config()

    case {Map.get(config, :client_id), Map.get(config, :client_secret)} do
      {id, secret} when is_binary(id) and is_binary(secret) ->
        {:ok, %{client_id: id, client_secret: secret}}

      _ ->
        {:error, :missing_oauth_config}
    end
  end

  defp exchange_code_for_tokens(code) when is_binary(code) do
    with {:ok, oauth_config} <- oauth_config() do
      callback_url = url(~p"/auth/google/callback")

      body = %{
        code: code,
        client_id: oauth_config.client_id,
        client_secret: oauth_config.client_secret,
        redirect_uri: callback_url,
        grant_type: "authorization_code"
      }

      case http_client().post(@google_token_url, form: body) do
        {:ok, %Req.Response{status: 200, body: response}} ->
          {:ok, response}

        {:ok, %Req.Response{status: status, body: response}} ->
          {:error, {:http_error, status, response}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp store_tokens(current_scope, account_id, tokens) do
    refresh_token =
      Map.get(tokens, "refresh_token") ||
        case Auth.get_oauth_token(current_scope, account_id) do
          {:ok, existing} -> existing.refresh_token
          _ -> nil
        end

    if is_nil(refresh_token) do
      {:error, :missing_refresh_token}
    else
      attrs = %{
        account_id: account_id,
        google_email: extract_email_safely(tokens),
        refresh_token: refresh_token,
        access_token: Map.get(tokens, "access_token"),
        expires_at: calculate_expires_at(Map.get(tokens, "expires_in")),
        scopes: build_scope_list(tokens)
      }

      Auth.store_oauth_token(current_scope, attrs)
    end
  end

  defp extract_email_safely(%{"id_token" => id_token}) when is_binary(id_token) do
    with [_header, payload, _signature] <- String.split(id_token, "."),
         {:ok, decoded} <- Base.url_decode64(payload, padding: false),
         {:ok, claims} <- JSON.decode(decoded) do
      Map.get(claims, "email", "unknown@oauth.local")
    else
      _ -> "unknown@oauth.local"
    end
  end

  defp extract_email_safely(_), do: "unknown@oauth.local"

  defp calculate_expires_at(expires_in) when is_integer(expires_in) do
    DateTime.utc_now() |> DateTime.add(expires_in, :second)
  end

  defp calculate_expires_at(expires_in) when is_binary(expires_in) do
    case Integer.parse(expires_in) do
      {value, ""} -> calculate_expires_at(value)
      _ -> nil
    end
  end

  defp calculate_expires_at(_), do: nil

  defp build_scope_list(%{"scope" => scope}) when is_binary(scope) do
    scope
    |> String.split(~r/\s+/, trim: true)
  end

  defp build_scope_list(%{"scope" => scopes}) when is_list(scopes) do
    Enum.map(scopes, &to_string/1)
  end

  defp build_scope_list(_tokens), do: []

  defp normalize_state_data(%{workspace_id: workspace_id, user_id: user_id}) do
    %{workspace_id: workspace_id, user_id: user_id}
  end

  defp normalize_state_data(%{"workspace_id" => workspace_id, "user_id" => user_id}) do
    %{workspace_id: workspace_id, user_id: user_id}
  end

  # Legacy support for account_id (migrate to workspace_id)
  defp normalize_state_data(%{account_id: account_id, user_id: user_id}) do
    %{workspace_id: account_id, user_id: user_id}
  end

  defp normalize_state_data(%{"account_id" => account_id, "user_id" => user_id}) do
    %{workspace_id: account_id, user_id: user_id}
  end

  defp http_client do
    Application.get_env(:gsc_analytics, :http_client, GscAnalytics.HTTPClient.Req)
  end

  defp unauthorized_redirect(conn) do
    conn
    |> put_flash(:error, "You are not authorized to manage that account.")
    |> redirect(to: ~p"/")
  end

  defp success_message(email) when is_binary(email) do
    "Google account #{email} connected successfully."
  end

  defp normalize_oauth_config(config) when is_map(config), do: config
  defp normalize_oauth_config(config) when is_list(config), do: Map.new(config)
  defp normalize_oauth_config(_), do: %{}
end
