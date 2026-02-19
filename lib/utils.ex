defmodule Sexy.Utils do
  @moduledoc """
  Utility functions used across Sexy: query parsing, number formatting,
  UUID compression, and struct conversion.

  ## Query format

  Sexy uses a compact query format for Telegram callback data:

      "/command key1=value1-key2=value2-key3=value3"

  Values are automatically parsed as integers, floats, or booleans when possible.

  ## Examples

      iex> Sexy.Utils.get_query("/buy id=42-amount=9.99-gift=true")
      %{id: 42, amount: 9.99, gift: true}

      iex> Sexy.Utils.stringify_query(%{id: 42, page: 1})
      "id=42-page=1"

      iex> Sexy.Utils.fiat_chunk(1234567, 0)
      "1 234 567"
  """

  @doc """
  Parse a command string and extract query parameters.

  Returns an empty map if no parameters are present.

  ## Examples

      iex> Sexy.Utils.get_query("/buy id=42-page=1")
      %{id: 42, page: 1}

      iex> Sexy.Utils.get_query("/start")
      %{}
  """
  @spec get_query(String.t()) :: map()
  def get_query(string) do
    string
    |> String.trim("/")
    |> String.split(" ", parts: 2)
    |> case do
      [_command] -> %{}
      [_command, query] -> split_query(query)
    end
  end

  @doc """
  Parse a query string in `"key=val-key=val"` format into an atom-keyed map.

  ## Examples

      iex> Sexy.Utils.split_query("id=42-name=hello")
      %{id: 42, name: "hello"}

      iex> Sexy.Utils.split_query(nil)
      %{}
  """
  @spec split_query(String.t() | nil) :: map()
  def split_query(nil), do: %{}

  def split_query(query_string) do
    query_string
    |> String.split("-")
    |> Enum.map(&split_keyword/1)
    |> Enum.into(%{})
  end

  defp split_keyword(kw_string) do
    kw_string
    |> String.split("=")
    |> then(fn [a, b] -> {String.to_atom(a), parse_value(b)} end)
  end

  defp parse_value(val) do
    cond do
      Regex.match?(~r/^[-]?\d+$/, val) ->
        {int, _} = Integer.parse(val)
        int

      Regex.match?(~r/^[-]?\d+\.\d+$/, val) ->
        {fl, _} = Float.parse(val)
        fl

      val in ["true", "false"] ->
        String.to_existing_atom(val)

      true ->
        val
    end
  end

  @doc """
  Convert an atom-keyed map back to a `"key=val-key=val"` query string.

  ## Example

      iex> Sexy.Utils.stringify_query(%{id: 42, page: 1})
      "id=42-page=1"
  """
  @spec stringify_query(map()) :: String.t()
  def stringify_query(query) do
    Enum.map_join(query, "-", fn {k, v} -> "#{k}=#{stringify_value(v)}" end)
  end

  @doc false
  def stringify_value(val) when is_float(val) do
    :erlang.float_to_binary(val, decimals: 2)
  end

  def stringify_value(val), do: val

  @doc """
  Get a value from a map, falling back to `default` if the key is missing **or** `nil`.

  Unlike `Map.get/3`, this also replaces explicit `nil` values with the default.
  """
  @spec get_and_avoid_nil(map(), atom(), term()) :: term()
  def get_and_avoid_nil(map, key, default) do
    case Map.get(map, key, default) do
      nil -> default
      val -> val
    end
  end

  @doc """
  Recursively convert string keys to atoms and structs to plain maps.

  Used internally to normalize Telegram API responses and TDLib JSON before processing.
  """
  @spec strip(map() | struct() | list() | term()) :: map() | list() | term()
  def strip(map) when is_non_struct_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      if is_atom(k),
        do: Map.put(acc, k, strip(v)),
        else: Map.put(acc, String.to_atom(k), strip(v))
    end)
  end

  def strip(map) when is_struct(map) do
    map
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.put(acc, k, strip(v))
    end)
  end

  def strip(list) when is_list(list) do
    Enum.map(list, &strip/1)
  end

  def strip(value) do
    value
  end

  @doc """
  Format a number with thousands separators (space-separated groups).

  ## Examples

      iex> Sexy.Utils.fiat_chunk(1234567, 0)
      "1 234 567"

      iex> Sexy.Utils.fiat_chunk(1234.5, 2)
      "1 234.50"
  """
  @spec fiat_chunk(number(), non_neg_integer()) :: String.t()
  def fiat_chunk(val, _dec) when is_integer(val) do
    format_integer_part(Integer.to_string(val))
  end

  def fiat_chunk(float, 0) do
    float
    |> :erlang.float_to_binary(decimals: 0)
    |> format_integer_part()
  end

  def fiat_chunk(float, dec) do
    str = :erlang.float_to_binary(float, decimals: dec)
    [int_part, dec_part] = String.split(str, ".")
    format_integer_part(int_part) <> "." <> dec_part
  end

  defp format_integer_part(str) do
    str
    |> String.to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> join_chunks()
  end

  defp join_chunks(chunks) do
    chunks
    |> Enum.reverse()
    |> Enum.map_join(" ", fn chunk -> chunk |> Enum.reverse() |> List.to_string() end)
  end

  @doc """
  Compress a UUID string into a short Base62 representation.

  ## Example

      iex> Sexy.Utils.stringify_uuid("550e8400-e29b-41d4-a716-446655440000")
      "2DEf3recbEMh3MaqjC1UDI"
  """
  @spec stringify_uuid(String.t()) :: String.t()
  def stringify_uuid(uuid) when is_binary(uuid) do
    uuid
    |> String.replace("-", "")
    |> Base.decode16!(case: :lower)
    |> :binary.decode_unsigned()
    |> Base62.encode()
  end

  @doc """
  Expand a Base62-compressed UUID back to the standard `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` format.

  ## Example

      iex> Sexy.Utils.normalize_uuid("2DEf3recbEMh3MaqjC1UDI")
      "550e8400-e29b-41d4-a716-446655440000"
  """
  @spec normalize_uuid(String.t()) :: String.t()
  def normalize_uuid(compact) when is_binary(compact) do
    compact
    |> Base62.decode!()
    |> :binary.encode_unsigned()
    |> Base.encode16(case: :lower)
    |> String.pad_leading(32, "0")
    |> String.replace(~r/^(.{8})(.{4})(.{4})(.{4})(.{12})$/, "\\1-\\2-\\3-\\4-\\5")
  end
end
