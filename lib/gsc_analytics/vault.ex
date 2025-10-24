defmodule GscAnalytics.Vault do
  use Cloak.Vault, otp_app: :gsc_analytics

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {
          Cloak.Ciphers.AES.GCM,
          # In development/test, use a default key
          # In production, this MUST be set via CLOAK_KEY environment variable
          tag: "AES.GCM.V1",
          key: decode_env!("CLOAK_KEY") || :crypto.strong_rand_bytes(32),
          iv_length: 12
        }
      )

    {:ok, config}
  end

  defp decode_env!(var) do
    case System.get_env(var) do
      nil -> nil
      key -> Base.decode64!(key)
    end
  end
end
