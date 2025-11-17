# T003: SerpSnapshot Ecto Schema

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🔥 P1 Critical
**TDD Required:** No (schema definition)

## Description
Create the Ecto schema for storing SERP snapshots with proper foreign key relationships to properties and accounts.

## Acceptance Criteria
- [ ] SerpSnapshot schema created in `lib/gsc_analytics/schemas/`
- [ ] Uses property_id foreign key (NOT just URL strings)
- [ ] Includes all required fields: keyword, position, serp_features, competitors
- [ ] Query helpers implemented: `for_property/2`, `latest_for_url/2`
- [ ] Validations implemented via changeset

## Implementation Steps

1. **Create schema file**
   ```elixir
   # lib/gsc_analytics/schemas/serp_snapshot.ex
   defmodule GscAnalytics.Schemas.SerpSnapshot do
     use Ecto.Schema
     import Ecto.Changeset
     import Ecto.Query

     @primary_key {:id, :binary_id, autogenerate: true}
     @foreign_key_type :binary_id

     schema "serp_snapshots" do
       # Relations (CRITICAL: Use property_id for tenancy)
       field :account_id, :integer
       belongs_to :property, GscAnalytics.Schemas.Property

       # URL being checked
       field :url, :string

       # SERP Data
       field :keyword, :string
       field :position, :integer
       field :serp_features, {:array, :string}, default: []
       field :competitors, {:array, :map}, default: []
       field :raw_response, :map  # Full JSON from ScrapFly

       # Metadata
       field :geo, :string, default: "us"
       field :checked_at, :utc_datetime
       field :api_cost, :decimal
       field :error_message, :string

       timestamps(type: :utc_datetime, updated_at: false)
     end

     @doc "Changeset for creating SERP snapshots"
     def changeset(snapshot, attrs) do
       snapshot
       |> cast(attrs, [
         :account_id, :property_id, :url, :keyword, :position,
         :serp_features, :competitors, :raw_response, :geo,
         :checked_at, :api_cost, :error_message
       ])
       |> validate_required([:account_id, :property_id, :url, :keyword, :checked_at])
       |> validate_url(:url)
       |> validate_number(:position, greater_than: 0, less_than_or_equal_to: 100)
       |> foreign_key_constraint(:property_id)
     end

     # Query Helpers

     def for_property(query \\ __MODULE__, property_id) do
       from(s in query, where: s.property_id == ^property_id)
     end

     def for_url(query \\ __MODULE__, url) do
       from(s in query, where: s.url == ^url)
     end

     def latest_for_url(query \\ __MODULE__, property_id, url) do
       query
       |> for_property(property_id)
       |> for_url(url)
       |> order_by([s], desc: s.checked_at)
       |> limit(1)
     end

     def with_position(query \\ __MODULE__) do
       from(s in query, where: not is_nil(s.position))
     end

     defp validate_url(changeset, field) do
       validate_change(changeset, field, fn _, url ->
         case URI.parse(url) do
           %URI{scheme: scheme} when scheme in ["http", "https"] -> []
           _ -> [{field, "must be a valid HTTP(S) URL"}]
         end
       end)
     end
   end
   ```

2. **Create test file**
   ```elixir
   # test/gsc_analytics/schemas/serp_snapshot_test.exs
   defmodule GscAnalytics.Schemas.SerpSnapshotTest do
     use GscAnalytics.DataCase, async: true

     alias GscAnalytics.Schemas.SerpSnapshot

     describe "changeset/2" do
       test "valid attributes" do
         attrs = %{
           account_id: 1,
           property_id: Ecto.UUID.generate(),
           url: "https://example.com",
           keyword: "test",
           checked_at: DateTime.utc_now()
         }

         changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
         assert changeset.valid?
       end

       test "requires account_id" do
         attrs = %{property_id: Ecto.UUID.generate(), url: "https://example.com", keyword: "test"}
         changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
         refute changeset.valid?
         assert "can't be blank" in errors_on(changeset).account_id
       end

       test "validates URL format" do
         attrs = %{
           account_id: 1,
           property_id: Ecto.UUID.generate(),
           url: "not-a-url",
           keyword: "test",
           checked_at: DateTime.utc_now()
         }

         changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
         refute changeset.valid?
       end

       test "validates position range" do
         attrs = %{
           account_id: 1,
           property_id: Ecto.UUID.generate(),
           url: "https://example.com",
           keyword: "test",
           position: 101,
           checked_at: DateTime.utc_now()
         }

         changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
         refute changeset.valid?
       end
     end

     describe "query helpers" do
       test "for_property/2 filters by property_id" do
         property_id = Ecto.UUID.generate()
         query = SerpSnapshot.for_property(property_id)
         assert %Ecto.Query{} = query
       end
     end
   end
   ```

## Definition of Done
- [ ] Schema created with property_id foreign key
- [ ] Changeset with validations
- [ ] Query helpers implemented
- [ ] Tests pass
- [ ] Ready for migration

## Notes
- **CRITICAL:** Use property_id FK, not just URL strings (Codex requirement)
- Enables proper tenancy enforcement with @current_scope
- raw_response field stores full JSON for debugging/re-parsing

## 📚 Reference Documentation
- **Ecto Schemas:** [Guide](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md)
- **Example:** `lib/gsc_analytics/schemas/performance.ex`
