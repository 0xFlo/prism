defmodule GscAnalytics.Auth.OAuthToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "oauth_tokens" do
    field :account_id, :integer
    field :google_email, :string
    field :refresh_token_encrypted, :binary
    field :access_token_encrypted, :binary
    field :expires_at, :utc_datetime
    field :scopes, {:array, :string}, default: []
    field :status, Ecto.Enum, values: [:valid, :invalid, :expired], default: :valid
    field :last_error, :string
    field :last_validated_at, :utc_datetime_usec

    # Virtual fields for decrypted tokens (never persisted)
    field :refresh_token, :string, virtual: true
    field :access_token, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(oauth_token, attrs) do
    oauth_token
    |> cast(attrs, [
      :account_id,
      :google_email,
      :refresh_token,
      :access_token,
      :expires_at,
      :scopes,
      :status,
      :last_error,
      :last_validated_at
    ])
    |> validate_required([:account_id, :google_email, :refresh_token])
    |> validate_number(:account_id, greater_than: 0)
    |> validate_format(:google_email, ~r/@/)
    |> validate_inclusion(:status, [:valid, :invalid, :expired])
    |> unique_constraint(:account_id)
    |> encrypt_tokens()
  end

  # Encrypt tokens before saving to database
  defp encrypt_tokens(changeset) do
    changeset
    |> maybe_encrypt_field(:refresh_token, :refresh_token_encrypted)
    |> maybe_encrypt_field(:access_token, :access_token_encrypted)
  end

  defp maybe_encrypt_field(changeset, virtual_field, encrypted_field) do
    case get_change(changeset, virtual_field) do
      nil ->
        changeset

      plaintext when is_binary(plaintext) ->
        encrypted = GscAnalytics.Vault.encrypt!(plaintext)

        changeset
        |> put_change(encrypted_field, encrypted)
        |> delete_change(virtual_field)
    end
  end

  @doc """
  Decrypt the stored tokens and populate virtual fields.
  """
  def with_decrypted_tokens(%__MODULE__{} = oauth_token) do
    %{
      oauth_token
      | refresh_token: decrypt_field(oauth_token.refresh_token_encrypted),
        access_token: decrypt_field(oauth_token.access_token_encrypted)
    }
  end

  defp decrypt_field(nil), do: nil

  defp decrypt_field(encrypted) when is_binary(encrypted) do
    GscAnalytics.Vault.decrypt!(encrypted)
  end

  @doc """
  Returns true if the token is in a valid state.
  """
  def valid?(%__MODULE__{status: :valid}), do: true
  def valid?(_), do: false

  @doc """
  Returns true if the token is in an invalid state (needs re-authentication).
  """
  def invalid?(%__MODULE__{status: :invalid}), do: true
  def invalid?(_), do: false

  @doc """
  Returns true if the token is expired.
  """
  def expired?(%__MODULE__{status: :expired}), do: true
  def expired?(_), do: false

  @doc """
  Returns true if the token needs re-authentication (invalid or expired).
  """
  def needs_reauth?(%__MODULE__{} = token) do
    invalid?(token) or expired?(token)
  end

  @doc """
  Changeset for marking a token as invalid.
  """
  def mark_invalid(oauth_token, error_reason) do
    oauth_token
    |> cast(
      %{
        status: :invalid,
        last_error: error_reason,
        last_validated_at: DateTime.utc_now()
      },
      [:status, :last_error, :last_validated_at]
    )
    |> validate_inclusion(:status, [:valid, :invalid, :expired])
  end

  @doc """
  Changeset for marking a token as valid.
  """
  def mark_valid(oauth_token) do
    oauth_token
    |> cast(
      %{
        status: :valid,
        last_error: nil,
        last_validated_at: DateTime.utc_now()
      },
      [:status, :last_error, :last_validated_at]
    )
    |> validate_inclusion(:status, [:valid, :invalid, :expired])
  end

  @doc """
  Changeset for marking a token as expired.
  """
  def mark_expired(oauth_token) do
    oauth_token
    |> cast(
      %{
        status: :expired,
        last_validated_at: DateTime.utc_now()
      },
      [:status, :last_validated_at]
    )
    |> validate_inclusion(:status, [:valid, :invalid, :expired])
  end
end
