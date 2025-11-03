defmodule GscAnalytics.WorkspaceTestHelper do
  @moduledoc """
  Helper functions for setting up complete workspace test environments.

  Provides one-line setup for tests that need a fully configured workspace
  with properties and OAuth tokens.
  """

  import GscAnalytics.AccountsFixtures
  import GscAnalytics.AuthFixtures

  alias GscAnalytics.Accounts

  @doc """
  Creates a complete workspace environment for testing:
  - User
  - Workspace
  - Active property
  - OAuth token

  Returns `{workspace, property}` tuple.

  ## Options
    * `:user` - Existing user (creates new if not provided)
    * `:property_url` - Property URL (defaults to "sc-domain:test.com")
    * `:workspace_attrs` - Additional workspace attributes
    * `:property_attrs` - Additional property attributes

  ## Example

      setup %{user: user} do
        {workspace, property} = setup_workspace_with_property(user: user)
        %{workspace: workspace, property: property}
      end
  """
  def setup_workspace_with_property(opts \\ []) do
    user = Keyword.get(opts, :user) || user_fixture()

    workspace_attrs = Keyword.get(opts, :workspace_attrs, [])
    workspace = workspace_fixture([{:user, user} | workspace_attrs])

    property_url = Keyword.get(opts, :property_url, "sc-domain:test.com")
    property_attrs = Keyword.get(opts, :property_attrs, [])

    {:ok, property} =
      Accounts.add_property(
        workspace.id,
        Map.merge(
          %{
            property_url: property_url,
            is_active: true
          },
          Enum.into(property_attrs, %{})
        )
      )

    # Create OAuth token so property is accessible
    _token = oauth_token_fixture(workspace)

    {workspace, property}
  end

  @doc """
  Same as setup_workspace_with_property/1 but returns just the workspace.
  Useful when you don't need the property reference.
  """
  def setup_workspace(opts \\ []) do
    {workspace, _property} = setup_workspace_with_property(opts)
    workspace
  end
end
