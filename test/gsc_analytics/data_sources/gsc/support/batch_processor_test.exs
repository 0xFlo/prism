defmodule GscAnalytics.DataSources.GSC.Support.BatchProcessorValidationTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.GSC.Support.BatchProcessor

  describe "validate_responses/2" do
    test "returns response map when all ids match" do
      requests = [%{id: "a"}, %{id: "b"}]
      responses = [%{id: "b", status: 200}, %{id: "a", status: 200}]

      assert {:ok, result} = BatchProcessor.validate_responses(requests, responses)
      assert result == %{"a" => %{id: "a", status: 200}, "b" => %{id: "b", status: 200}}
    end

    test "returns error when a response is missing" do
      requests = [%{id: "a"}, %{id: "b"}]
      responses = [%{id: "a", status: 200}]

      assert {:error, {:missing_parts, ["b"]}} =
               BatchProcessor.validate_responses(requests, responses)
    end

    test "returns error when an unexpected response id is present" do
      requests = [%{id: "a"}]
      responses = [%{id: "a"}, %{id: "extra"}]

      assert {:error, {:unexpected_parts, ["extra"]}} =
               BatchProcessor.validate_responses(requests, responses)
    end

    test "returns error when duplicate response ids are present" do
      requests = [%{id: "a"}]
      responses = [%{id: "a"}, %{id: "a"}]

      assert {:error, {:duplicate_parts, "a"}} =
               BatchProcessor.validate_responses(requests, responses)
    end
  end
end
