defmodule GscAnalytics.Auth do
  @moduledoc """
  The Auth context.
  """

  import Ecto.Query, warn: false
  alias GscAnalytics.Repo

  alias GscAnalytics.Auth.{Scope, User, UserToken, UserNotifier, OAuthToken}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `GscAnalytics.Auth.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `GscAnalytics.Auth.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## OAuth Token Management

  @doc """
  Retrieves the OAuth token for a specific account.
  Returns the token with decrypted fields populated.
  """
  def get_oauth_token(current_scope, account_id) do
    with {:ok, account_id} <- normalize_account_id(account_id),
         :ok <- Scope.authorize_account(current_scope, account_id) do
      case Repo.get_by(OAuthToken, account_id: account_id) do
        nil -> {:error, :not_found}
        token -> {:ok, OAuthToken.with_decrypted_tokens(token)}
      end
    end
  end

  @doc """
  Batch retrieves OAuth tokens for multiple accounts.
  Returns a map of account_id => token (with decrypted fields).
  Only includes tokens for authorized accounts.
  """
  def batch_get_oauth_tokens(current_scope, account_ids) when is_list(account_ids) do
    import Ecto.Query

    # Filter to only authorized account IDs
    authorized_ids =
      Enum.filter(account_ids, fn account_id ->
        case normalize_account_id(account_id) do
          {:ok, normalized_id} ->
            case Scope.authorize_account(current_scope, normalized_id) do
              :ok -> true
              _ -> false
            end

          _ ->
            false
        end
      end)

    # Batch load all OAuth tokens in a single query
    tokens =
      from(t in OAuthToken,
        where: t.account_id in ^authorized_ids
      )
      |> Repo.all()

    # Return as a map of account_id => decrypted_token
    Map.new(tokens, fn token ->
      {token.account_id, OAuthToken.with_decrypted_tokens(token)}
    end)
  end

  @doc """
  Stores or updates OAuth tokens for an account.
  Returns the freshly decrypted token on success.
  """
  def store_oauth_token(current_scope, attrs) when is_map(attrs) do
    attrs = ensure_map(attrs)

    with {:ok, account_id} <- account_id_from_attrs(attrs),
         :ok <- Scope.authorize_account(current_scope, account_id) do
      normalized_attrs =
        attrs
        |> Map.put(:account_id, account_id)
        |> normalize_scope_attr()
        # Ensure status is set to :valid when storing fresh tokens
        |> Map.put(:status, :valid)

      result =
        case Repo.get_by(OAuthToken, account_id: account_id) do
          nil ->
            %OAuthToken{}
            |> OAuthToken.changeset(normalized_attrs)
            |> Repo.insert()

          existing ->
            existing
            |> OAuthToken.changeset(normalized_attrs)
            |> Repo.update()
        end

      case result do
        {:ok, token} -> {:ok, OAuthToken.with_decrypted_tokens(token)}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Refreshes the access token using the stored refresh token.
  """
  def refresh_oauth_access_token(current_scope, account_id) do
    with {:ok, account_id} <- normalize_account_id(account_id),
         :ok <- Scope.authorize_account(current_scope, account_id),
         {:ok, existing} <- get_oauth_token(nil, account_id),
         {:ok, new_tokens} <- request_token_refresh(existing.refresh_token) do
      attrs = %{
        account_id: account_id,
        google_email: existing.google_email,
        refresh_token: Map.get(new_tokens, "refresh_token", existing.refresh_token),
        access_token: Map.get(new_tokens, "access_token"),
        expires_at: calculate_expires_at(Map.get(new_tokens, "expires_in")),
        scopes: build_scope_list(new_tokens, existing.scopes),
        status: :valid,
        last_error: nil,
        last_validated_at: DateTime.utc_now()
      }

      store_oauth_token(nil, attrs)
    else
      {:error, {:http_error, 400, %{"error" => "invalid_grant"} = response}} ->
        # Token has been revoked or expired - mark as invalid in database
        with {:ok, account_id} <- normalize_account_id(account_id),
             {:ok, existing} <- get_oauth_token(nil, account_id) do
          error_message = Map.get(response, "error_description", "invalid_grant")

          existing
          |> OAuthToken.mark_invalid(error_message)
          |> Repo.update()

          require Logger

          Logger.error(
            "OAuth token refresh failed for account #{account_id}: invalid_grant - #{error_message}"
          )
        end

        {:error, :oauth_token_invalid}

      error ->
        error
    end
  end

  @doc """
  Disconnects (deletes) the OAuth token for an account.
  """
  def disconnect_oauth_account(current_scope, account_id) do
    with {:ok, account_id} <- normalize_account_id(account_id),
         :ok <- Scope.authorize_account(current_scope, account_id) do
      case Repo.get_by(OAuthToken, account_id: account_id) do
        nil -> {:error, :not_found}
        token -> Repo.delete(token)
      end
    end
  end

  @doc """
  Returns whether an account has OAuth tokens configured.
  """
  def has_oauth_token?(current_scope, account_id) do
    with {:ok, account_id} <- normalize_account_id(account_id),
         :ok <- Scope.authorize_account(current_scope, account_id) do
      Repo.exists?(from(t in OAuthToken, where: t.account_id == ^account_id))
    end
  end

  @doc """
  Validates the OAuth token for an account and returns its status.
  Returns {:ok, :valid | :invalid | :expired} or {:error, :not_found}

  This function computes the real-time token status by checking:
  1. The persisted status field (invalid/expired)
  2. Whether the token has expired based on expires_at

  If the token has expired but status is still :valid, it will be marked as :expired.
  """
  def validate_oauth_token_status(current_scope, account_id) do
    with {:ok, account_id} <- normalize_account_id(account_id),
         :ok <- Scope.authorize_account(current_scope, account_id),
         {:ok, token} <- get_oauth_token(nil, account_id) do
      # Compute real-time status based on persisted state and expiration
      real_status = compute_token_status(token)

      # If status changed (e.g., token expired), persist it
      if real_status != token.status do
        case Repo.get(OAuthToken, token.id) do
          nil ->
            {:ok, real_status}

          oauth_token ->
            oauth_token
            |> OAuthToken.mark_expired()
            |> Repo.update()

            {:ok, real_status}
        end
      else
        {:ok, token.status}
      end
    end
  end

  defp compute_token_status(token) do
    cond do
      # Already marked invalid or expired
      token.status in [:invalid, :expired] ->
        token.status

      # Token has expired based on expires_at
      token_expired?(token.expires_at) ->
        :expired

      # Token is valid
      true ->
        :valid
    end
  end

  defp token_expired?(nil), do: false

  defp token_expired?(expires_at) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end

  # Private helpers ----------------------------------------------------------

  defp request_token_refresh(refresh_token) when is_binary(refresh_token) do
    with {:ok, %{client_id: client_id, client_secret: client_secret}} <-
           extract_credentials(Application.get_env(:gsc_analytics, :google_oauth, %{})) do
      body = %{
        client_id: client_id,
        client_secret: client_secret,
        refresh_token: refresh_token,
        grant_type: "refresh_token"
      }

      case http_client().post("https://oauth2.googleapis.com/token", form: body) do
        {:ok, %Req.Response{status: 200, body: response}} ->
          {:ok, response}

        {:ok, %Req.Response{status: status, body: response}} ->
          {:error, {:http_error, status, response}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

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

  defp account_id_from_attrs(%{account_id: account_id}), do: normalize_account_id(account_id)
  defp account_id_from_attrs(%{"account_id" => account_id}), do: normalize_account_id(account_id)
  defp account_id_from_attrs(_), do: {:error, :missing_account_id}

  defp normalize_account_id(account_id) when is_integer(account_id) and account_id > 0,
    do: {:ok, account_id}

  defp normalize_account_id(account_id) when is_binary(account_id) do
    case Integer.parse(account_id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_account_id}
    end
  end

  defp normalize_account_id(_), do: {:error, :invalid_account_id}

  defp ensure_map(%_{} = struct), do: Map.from_struct(struct)
  defp ensure_map(map) when is_map(map), do: map

  defp normalize_scope_attr(attrs) do
    case Map.get(attrs, :scopes) do
      nil ->
        attrs

      scopes when is_list(scopes) ->
        Map.put(attrs, :scopes, Enum.map(scopes, &to_string/1))

      scopes ->
        Map.put(attrs, :scopes, scopes |> to_string() |> String.split(" "))
    end
  end

  defp normalize_oauth_config(config) when is_map(config), do: config
  defp normalize_oauth_config(config) when is_list(config), do: Map.new(config)
  defp normalize_oauth_config(_), do: %{}

  defp extract_credentials(config) do
    normalized = normalize_oauth_config(config)

    case {Map.get(normalized, :client_id), Map.get(normalized, :client_secret)} do
      {id, secret} when is_binary(id) and is_binary(secret) ->
        {:ok, %{client_id: id, client_secret: secret}}

      _ ->
        {:error, :missing_oauth_config}
    end
  end

  defp build_scope_list(%{"scope" => scope}, _fallback) when is_binary(scope) do
    scope
    |> String.split(~r/\s+/, trim: true)
  end

  defp build_scope_list(%{"scope" => scopes}, _fallback) when is_list(scopes) do
    Enum.map(scopes, &to_string/1)
  end

  defp build_scope_list(_tokens, fallback), do: fallback || []

  defp http_client do
    Application.get_env(:gsc_analytics, :http_client, GscAnalytics.HTTPClient.Req)
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
