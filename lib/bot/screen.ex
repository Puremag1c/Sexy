defmodule Sexy.Bot.Screen do
  @moduledoc """
  Converts plain maps into `Sexy.Utils.Object` structs ready for sending.

  This is a thin wrapper — `build/1` simply calls `struct/2`. The module exists
  to provide a clear semantic entry point in the pipeline:

      %{chat_id: 123, text: "Hello", kb: %{inline_keyboard: [...]}}
      |> Sexy.Bot.Screen.build()   # => %Sexy.Utils.Object{...}
      |> Sexy.Bot.Sender.deliver()

  Usually called via `Sexy.Bot.build/1`.
  """

  alias Sexy.Utils.Object

  @doc """
  Build an Object struct from a map or a list of maps.

  ## Examples

      iex> Sexy.Bot.Screen.build(%{chat_id: 123, text: "Hi"})
      %Sexy.Utils.Object{chat_id: 123, text: "Hi"}

      iex> Sexy.Bot.Screen.build([%{chat_id: 1, text: "A"}, %{chat_id: 2, text: "B"}])
      [%Sexy.Utils.Object{chat_id: 1, text: "A"}, %Sexy.Utils.Object{chat_id: 2, text: "B"}]
  """
  def build(items) when is_list(items), do: Enum.map(items, &build/1)

  def build(map) when is_map(map) do
    struct(%Object{}, map)
  end
end
