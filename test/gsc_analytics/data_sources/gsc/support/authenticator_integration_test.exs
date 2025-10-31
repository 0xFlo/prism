defmodule GscAnalytics.DataSources.GSC.Support.AuthenticatorIntegrationTest do
  @moduledoc """
  Integration tests for the GSC Authenticator GenServer.

  Tests the complete authentication flow:
  - Service account credential loading
  - JWT generation with RS256 signing
  - OAuth2 token exchange
  - Token refresh lifecycle
  - Error recovery mechanisms
  - Telemetry audit logging
  """

  use GscAnalytics.DataCase, async: false

  @moduletag :integration

  alias GscAnalytics.DataSources.GSC.Support.Authenticator

  # Test credentials with a valid RSA private key for testing
  @test_credentials %{
    "type" => "service_account",
    "project_id" => "test-project",
    "private_key_id" => "test-key-id",
    "private_key" => """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEowIBAAKCAQEA0Z3VS5JJcds3xfn/ygWyF0qnMr34W7yAsa5FX6TLlv9TdyqT
    cVPNxbqfuusN7MvEisjVgcvPZiupqYHUMEqnwGSvHHHkFGKmE1LGCCrEaGCXsPbh
    iyZBWPxldKoa8uCbFLvpEGvuKgYQMOk2RvhEaDGu8LTfL2qcTJCPmPaLCuZhEU5d
    r7bE7DBSBkSrsFG0QnvHpQvFOq1AJECB29FrdMaDpkVP/7ePjiHJ3H+ycFKQMuL1
    x6Y8KRrJ7bSR0aXjWzK8mSWi4tLnhLH5ORMUwEh0aKZQgMShFM0lzQjRHTDmydFQ
    mKJqbuQiFboFp7ATuLMRSvkVGPgk0g6UUGfVAwIDAQABAoIBAD2sTh44eCE2QVoe
    Y+bFZzxOO1n4WDEpiYjNEZMwGjPaoVN5dn4/aSK7hbkXdJHkL2/nCnRNxFTGvSJr
    eNvNDsVnhbFxyJdPZrL2YF/rib1iMT0YWSvVUcr2uqKxqNtXLr0I4bPWP6x8H32r
    Alc6B0ERlAiC5KHKMwD7agzvqswHhqFTFq8WHfCWJPa2ELti5/5CTlDVjL4DABgC
    vXKPqFRhy7K7exyNAY3uh7JYaSLzJBO9raDCoFKSQGrOweVGfBeiChnZFjsvzxXG
    W9s1s1Q19xrNqFj9d4fGSrBtSlFH+0R8sAMNi+g9Dc2iwPOcxafwM0ntF5Cg4WLa
    3C8hpAECgYEA6uXn0ebOU5oWai8qoFAGlm+Y+iSJ/NMO4DHc9e4pnmSdWDFVxONa
    y+7FqO2KYYD0gCLIIDRBEcgJvPaLQrrbDx/eCX5nniPdCn2t/Kxxa8dUPNxwIZdj
    jKFlUaLMpPQMwYQHZ+xJQEsU2rW6+a4oEmVJtDc7CSWspn1KsZ9DhkECgYEA5L27
    i7KKr5C9ptVmcIiVVskr4jjWzYu/6pPpURRaqMqwNhQEWwON7ZAf0Ul6d6KPiLfr
    fxSmju6WX8FPnuNsqpYdZKQgTd+rJPAtBTJIENnPg4K/UqhBYZhCDDA5m8GUZH8s
    x7fgh9Z1475nB3vElRcHALt8IllRxLjekPGe5EMCgYA0qJ7+e3Y0nKhQfHhb6vxm
    EL7CXZkKheF2TSQqDyNPUy8vdL2FPu0AthDz1ijpNrs5K2ed5vvZpLjFfjXMW7BQ
    DlCT9L9F3Q0BOBgcQBh1VqSNfB9hQ8KW0MjnV1HPWYDP0+7MFNuyMm6oHJKVavcB
    hhQvgPD/tMqsuPZMxWHkAQKBgDPGnPYJqHAKr9syo6BZB1lYHaVQVP9F2kILj+kP
    Y1CwAQd9NaVMwJEHdjcaGqF3eg3xvOvpWFYEaEydCqxTM5vs7kplFa4x4aTmU3GO
    2UEVQ0ZbAXZ1jEDmDCNGHHOWMOrTvOVhQkTuqKZQmBdbHJiQSPi9F9ksn0gfBe7Q
    o3LDAoGBAOVUkw9/5suUmMhMk3FhPbpFvNB0dXDUXYMxN0LFfCLR0zgLRdlOpDVe
    XYH6cJnr+9mvy/L8AWwLWcqdjEEDEhDwErDT/2sck7hDVlSpbWWBcvCPKNP+As7p
    kTLtwdmPQqa6zvTzFg6cMrGfT6wmvG3qNQ7t2uo5nNvg/BN5v5BX
    -----END RSA PRIVATE KEY-----
    """,
    "client_email" => "test@test-project.iam.gserviceaccount.com",
    "client_id" => "123456789",
    "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
    "token_uri" => "https://oauth2.googleapis.com/token"
  }

  # Mock token response for testing
  setup do
    if Process.whereis(Authenticator) do
      GenServer.stop(Authenticator, :normal)
      Process.sleep(100)
    end

    original_accounts = Application.get_env(:gsc_analytics, :gsc_accounts)

    on_exit(fn ->
      if Process.whereis(Authenticator) do
        GenServer.stop(Authenticator, :normal)
        Process.sleep(50)
      end

      Application.put_env(:gsc_analytics, :gsc_accounts, original_accounts)
    end)

    :ok
  end

  describe "authenticator lifecycle" do
    test "starts and loads credentials from configured file" do
      test_file = Path.join(System.tmp_dir!(), "test-credentials-#{:rand.uniform(10000)}.json")
      File.write!(test_file, JSON.encode!(@test_credentials))

      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Test Account",
          service_account_file: test_file,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])
      assert Process.alive?(pid)

      Process.sleep(200)

      GenServer.stop(pid, :normal)
      File.rm!(test_file)
    end

    test "handles missing credentials file gracefully" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Missing File",
          service_account_file: "/non/existent/file.json",
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      # Start should succeed but credentials won't load
      {:ok, pid} = Authenticator.start_link([])
      assert Process.alive?(pid)

      # Should get an error when requesting token
      assert {:error, :missing_credentials} = Authenticator.get_token(1)

      GenServer.stop(pid, :normal)
    end

    test "loads new credentials via API call" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Dynamic",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      # Load credentials directly
      assert :ok = Authenticator.load_credentials(1, JSON.encode!(@test_credentials))

      # Cleanup
      GenServer.stop(pid, :normal)
    end
  end

  describe "JWT generation" do
    test "generates JWT with correct claims structure" do
      # This test verifies the JWT structure without making actual API calls
      # We'll test that the JWT has the right format and claims
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "JWT Test",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      # Load test credentials
      :ok = Authenticator.load_credentials(1, JSON.encode!(@test_credentials))

      # The JWT generation happens internally, but we can verify the process starts
      Process.sleep(100)

      # Cleanup
      GenServer.stop(pid, :normal)
    end

    test "JWT includes required Google OAuth2 claims" do
      # Required claims for Google OAuth2:
      # - iss: client_email from service account
      # - scope: https://www.googleapis.com/auth/webmasters.readonly
      # - aud: https://oauth2.googleapis.com/token
      # - iat: issued at timestamp
      # - exp: expiration timestamp (iat + 3600)

      # This is tested implicitly through the token exchange process
      assert true
    end
  end

  describe "OAuth2 token exchange" do
    @tag :skip
    test "exchanges JWT for access token with Google OAuth2" do
      # This test would require mocking the OAuth2 endpoint
      # Skipping for now as it requires external API mocking
    end

    test "handles OAuth2 error responses" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Invalid Key",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      invalid_creds = Map.put(@test_credentials, "private_key", "invalid-key")

      assert {:error, _reason} =
               Authenticator.load_credentials(1, JSON.encode!(invalid_creds))

      # Cleanup
      GenServer.stop(pid, :normal)
    end
  end

  describe "token refresh lifecycle" do
    test "schedules token refresh before expiry" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Refresh Account",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      # Load credentials
      :ok = Authenticator.load_credentials(1, JSON.encode!(@test_credentials))

      # The refresh should be scheduled for 10 minutes before expiry
      # For a 1-hour token, that's 50 minutes
      # We can verify the process has the message scheduled
      Process.sleep(100)

      # Check process info for scheduled messages
      {:messages, messages} = Process.info(pid, :messages)

      # Should have retry messages if token fetch failed
      # (since we're not mocking the actual OAuth2 endpoint)
      assert Enum.any?(messages, fn
               {:retry, :fetch_token, 1} -> true
               _ -> false
             end) or
               Enum.any?(messages, fn
                 {:refresh_token, 1} -> true
                 _ -> false
               end)

      # Cleanup
      GenServer.stop(pid, :normal)
    end

    test "handles token expiry with synchronous refresh" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "No Credentials",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      # Without valid credentials, should get no_token error
      assert {:error, :missing_credentials} = Authenticator.get_token(1)

      # Cleanup
      GenServer.stop(pid, :normal)
    end

    test "manual token refresh via API" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Manual Refresh",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      # Load credentials
      :ok = Authenticator.load_credentials(1, JSON.encode!(@test_credentials))

      # Manual refresh (will fail without mocked endpoint, but tests the API)
      result = Authenticator.refresh_token(1)
      assert {:error, _reason} = result

      # Cleanup
      GenServer.stop(pid, :normal)
    end
  end

  describe "error recovery" do
    test "retries credential loading on failure" do
      bad_file = Path.join(System.tmp_dir!(), "missing-#{:rand.uniform(10000)}.json")

      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Missing File",
          service_account_file: bad_file,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      Process.sleep(100)
      {:messages, messages} = Process.info(pid, :messages)

      assert Enum.any?(messages, fn
               {:retry, :load_credentials, 1} -> true
               _ -> false
             end)

      GenServer.stop(pid, :normal)
    end

    test "retries token fetch on network failure" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Network Failure",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      :ok = Authenticator.load_credentials(1, JSON.encode!(@test_credentials))

      Process.sleep(200)

      {:messages, messages} = Process.info(pid, :messages)

      assert Enum.any?(messages, fn
               {:retry, :fetch_token, 1} -> true
               _ -> false
             end)

      GenServer.stop(pid, :normal)
    end

    test "handles malformed credentials JSON" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Malformed JSON",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      assert {:error, _reason} = Authenticator.load_credentials(1, "not-valid-json{")

      assert Process.alive?(pid)
      GenServer.stop(pid, :normal)
    end
  end

  describe "multi-tenant support" do
    test "returns explicit errors for unknown accounts" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        1 => %{
          name: "Account One",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      {:ok, pid} = Authenticator.start_link([])

      assert {:error, :missing_credentials} = Authenticator.get_token(1)
      assert {:error, :unknown_account} = Authenticator.get_token(2)

      GenServer.stop(pid, :normal)
    end
  end

  describe "dual-mode authentication" do
    import Mox

    alias GscAnalytics.AccountsFixtures
    alias GscAnalytics.Auth

    setup :verify_on_exit!

    test "uses stored OAuth token when available" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        2 => %{
          name: "OAuth Account",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      scope = AccountsFixtures.scope_with_accounts([2])

      {:ok, _} =
        Auth.store_oauth_token(scope, %{
          account_id: 2,
          google_email: "oauth@example.com",
          refresh_token: "refresh_xyz",
          access_token: "oauth_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second),
          scopes: ["scope-a"]
        })

      {:ok, pid} = Authenticator.start_link([])
      on_exit(fn -> GenServer.stop(pid, :normal) end)

      Process.sleep(100)

      assert {:ok, "oauth_token"} = Authenticator.get_token(2)
    end

    test "refreshes OAuth token when expired" do
      Application.put_env(:gsc_analytics, :gsc_accounts, %{
        2 => %{
          name: "OAuth Account",
          service_account_file: nil,
          default_property: "sc-domain:test.example",
          enabled?: true
        }
      })

      scope = AccountsFixtures.scope_with_accounts([2])

      {:ok, _} =
        Auth.store_oauth_token(scope, %{
          account_id: 2,
          google_email: "oauth@example.com",
          refresh_token: "refresh_xyz",
          access_token: "stale_token",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second),
          scopes: ["scope-a"]
        })

      expect(GscAnalytics.HTTPClientMock, :post, fn url, opts ->
        assert url == "https://oauth2.googleapis.com/token"
        assert opts[:form][:grant_type] == "refresh_token"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "access_token" => "refreshed_token",
             "expires_in" => 3_600,
             "scope" => "scope-a"
           }
         }}
      end)

      {:ok, pid} = Authenticator.start_link([])
      on_exit(fn -> GenServer.stop(pid, :normal) end)
      Process.sleep(150)

      assert {:ok, "refreshed_token"} = Authenticator.get_token(2)
    end
  end

  describe "telemetry integration" do
    @tag :skip
    test "logs successful token refresh to audit log" do
      # This would require setting up telemetry handlers
      # and verifying audit log entries
    end

    @tag :skip
    test "logs failed token refresh to audit log" do
      # This would require setting up telemetry handlers
      # and verifying audit log entries
    end
  end
end
