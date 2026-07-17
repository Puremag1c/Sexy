defmodule Mix.Tasks.Sexy.Tdl.GenerateTypes do
  @moduledoc """
  Generate `Sexy.TDL.Object` and `Sexy.TDL.Method` structs from a TDLib schema.

  Accepts either `td_api.tl` (shipped in the TDLib source tree at
  `td/generate/scheme/td_api.tl` — no TDLib build needed) or a legacy
  `types.json`. Run this **inside the sexy repository (or a fork/vendored
  copy)** when a new TDLib version ships:

      mix sexy.tdl.generate_types /path/to/td_api.tl
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

  # .tl builtins carry no doc comments by design — anything else undocumented
  # is an error (a silently dropped type = silently missing struct downstream)
  @tl_builtins ~w(double string int32 int53 int64 bytes boolFalse boolTrue vector)
  @doxygen_prefix "https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1"

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

    {json, objects, methods} =
      if Path.extname(json_source) == ".tl" do
        Logger.info("Parsing TL schema...")
        extract_tl(text)
      else
        Logger.info("Parsing JSON...")
        extract(text)
      end

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

  # ── td_api.tl parsing ─────────────────────────────────────────────────
  # Line-oriented state machine: `//` comment lines accumulate and attach to
  # the next `name f:t ... = Result;` definition; `//@class` groups stand
  # alone (abstract classes); `---functions---` switches object → function.
  # Produces the same map shape extract/1 gets from types.json.

  defp extract_tl(text) do
    {entries, warnings} = tl_parse(String.split(text, "\n"), :object, [], [], [])

    if warnings != [] do
      Mix.raise(
        "td_api.tl parse problems (#{length(warnings)}):\n" <>
          Enum.join(Enum.take(warnings, 20), "\n")
      )
    end

    json = Map.new(entries)
    type_filter = fn k, t -> json |> Map.get(k) |> Map.get("type") == t end
    keys = Map.keys(json)

    {json, Enum.filter(keys, &type_filter.(&1, "object")),
     Enum.filter(keys, &type_filter.(&1, "function"))}
  end

  defp tl_parse([], _kind, _comments, entries, warnings), do: {entries, Enum.reverse(warnings)}

  defp tl_parse([line | rest], kind, comments, entries, warnings) do
    line = String.trim_trailing(line)

    cond do
      line == "---functions---" ->
        tl_parse(rest, :function, [], entries, warnings)

      String.starts_with?(line, "//") ->
        tl_parse(rest, kind, comments ++ [line], entries, warnings)

      line == "" ->
        {entries, warnings} = tl_flush_class(comments, entries, warnings)
        tl_parse(rest, kind, [], entries, warnings)

      String.contains?(line, "=") and String.ends_with?(line, ";") ->
        {entries, warnings} = tl_definition(line, comments, kind, entries, warnings)
        tl_parse(rest, kind, [], entries, warnings)

      true ->
        tl_parse(rest, kind, comments, entries, ["unhandled line: #{line}" | warnings])
    end
  end

  # A comment group followed by a blank line is either an @class declaration
  # (abstract base type — emitted as a field-less object) or dangling noise.
  defp tl_flush_class(comments, entries, warnings) do
    joined = tl_join_comments(comments)

    cond do
      String.starts_with?(joined, "@class ") ->
        tokens = tl_tokenize(joined, ["class", "description"])
        name = tokens |> Map.fetch!("class") |> String.trim()

        entry = %{
          "type" => "object",
          "url" => doxygen_url(name),
          "desc" => Map.get(tokens, "description", ""),
          "fields" => []
        }

        {[{name, entry} | entries], warnings}

      joined != "" and String.starts_with?(joined, "@") ->
        {entries, ["dangling comment group: #{String.slice(joined, 0, 80)}" | warnings]}

      true ->
        {entries, warnings}
    end
  end

  defp tl_definition(line, comments, kind, entries, warnings) do
    # `name f1:t1 f2:t2 = ResultType;`
    [decl, _result] = String.split(line, "=", parts: 2)
    [name | field_tokens] = decl |> String.trim() |> String.split(~r/\s+/)

    case tl_join_comments(comments) do
      "" when name in @tl_builtins ->
        {entries, warnings}

      "" ->
        {entries, ["undocumented definition skipped: #{name}" | warnings]}

      joined ->
        fields =
          field_tokens
          |> Enum.filter(&String.contains?(&1, ":"))
          |> Enum.map(fn tok ->
            [fname, ftype] = String.split(tok, ":", parts: 2)
            {fname, tl_map_type(ftype)}
          end)

        field_names = Enum.map(fields, &elem(&1, 0))
        tokens = tl_tokenize(joined, ["description" | field_names])

        warnings =
          case Map.keys(tokens) -- ["description" | field_names] do
            [] -> warnings
            extra -> ["unknown doc tokens in #{name}: #{inspect(extra)}" | warnings]
          end

        fields_json =
          Enum.map(fields, fn {fname, ftype} ->
            %{"name" => fname, "type" => ftype, "desc" => Map.get(tokens, fname, "")}
          end)

        entry = %{
          "type" => to_string(kind),
          "url" => doxygen_url(name),
          "desc" => Map.get(tokens, "description", ""),
          "fields" => fields_json
        }

        {[{name, entry} | entries], warnings}
    end
  end

  # Strip `//`; a `//-` line continues the previous line's text.
  defp tl_join_comments(comments) do
    comments
    |> Enum.map(&String.trim_leading(&1, "//"))
    |> Enum.reduce("", fn line, acc ->
      cond do
        String.starts_with?(line, "-") -> acc <> " " <> String.trim_leading(line, "-")
        acc == "" -> line
        true -> acc <> " " <> line
      end
    end)
    |> String.trim()
  end

  # Split "@name text @name2 text2" into %{name => text}. Only `allowed` names
  # start a new token; any other literal `@word` stays inside the running text.
  defp tl_tokenize(text, allowed) do
    parts = Regex.split(~r/@(?=\w+)/, text, trim: true)
    {map, _current} = Enum.reduce(parts, {%{}, nil}, &tl_take_part(&1, &2, allowed))
    map
  end

  defp tl_take_part(part, {map, current}, allowed) do
    case Regex.run(~r/^(\w+)[ \t]+(.*)$/s, part) do
      [_, word, tail] ->
        if word in allowed and not Map.has_key?(map, word) do
          {Map.put(map, word, String.trim(tail)), word}
        else
          tl_append(map, current, "@" <> part)
        end

      _ ->
        tl_append(map, current, "@" <> part)
    end
  end

  defp tl_append(map, nil, _text), do: {map, nil}
  defp tl_append(map, current, text), do: {Map.update!(map, current, &(&1 <> text)), current}

  # doxygen file-name mangling (CASE_SENSE_NAMES=NO): uppercase → "_" + lower
  # (including a leading one for capitalized class names), literal "_" → "__"
  defp doxygen_url(name) do
    mangled =
      name
      |> String.graphemes()
      |> Enum.map_join(fn
        "_" -> "__"
        <<c>> when c in ?A..?Z -> <<?_, c + 32>>
        g -> g
      end)

    @doxygen_prefix <> mangled <> ".html"
  end

  # Cosmetic type strings for the docs tables — matches the legacy scraper's
  # rendering of TDLib's JSON interface (int32 → number, int53/int64 → string)
  defp tl_map_type("int32"), do: "number"
  defp tl_map_type("int53"), do: "string"
  defp tl_map_type("int64"), do: "string"
  defp tl_map_type("Bool"), do: "bool"

  defp tl_map_type("vector<" <> rest),
    do: rest |> String.trim_trailing(">") |> tl_map_type() |> Kernel.<>("[]")

  defp tl_map_type(other), do: other

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
