defmodule Mix.Tasks.Sexy.Tdl.GenerateTypes do
  @moduledoc "Generate Sexy.TDL.Object and Sexy.TDL.Method structs from TDLib types.json"
  use Mix.Task
  require Logger

  @object_module "lib/sexy/tdl/object.ex"
  @method_module "lib/sexy/tdl/method.ex"

  def run(args) do
    json_source =
      case args do
        [path] -> path
        _ -> "types.json"
      end

    Logger.info("Importing #{json_source}...")
    text = File.read!(json_source)

    Logger.info("Parsing JSON...")
    {json, objects, methods} = extract(text)
    Logger.info("#{Enum.count(objects)} objects found.")
    Logger.info("#{Enum.count(methods)} methods found.")

    remove_old_modules()
    generate_object_module(json, objects)
    generate_method_module(json, methods)

    Logger.info("Done.")
  end

  defp extract(text) do
    json = Jason.decode!(text)
    keys = Map.keys(json)
    type_filter = fn k, t -> json |> Map.get(k) |> Map.get("type") == t end

    objects = Enum.filter(keys, &type_filter.(&1, "object"))
    methods = Enum.filter(keys, &type_filter.(&1, "function"))

    {json, objects, methods}
  end

  defp remove_old_modules do
    File.rm(@object_module)
    File.rm(@method_module)
  end

  defp generate_object_module(json, objects) do
    Logger.info("Writing object module...")
    fd = File.open!(@object_module, [:write, encoding: :utf8])

    IO.write(fd, """
    defmodule Sexy.TDL.Object do
      @moduledoc \"""
      This module was generated using Telegram's TDLib documentation. It contains
      #{Enum.count(objects)} submodules (= structs).
      \"""
    """)

    for key <- objects do
      json_object = Map.get(json, key)
      IO.write(fd, build_type(key, json_object))
    end

    IO.write(fd, "end")
    File.close(fd)
  end

  defp generate_method_module(json, methods) do
    Logger.info("Writing method module...")
    fd = File.open!(@method_module, [:write, encoding: :utf8])

    IO.write(fd, """
    defmodule Sexy.TDL.Method do
      @moduledoc \"""
      This module was generated using Telegram's TDLib documentation. It contains
      #{Enum.count(methods)} submodules (= structs).
      \"""
    """)

    for key <- methods do
      json_method = Map.get(json, key)
      IO.write(fd, build_type(key, json_method))
    end

    IO.write(fd, "end")
    File.close(fd)
  end

  defp build_type(key, json_type) do
    module_name = titlecase_once(key)

    %{"url" => url, "fields" => fields} = json_type
    desc = Map.get(json_type, "desc")

    struct_fields = build_fields_string(fields)

    fields_doc =
      if Enum.count(fields) > 0 do
        build_fields_doc(fields)
      end

    """
    defmodule #{module_name} do
      @moduledoc  \"""
    """ <>
      format_lines(desc, 2) <>
      "\n" <>
      format_lines(fields_doc, 2) <>
      """

        More details on [telegram's documentation](#{url}).
        \"""

        defstruct "@type": "#{key}", "@extra": nil#{struct_fields}
      end
      """
  end

  defp build_fields_string(list) do
    List.foldl(list, "", fn field, acc ->
      acc <> ", #{Map.get(field, "name")}: nil"
    end)
  end

  defp build_fields_doc(list) do
    table_header = """
    | Name | Type | Description |
    |------|------| ------------|
    """

    table_lines =
      list
      |> Enum.map(fn m ->
        "| #{Map.get(m, "name")} | #{Map.get(m, "type")} | #{Map.get(m, "desc")} |\n"
      end)
      |> List.to_string()

    table_header <> table_lines
  end

  defp format_lines(nil, _padding), do: ""

  defp format_lines(text, padding) do
    pad = fn s -> String.duplicate(" ", padding) <> s <> "\n" end

    text
    |> String.trim("\n")
    |> String.split("\n")
    |> Enum.map(&pad.(&1))
    |> List.to_string()
  end

  defp titlecase_once(str) do
    first_letter = String.first(str)
    String.replace_prefix(str, first_letter, String.upcase(first_letter))
  end
end
