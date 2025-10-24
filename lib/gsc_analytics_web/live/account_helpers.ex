defmodule GscAnalyticsWeb.Live.AccountHelpers do
  @moduledoc """
  Shared helpers for LiveViews that need to expose Google Search Console account
  selection controls. Handles configuration lookups, parameter parsing, and
  assigning consistent socket assigns for layouts.
  """

  use Phoenix.Component

  alias GscAnalytics.Accounts

  @type socket :: Phoenix.LiveView.Socket.t()

  @doc """
  Ensure base account assigns are present on the socket and return the selected
  account.

  Accepts the params map so we can respect `account_id` query values during
  initial mount.
  """
  @spec init_account_assigns(socket(), map()) :: {socket(), map()}
  def init_account_assigns(socket, params \\ %{}) do
    accounts = Accounts.list_gsc_accounts()
    accounts_by_id = Map.new(accounts, fn account -> {account.id, account} end)
    requested_id = params |> Map.get("account_id") |> parse_account_param()
    current_account = resolve_initial_account(accounts_by_id, requested_id)

    socket =
      socket
      |> assign(:accounts_by_id, accounts_by_id)
      |> assign(:account_options, Accounts.gsc_account_options())
      |> assign(:current_account, current_account)
      |> assign(:current_account_id, current_account.id)

    {socket, current_account}
  end

  @doc """
  Update the current account selection based on the latest params. Expects the
  socket to already contain `:accounts_by_id`.
  """
  @spec assign_current_account(socket(), map()) :: socket()
  def assign_current_account(socket, params \\ %{}) do
    requested_id = params |> Map.get("account_id") |> parse_account_param()
    accounts = Map.get(socket.assigns, :accounts_by_id, %{})

    current_account =
      case requested_id && Map.get(accounts, requested_id) do
        nil -> resolve_initial_account(accounts, requested_id)
        account -> account
      end

    socket
    |> assign(:current_account, current_account)
    |> assign(:current_account_id, current_account.id)
  end

  @doc """
  Parse incoming account parameter values safely.
  """
  @spec parse_account_param(term()) :: integer() | nil
  def parse_account_param(nil), do: nil
  def parse_account_param(value) when is_integer(value) and value > 0, do: value

  def parse_account_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  def parse_account_param(_), do: nil

  defp resolve_initial_account(accounts_by_id, requested_id) do
    cond do
      requested_id && Map.has_key?(accounts_by_id, requested_id) ->
        Map.fetch!(accounts_by_id, requested_id)

      Map.has_key?(accounts_by_id, Accounts.default_account_id()) ->
        Map.fetch!(accounts_by_id, Accounts.default_account_id())

      true ->
        accounts_by_id
        |> Map.values()
        |> Enum.sort_by(& &1.id)
        |> List.first()
        |> case do
          nil -> raise "No GSC accounts configured. Please update :gsc_accounts in config/config.exs"
          account -> account
        end
    end
  end
end
