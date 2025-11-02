defmodule GscAnalytics.Auth.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `GscAnalytics.Auth.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias GscAnalytics.Auth.User

  defstruct user: nil, account_ids: []

  @type t :: %__MODULE__{
          user: User.t() | nil,
          account_ids: [integer()]
        }

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    account_ids = GscAnalytics.Accounts.account_ids_for_user(user)
    %__MODULE__{user: user, account_ids: account_ids}
  end

  def for_user(nil), do: nil

  @doc """
  Reloads the scope by refreshing the account_ids from the database.

  This is useful when a new workspace/account is created and needs to be
  added to the scope's authorized account list.
  """
  @spec reload(t()) :: t()
  def reload(%__MODULE__{user: user} = scope) when not is_nil(user) do
    account_ids = GscAnalytics.Accounts.account_ids_for_user(user)
    %{scope | account_ids: account_ids}
  end

  def reload(nil), do: nil

  @doc """
  Returns true when the given account is accessible for the scope.

  Nil scopes are treated as internal callers and bypass checks.
  """
  @spec account_authorized?(t() | nil, integer()) :: boolean()
  def account_authorized?(nil, _account_id), do: true

  def account_authorized?(%__MODULE__{account_ids: account_ids}, account_id) do
    account_id in (account_ids || [])
  end

  @doc """
  Authorizes access to an account, returning `:ok` or `{:error, :unauthorized_account}`.
  """
  @spec authorize_account(t() | nil, integer()) :: :ok | {:error, :unauthorized_account}
  def authorize_account(nil, _account_id), do: :ok

  def authorize_account(%__MODULE__{} = scope, account_id) do
    if account_authorized?(scope, account_id) do
      :ok
    else
      {:error, :unauthorized_account}
    end
  end

  @doc """
  Authorizes access to an account, raising when unauthorized.
  Suitable for controller-level guards where exceptions are acceptable.
  """
  @spec authorize_account!(t() | nil, integer()) :: :ok
  def authorize_account!(scope, account_id) do
    case authorize_account(scope, account_id) do
      :ok -> :ok
      {:error, :unauthorized_account} -> raise "Unauthorized access to account #{account_id}"
    end
  end
end
