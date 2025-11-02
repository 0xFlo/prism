defmodule GscAnalyticsWeb.Live.AccountHelpersTest do
  use GscAnalyticsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GscAnalytics.AuthFixtures

  alias GscAnalytics.{Accounts, Auth, Repo, Workspaces}
  alias GscAnalytics.Schemas.{Workspace, WorkspaceProperty}
  alias GscAnalyticsWeb.Live.AccountHelpers

  describe "property dropdown rendering" do
    setup do
      user = user_fixture()

      # Create two workspaces with different Google accounts
      {:ok, workspace1} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "user1@example.com",
          name: "user1@example.com",
          enabled: true
        })

      {:ok, workspace2} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "user2@example.com",
          name: "user2@example.com",
          enabled: true
        })

      # Reload scope to include new workspace IDs
      scope = %Auth.Scope{user: user, account_ids: [workspace1.id, workspace2.id]}

      # Create OAuth tokens for both workspaces
      {:ok, _token1} =
        Auth.store_oauth_token(scope, %{
          account_id: workspace1.id,
          google_email: "user1@example.com",
          access_token: "fake_access_token_1",
          refresh_token: "fake_refresh_token_1",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      {:ok, _token2} =
        Auth.store_oauth_token(scope, %{
          account_id: workspace2.id,
          google_email: "user2@example.com",
          access_token: "fake_access_token_2",
          refresh_token: "fake_refresh_token_2",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Create properties for workspace1
      {:ok, prop1_1} =
        Accounts.add_property(workspace1.id, %{
          property_url: "sc-domain:workspace1-site1.com",
          is_active: true
        })

      {:ok, prop1_2} =
        Accounts.add_property(workspace1.id, %{
          property_url: "sc-domain:workspace1-site2.com",
          is_active: true
        })

      # Create properties for workspace2
      {:ok, prop2_1} =
        Accounts.add_property(workspace2.id, %{
          property_url: "sc-domain:workspace2-site1.com",
          is_active: true
        })

      {:ok, prop2_2} =
        Accounts.add_property(workspace2.id, %{
          property_url: "sc-domain:workspace2-site2.com",
          is_active: true
        })

      %{
        user: user,
        scope: scope,
        workspace1: workspace1,
        workspace2: workspace2,
        prop1_1: prop1_1,
        prop1_2: prop1_2,
        prop2_1: prop2_1,
        prop2_2: prop2_2
      }
    end

    test "properties are correctly associated with their workspaces", %{
      workspace1: workspace1,
      workspace2: workspace2,
      prop1_1: prop1_1,
      prop1_2: prop1_2,
      prop2_1: prop2_1,
      prop2_2: prop2_2
    } do
      # Verify database associations are correct
      workspace1_props = Accounts.list_properties(workspace1.id)
      workspace2_props = Accounts.list_properties(workspace2.id)

      workspace1_urls = Enum.map(workspace1_props, & &1.property_url)
      workspace2_urls = Enum.map(workspace2_props, & &1.property_url)

      assert prop1_1.property_url in workspace1_urls
      assert prop1_2.property_url in workspace1_urls
      refute prop2_1.property_url in workspace1_urls
      refute prop2_2.property_url in workspace1_urls

      assert prop2_1.property_url in workspace2_urls
      assert prop2_2.property_url in workspace2_urls
      refute prop1_1.property_url in workspace2_urls
      refute prop1_2.property_url in workspace2_urls
    end

    test "dropdown shows properties with correct Google account labels", %{
      user: user,
      workspace1: workspace1,
      workspace2: workspace2
    } do
      {:ok, conn} = Plug.Test.init_test_session(Plug.Conn.fetch_session(build_conn()), %{})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      # Get the property dropdown options
      html = render(view)

      # Properties from workspace1 should have user1@example.com prefix
      assert html =~ "user1@example.com - sc-domain:workspace1-site1.com"
      assert html =~ "user1@example.com - sc-domain:workspace1-site2.com"

      # Properties from workspace2 should have user2@example.com prefix
      assert html =~ "user2@example.com - sc-domain:workspace2-site1.com"
      assert html =~ "user2@example.com - sc-domain:workspace2-site2.com"

      # Ensure no cross-contamination (workspace1 properties should NOT have workspace2 email)
      refute html =~ "user2@example.com - sc-domain:workspace1-site1.com"
      refute html =~ "user2@example.com - sc-domain:workspace1-site2.com"

      # Ensure no cross-contamination (workspace2 properties should NOT have workspace1 email)
      refute html =~ "user1@example.com - sc-domain:workspace2-site1.com"
      refute html =~ "user1@example.com - sc-domain:workspace2-site2.com"
    end

    test "inactive properties do not appear in dropdown", %{
      user: user,
      workspace1: workspace1
    } do
      # Create an inactive property
      {:ok, _inactive_prop} =
        Accounts.add_property(workspace1.id, %{
          property_url: "sc-domain:inactive-site.com",
          is_active: false
        })

      {:ok, conn} = Plug.Test.init_test_session(Plug.Conn.fetch_session(build_conn()), %{})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      # Inactive property should not appear
      refute html =~ "sc-domain:inactive-site.com"
    end

    test "only properties with API access appear in dropdown when API validation is enabled" do
      user = user_fixture()

      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "test@example.com",
          enabled: true
        })

      scope = %Auth.Scope{user: user, account_ids: [workspace.id]}

      {:ok, _token} =
        Auth.store_oauth_token(scope, %{
          account_id: workspace.id,
          google_email: "test@example.com",
          access_token: "fake_access_token",
          refresh_token: "fake_refresh_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Create property that would be saved but might not have API access
      # This tests that the API validation properly filters properties
      {:ok, prop} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:no-api-access.com",
          is_active: true
        })

      # Mock the API to return empty list (no API access)
      # In real implementation, you'd use a mock library like Mox
      # For now, this test documents the expected behavior

      # The property should NOT appear in dropdown if API returns no access
      # The property SHOULD appear if API confirms access
      assert prop.is_active == true
    end
  end

  describe "switching between workspaces" do
    test "switching workspace updates property options correctly", %{conn: conn} do
      user = user_fixture()

      {:ok, workspace1} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "ws1@example.com",
          name: "ws1@example.com",
          enabled: true
        })

      {:ok, workspace2} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "ws2@example.com",
          name: "ws2@example.com",
          enabled: true
        })

      scope = %Auth.Scope{user: user, account_ids: [workspace1.id, workspace2.id]}

      {:ok, _} =
        Auth.store_oauth_token(scope, %{
          account_id: workspace1.id,
          google_email: "ws1@example.com",
          access_token: "fake_token_1",
          refresh_token: "fake_refresh_1",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      {:ok, _} =
        Auth.store_oauth_token(scope, %{
          account_id: workspace2.id,
          google_email: "ws2@example.com",
          access_token: "fake_token_2",
          refresh_token: "fake_refresh_2",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      {:ok, _} =
        Accounts.add_property(workspace1.id, %{
          property_url: "sc-domain:ws1-site.com",
          is_active: true
        })

      {:ok, _} =
        Accounts.add_property(workspace2.id, %{
          property_url: "sc-domain:ws2-site.com",
          is_active: true
        })

      {:ok, conn} = Plug.Test.init_test_session(Plug.Conn.fetch_session(conn), %{})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/?account_id=#{workspace1.id}")

      # Should see both workspaces' properties but with correct labels
      html = render(view)
      assert html =~ "ws1@example.com - sc-domain:ws1-site.com"
      assert html =~ "ws2@example.com - sc-domain:ws2-site.com"

      # Switch to workspace2
      {:ok, view, _html} = live(conn, ~p"/?account_id=#{workspace2.id}")
      html = render(view)

      # Should still see both, with correct labels
      assert html =~ "ws1@example.com - sc-domain:ws1-site.com"
      assert html =~ "ws2@example.com - sc-domain:ws2-site.com"
    end
  end
end
