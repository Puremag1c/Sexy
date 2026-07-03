defmodule Mix.Tasks.Sexy.Tdl.Setup do
  @moduledoc """
  Interactive setup for Sexy.TDL (TDLib integration).

  Guides through configuration:
  1. Path to tdlib_json_cli binary
  2. Data root directory for session storage

  `Sexy.TDL.Object`/`Sexy.TDL.Method` types are bundled with the library —
  no generation step is needed. To regenerate them for a newer TDLib, run
  `mix sexy.tdl.generate_types` inside the sexy repository (or a fork).

  Usage:

      mix sexy.tdl.setup
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.shell().info("── Sexy.TDL Setup ──\n")

    binary = prompt_binary()
    data_root = prompt_data_root()

    write_config(binary, data_root)

    Mix.shell().info("""
    \n── Done! ──

    TDLib types (Sexy.TDL.Object/Method) are already bundled with the library.

    Add to your supervision tree:

        children = [
          Sexy.TDL,
          # ...
        ]

    Then open sessions with:

        config = Sexy.TDL.default_config()
        config = %{config | api_id: "YOUR_ID", api_hash: "YOUR_HASH"}
        Sexy.TDL.open("session_name", config, app_pid: self())
    """)
  end

  # Mix.shell().prompt returns :eof when there is no interactive stdin (CI,
  # piped input) — fail with a clear message instead of a FunctionClauseError.
  defp prompt(message) do
    case Mix.shell().prompt(message) do
      input when is_binary(input) -> String.trim(input)
      _eof -> Mix.raise("sexy.tdl.setup requires an interactive terminal")
    end
  end

  defp prompt_binary do
    default = "/usr/local/bin/tdlib_json_cli"
    input = prompt("Path to tdlib_json_cli binary [#{default}]:")
    path = if input == "", do: default, else: input

    unless File.exists?(path) do
      Mix.shell().info("Warning: #{path} not found. Make sure it exists at runtime.")
    end

    path
  end

  defp prompt_data_root do
    default = "/tmp/tdlib_data"
    input = prompt("Data root directory for sessions [#{default}]:")
    if input == "", do: default, else: input
  end

  defp write_config(binary, data_root) do
    config_path = "config/config.exs"

    snippet = """

    # Sexy.TDL configuration
    config :sexy,
      tdlib_binary: #{inspect(binary)},
      tdlib_data_root: #{inspect(data_root)}
    """

    if File.exists?(config_path) do
      content = File.read!(config_path)

      if String.contains?(content, ":tdlib_binary") do
        Mix.shell().info("\nConfig already contains :tdlib_binary. Skipping config write.")
        Mix.shell().info("Verify your config/config.exs has:")
        Mix.shell().info(snippet)
      else
        File.write!(config_path, content <> snippet)
        Mix.shell().info("\nAppended TDL config to #{config_path}")
      end
    else
      Mix.shell().info("\nNo #{config_path} found. Add this to your config manually:")
      Mix.shell().info(snippet)
    end
  end
end
