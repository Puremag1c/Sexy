defmodule Mix.Tasks.Sexy.Tdl.GenerateTypes do
  @moduledoc """
  Generate `Sexy.TDL.Object` and `Sexy.TDL.Method` structs from a TDLib `types.json`.

  Run this **inside the sexy repository (or a fork/vendored copy)** when a new
  TDLib version ships:

      mix sexy.tdl.generate_types /path/to/types.json

  It overwrites `lib/tdl/object.ex` and `lib/tdl/method.ex` — the files shipped
  with the library.

  Running it in a consumer project is refused: the generated modules would
  duplicate the ones already compiled in the `:sexy` dependency, and
  `mix release` fails on duplicated modules. Pass `--force` only if you know
  exactly why you need that.
  """
  use Mix.Task
  require Logger

  @object_module "lib/tdl/object.ex"
  @method_module "lib/tdl/method.ex"

  def run(args) do
    {opts, args} = OptionParser.parse!(args, strict: [force: :boolean])

    unless Mix.Project.config()[:app] == :sexy or opts[:force] do
      Mix.raise("""
      sexy.tdl.generate_types must run inside the sexy repository (or a fork).

      Generating Sexy.TDL.Object/Method into this project would duplicate the
      modules already compiled in the :sexy dependency and break `mix release`.
      To use types for a newer TDLib, regenerate them in a fork of sexy and
      depend on that fork. Pass --force to override.
      """)
    end

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

    File.mkdir_p!(Path.dirname(@object_module))
    generate_module(@object_module, "Sexy.TDL.Object", json, objects)
    generate_module(@method_module, "Sexy.TDL.Method", json, methods)

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

  # Write to a temp file and rename over the target only on success, so a
  # malformed types.json can't destroy the previously generated modules.
  defp generate_module(path, module_name, json, keys) do
    Logger.info("Writing #{module_name}...")
    tmp = path <> ".tmp"
    fd = File.open!(tmp, [:write, encoding: :utf8])

    IO.write(fd, """
    defmodule #{module_name} do
      @moduledoc \"""
      This module was generated using Telegram's TDLib documentation. It contains
      #{Enum.count(keys)} submodules (= structs).
      \"""
    """)

    for key <- keys do
      IO.write(fd, build_type(key, Map.get(json, key)))
    end

    IO.write(fd, "end")
    File.close(fd)
    File.rename!(tmp, path)
  end

  defp build_type(key, json_type) do
    key = identifier!(key)
    module_name = Sexy.Utils.titlecase_once(key)

    %{"url" => url, "fields" => fields} = json_type
    desc = json_type |> Map.get("desc") |> escape_doc()

    struct_fields = build_fields_string(fields)

    fields_doc =
      unless Enum.empty?(fields) do
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

        More details on [telegram's documentation](#{escape_doc(url)}).
        \"""

        defstruct "@type": "#{key}", "@extra": nil#{struct_fields}
      end
      """
  end

  # Doc text is spliced into interpolating heredocs of the generated source —
  # escape everything that could break out of them (code execution at the
  # consumer's compile time otherwise).
  defp escape_doc(nil), do: nil

  defp escape_doc(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("\#{", "\\\#{")
    |> String.replace(~s("""), ~s(\\"""))
  end

  # Type and field names become module names and struct keys — escaping can't
  # make an arbitrary string a safe identifier, so validate instead: a name that
  # isn't a plain identifier can't inject code via #{module_name}/defstruct.
  defp identifier!(name) do
    if is_binary(name) and Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, name) do
      name
    else
      raise "invalid identifier in types.json: #{inspect(name)}"
    end
  end

  defp build_fields_string(list) do
    List.foldl(list, "", fn field, acc ->
      acc <> ", #{identifier!(Map.get(field, "name"))}: nil"
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
        "| #{escape_doc(Map.get(m, "name"))} | #{escape_doc(Map.get(m, "type"))} | #{escape_doc(Map.get(m, "desc"))} |\n"
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
end
