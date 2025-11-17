defmodule GscAnalytics.UserSettings.WorkspaceManager do
  @moduledoc """
  Encapsulates the side-effectful operations required by the User settings
  LiveView when listing workspaces, parsing identifiers, and handling property
  mutations.
  """

  import Ecto.Query
  import Phoenix.Component, only: [to_form: 1]

  alias GscAnalytics.{Accounts, Auth, Workspaces}
  alias GscAnalytics.Auth.OAuthToken
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.WorkspaceProperty

  @spec list_accounts(Auth.Scope.t()) :: {[map()], map()}
  def list_accounts(%Auth.Scope{} = scope) do
    workspace_ids = Accounts.account_ids_for_user(scope.user)
    preloaded_properties = batch_load_properties(workspace_ids)
    accounts = build_accounts(scope, preloaded_properties)
    {accounts, preloaded_properties}
  end

  def account_requires_action?(%{oauth: nil}), do: true
  def account_requires_action?(%{property_required?: true}), do: true
  def account_requires_action?(_), do: false

  def parse_account_id(account_id) when is_integer(account_id) and account_id > 0,
    do: {:ok, account_id}

  def parse_account_id(account_id) when is_binary(account_id) do
    account_id
    |> String.trim()
    |> Integer.parse()
    |> case do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_account_id}
    end
  end

  def parse_account_id(_), do: {:error, :invalid_account_id}

  def property_display_label(nil, _options), do: nil

  def property_display_label(property, options) when is_binary(property) do
    trimmed = String.trim(property)

    options
    |> Enum.find(&(to_string(&1.value) == trimmed))
    |> case do
      %{label: label} when is_binary(label) and label != "" ->
        label

      _ ->
        format_property_label(trimmed)
    end
  end

  def property_display_label(_property, _options), do: nil

  def format_property_label("sc-domain:" <> rest), do: "Domain: #{rest}"

  def format_property_label(property) when is_binary(property) do
    property
    |> String.trim()
    |> case do
      "https://" <> _ = url -> URI.parse(url).host || url
      other -> other
    end
  end

  def format_property_label(property), do: to_string(property)

  def translate_property_error(:invalid_account_id), do: "Invalid workspace identifier"

  def translate_property_error(:unauthorized_account),
    do: "You do not have access to this workspace"

  def translate_property_error(_), do: "Unable to load properties right now"

  def changeset_error_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.join(", ")
  end

  defp build_accounts(%Auth.Scope{} = scope, preloaded_properties) do
    workspaces = Workspaces.list_workspaces(scope.user.id)
    workspace_ids = Enum.map(workspaces, & &1.id)
    oauth_tokens = batch_load_oauth_tokens(workspace_ids)

    Enum.map(workspaces, fn workspace ->
      oauth = Map.get(oauth_tokens, workspace.id)
      saved_properties_for_account = Map.get(preloaded_properties, workspace.id, [])

      {property_options, property_options_error, oauth_error} =
        if oauth do
          case Accounts.list_property_options(scope, workspace.id, saved_properties_for_account) do
            {:ok, options} ->
              {ensure_included_property(options, workspace.default_property), nil, nil}

            {:error, :oauth_token_invalid} ->
              {[], nil, :oauth_token_invalid}

            {:error, reason} ->
              {[], translate_property_error(reason), nil}
          end
        else
          {[], nil, nil}
        end

      saved_properties = saved_properties_for_account
      active_properties = Enum.filter(saved_properties, & &1.is_active)
      active_property = List.first(active_properties)
      property_label = property_display_label(workspace.default_property, property_options)

      unified_properties =
        build_unified_properties(property_options, saved_properties)

      %{
        id: workspace.id,
        display_name: workspace.name,
        oauth: oauth,
        oauth_error: oauth_error,
        default_property: workspace.default_property,
        property_options: property_options,
        property_options_error: property_options_error,
        property_label: property_label,
        property_required?: is_nil(workspace.default_property) && Enum.empty?(active_properties),
        can_manage_property?: not is_nil(oauth),
        property_form: to_form(%{"default_property" => workspace.default_property || ""}),
        saved_properties: saved_properties,
        active_property: active_property,
        active_properties: active_properties,
        unified_properties: unified_properties
      }
    end)
  end

  defp build_unified_properties(api_properties, saved_properties) do
    api_properties = api_properties || []
    saved_properties = saved_properties || []

    saved_only_properties =
      saved_properties
      |> Enum.reject(fn prop -> Enum.any?(api_properties, &(&1.value == prop.property_url)) end)
      |> Enum.map(fn prop ->
        %{
          property_url: prop.property_url,
          label: prop.display_name || format_property_label(prop.property_url),
          permission_level: nil,
          has_api_access: false,
          is_saved: true,
          is_active: prop.is_active,
          property_id: prop.id
        }
      end)

    (api_properties ++ saved_only_properties)
    |> Enum.sort_by(fn prop -> String.downcase(prop.label || prop.property_url) end)
  end

  defp batch_load_oauth_tokens([]), do: %{}

  defp batch_load_oauth_tokens(workspace_ids) do
    from(t in OAuthToken, where: t.account_id in ^workspace_ids)
    |> Repo.all()
    |> Enum.map(fn token ->
      {token.account_id,
       %{
         google_email: token.google_email,
         status: token.status,
         last_error: token.last_error,
         last_validated_at: token.last_validated_at
       }}
    end)
    |> Map.new()
  end

  defp batch_load_properties([]), do: %{}

  defp batch_load_properties(workspace_ids) do
    from(p in WorkspaceProperty,
      where: p.workspace_id in ^workspace_ids,
      order_by: [desc: p.is_active, asc: p.display_name]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.workspace_id)
  end

  defp ensure_included_property(options, property) do
    case property do
      nil ->
        options

      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" or Enum.any?(options, &(&1.value == trimmed)) do
          options
        else
          [
            %{value: trimmed, label: format_property_label(trimmed), permission_level: nil}
            | options
          ]
        end

      _ ->
        options
    end
  end
end
