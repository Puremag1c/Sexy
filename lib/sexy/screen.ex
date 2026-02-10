defmodule Sexy.Screen do
  @moduledoc """
  Converts app maps into Sexy.Utils.Object structs ready for sending.
  """

  alias Sexy.Utils.Object

  def build(items) when is_list(items), do: Enum.map(items, &build/1)

  def build(map) when is_map(map) do
    struct(%Object{}, map)
  end
end
