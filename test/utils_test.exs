defmodule Sexy.UtilsTest do
  use ExUnit.Case, async: true

  alias Sexy.Utils

  # ── get_query/1 ──────────────────────────────────────────────

  describe "get_query/1" do
    test "parses command with query params" do
      assert Utils.get_query("/buy id=42-page=1") == %{id: 42, page: 1}
    end

    test "returns empty map for command without params" do
      assert Utils.get_query("/start") == %{}
    end

    test "parses typed values (int, float, bool, string)" do
      result = Utils.get_query("/cmd count=5-price=9.99-active=true-name=hello")
      assert result == %{count: 5, price: 9.99, active: true, name: "hello"}
    end

    test "handles command with leading slash trimmed" do
      assert Utils.get_query("buy id=1") == %{id: 1}
    end

    test "parses false boolean" do
      assert Utils.get_query("/cmd flag=false") == %{flag: false}
    end
  end

  # ── split_query/1 ────────────────────────────────────────────

  describe "split_query/1" do
    test "parses key=val-key=val format" do
      assert Utils.split_query("id=42-name=hello") == %{id: 42, name: "hello"}
    end

    test "returns empty map for nil" do
      assert Utils.split_query(nil) == %{}
    end

    test "parses integer values" do
      assert Utils.split_query("count=10") == %{count: 10}
    end

    test "parses float values" do
      assert Utils.split_query("price=9.99") == %{price: 9.99}
    end

    test "parses boolean values" do
      assert Utils.split_query("a=true-b=false") == %{a: true, b: false}
    end

    test "keeps string values as strings" do
      assert Utils.split_query("name=hello") == %{name: "hello"}
    end
  end

  # ── stringify_query/1 ────────────────────────────────────────

  describe "stringify_query/1" do
    test "converts map to key=val string" do
      result = Utils.stringify_query(%{id: 42})
      assert result == "id=42"
    end

    test "formats floats with 2 decimals" do
      result = Utils.stringify_query(%{price: 9.9})
      assert result == "price=9.90"
    end

    test "handles multiple keys" do
      result = Utils.stringify_query(%{a: 1, b: 2})
      parts = String.split(result, "-") |> Enum.sort()
      assert parts == ["a=1", "b=2"]
    end

    test "handles string values" do
      assert Utils.stringify_query(%{name: "hello"}) == "name=hello"
    end
  end

  # ── get_and_avoid_nil/3 ──────────────────────────────────────

  describe "get_and_avoid_nil/3" do
    test "returns existing value" do
      assert Utils.get_and_avoid_nil(%{name: "bob"}, :name, "default") == "bob"
    end

    test "returns default when key is nil" do
      assert Utils.get_and_avoid_nil(%{name: nil}, :name, "default") == "default"
    end

    test "returns default when key is missing" do
      assert Utils.get_and_avoid_nil(%{}, :name, "default") == "default"
    end

    test "returns zero (not nil) correctly" do
      assert Utils.get_and_avoid_nil(%{count: 0}, :count, 10) == 0
    end

    test "returns false (not nil) correctly" do
      assert Utils.get_and_avoid_nil(%{flag: false}, :flag, true) == false
    end
  end

  # ── strip/1 ──────────────────────────────────────────────────

  describe "strip/1" do
    test "converts string keys to atom keys" do
      assert Utils.strip(%{"name" => "bob", "age" => 25}) == %{name: "bob", age: 25}
    end

    test "keeps atom keys as-is" do
      assert Utils.strip(%{name: "bob"}) == %{name: "bob"}
    end

    test "recursively strips nested maps" do
      input = %{"user" => %{"name" => "bob"}}
      assert Utils.strip(input) == %{user: %{name: "bob"}}
    end

    test "strips structs to plain maps" do
      obj = %Sexy.Utils.Object{chat_id: 123, text: "hi"}
      result = Utils.strip(obj)
      assert is_map(result)
      refute Map.has_key?(result, :__struct__)
      assert result.chat_id == 123
      assert result.text == "hi"
    end

    test "strips lists recursively" do
      input = [%{"a" => 1}, %{"b" => 2}]
      assert Utils.strip(input) == [%{a: 1}, %{b: 2}]
    end

    test "returns plain values as-is" do
      assert Utils.strip("hello") == "hello"
      assert Utils.strip(42) == 42
      assert Utils.strip(nil) == nil
    end
  end

  # ── fiat_chunk/2 ─────────────────────────────────────────────

  describe "fiat_chunk/2" do
    test "formats integer with thousands separators" do
      assert Utils.fiat_chunk(1_234_567, 0) == "1 234 567"
    end

    test "formats small integer" do
      assert Utils.fiat_chunk(42, 0) == "42"
    end

    test "formats float with decimals" do
      assert Utils.fiat_chunk(1234.5, 2) == "1 234.50"
    end

    test "formats float with 0 decimals" do
      assert Utils.fiat_chunk(1234.0, 0) == "1 234"
    end

    test "formats negative integer" do
      assert Utils.fiat_chunk(-1234, 0) == "-1 234"
    end

    test "formats zero" do
      assert Utils.fiat_chunk(0, 0) == "0"
    end

    test "formats large number" do
      assert Utils.fiat_chunk(1_000_000_000, 0) == "1 000 000 000"
    end
  end

  # ── stringify_uuid/1 + normalize_uuid/1 ──────────────────────

  describe "UUID roundtrip" do
    test "stringify_uuid compresses a UUID" do
      result = Utils.stringify_uuid("550e8400-e29b-41d4-a716-446655440000")
      assert is_binary(result)
      assert String.length(result) < 36
    end

    test "normalize_uuid expands back" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      compressed = Utils.stringify_uuid(uuid)
      assert Utils.normalize_uuid(compressed) == uuid
    end

    test "roundtrip with different UUID" do
      uuid = "00000000-0000-0000-0000-000000000001"
      assert uuid == uuid |> Utils.stringify_uuid() |> Utils.normalize_uuid()
    end

    test "roundtrip with all-f UUID" do
      uuid = "ffffffff-ffff-ffff-ffff-ffffffffffff"
      assert uuid == uuid |> Utils.stringify_uuid() |> Utils.normalize_uuid()
    end
  end
end
