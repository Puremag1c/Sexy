defmodule Sexy.Utils do
  @moduledoc """
    Utils for Sexy
  """

  def get_query(string) do
    string
    |> String.trim("/")
    |> String.split(" ", parts: 2)
    |> case do
      [_command] -> %{}
      [_command, query] -> split_query(query)
    end
  end

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

  def stringify_query(query) do
    query
    |> Enum.map(fn {k, v} -> "#{k}=#{stringify_value(v)}" end)
    |> Enum.join("-")
  end

  def stringify_value(val) when is_float(val) do
    :erlang.float_to_binary(val, [decimals: 2])
  end

  def stringify_value(val), do: val

  def get_and_avoid_nil(map, key, default) do
    case Map.get(map, key, default) do
      nil -> default
      val -> val
    end
  end

  # MapStrings to atoms and Structs to map parser
  def strip(map) when is_non_struct_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      unless is_atom(k),
        do: Map.put(acc, String.to_atom(k), strip(v)),
        else: Map.put(acc, k, strip(v))
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

  def fiat_chunk(val, _0) when is_integer(val) do
    p =
      val
      |> to_string()
      |> String.to_charlist()
      |> Enum.reverse()

    case Enum.chunk_every(p, 3) do
      [t] ->
        t |> List.to_string() |> String.reverse()

      [t, h] ->
        String.reverse(List.to_string(h)) <> " " <> String.reverse(List.to_string(t))

      [t, h, m] ->
        String.reverse(List.to_string(m)) <>
          " " <> String.reverse(List.to_string(h)) <> " " <> String.reverse(List.to_string(t))

      [t, h, m, hh] ->
        String.reverse(List.to_string(hh)) <> " " <>
          String.reverse(List.to_string(m)) <> " " <>
          String.reverse(List.to_string(h)) <> " " <>
          String.reverse(List.to_string(t))
    end
  end

  def fiat_chunk(float, 0) do
    p =
      float
      |> :erlang.float_to_binary(decimals: 0)
      |> String.to_charlist()
      |> Enum.reverse()

    case Enum.chunk_every(p, 3) do
      [t] ->
        t |> List.to_string() |> String.reverse()

      [t, h] ->
        String.reverse(List.to_string(h)) <> " " <> String.reverse(List.to_string(t))

      [t, h, m] ->
        String.reverse(List.to_string(m)) <>
          " " <> String.reverse(List.to_string(h)) <> " " <> String.reverse(List.to_string(t))

      [t, h, m, hh] ->
        String.reverse(List.to_string(hh)) <> " " <>
          String.reverse(List.to_string(m)) <> " " <>
          String.reverse(List.to_string(h)) <> " " <>
          String.reverse(List.to_string(t))
    end
  end

  def fiat_chunk(float, dec) do
    p =
      float
      |> :erlang.float_to_binary(decimals: dec)
      |> String.to_charlist()
      |> Enum.reverse()

    nu =
      case Enum.at(p, 1) do
        46 ->
          String.to_charlist("0" <> List.to_string(p))

        _ ->
          p
      end

    case Enum.chunk_every(nu, 6) do
      [t] ->
        t |> List.to_string() |> String.reverse()

      [t, h] ->
        case Enum.chunk_every(h, 3) do
          [m] ->
            String.reverse(List.to_string(m)) <> " " <> String.reverse(List.to_string(t))

          [m, hh] ->
            String.reverse(List.to_string(hh)) <>
              " " <> String.reverse(List.to_string(m)) <> " " <> String.reverse(List.to_string(t))
        end

      [t, h, d] ->
        [m, hh] = Enum.chunk_every(h, 3)

        case Enum.chunk_every(d, 3) do
          [g] ->
            String.reverse(List.to_string(g)) <>
              " " <>
              String.reverse(List.to_string(hh)) <>
              " " <> String.reverse(List.to_string(m)) <> " " <> String.reverse(List.to_string(t))

          [g, hhh] ->
            String.reverse(List.to_string(hhh)) <>
              " " <>
              String.reverse(List.to_string(g)) <>
              " " <>
              String.reverse(List.to_string(hh)) <>
              " " <> String.reverse(List.to_string(m)) <> " " <> String.reverse(List.to_string(t))
        end
    end
  end

  def stringify_uuid(uuid) when is_binary(uuid) do
    uuid
    |> String.replace("-", "")
    |> Base.decode16!(case: :lower)
    |> :binary.decode_unsigned()
    |> Base62.encode()
  end

  def normalize_uuid(compact) when is_binary(compact) do
    compact
    |> Base62.decode!()
    |> :binary.encode_unsigned()
    |> Base.encode16(case: :lower)
    |> String.pad_leading(32, "0")
    |> String.replace(~r/^(.{8})(.{4})(.{4})(.{4})(.{12})$/, "\\1-\\2-\\3-\\4-\\5")
  end

end
