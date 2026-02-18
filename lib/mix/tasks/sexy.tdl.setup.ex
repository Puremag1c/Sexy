defmodule Mix.Tasks.Sexy.Tdl.Setup do
  @moduledoc """
  Interactive setup for Sexy.TDL (TDLib integration).

  Guides through configuration:
  1. Path to tdlib_json_cli binary
  2. Data root directory for session storage
  3. Generates Method/Object types from types.json

  Usage:

      mix sexy.tdl.setup
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.shell().info("── Sexy.TDL Setup ──\n")

    binary = prompt_binary()
    data_root = prompt_data_root()
    types_json = prompt_types_json(binary)

    write_config(binary, data_root)

    if types_json do
      Mix.shell().info("\nGenerating types from #{types_json}...")
      Mix.Task.run("sexy.tdl.generate_types", [types_json])
    end

    Mix.shell().info("""
    \n── Done! ──

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

  defp prompt_binary do
    default = "/usr/local/bin/tdlib_json_cli"

    input =
      Mix.shell().prompt("Path to tdlib_json_cli binary [#{default}]:")
      |> String.trim()

    path = if input == "", do: default, else: input

    unless File.exists?(path) do
      Mix.shell().info("Warning: #{path} not found. Make sure it exists at runtime.")
    end

    path
  end

  defp prompt_data_root do
    default = "/tmp/tdlib_data"

    input =
      Mix.shell().prompt("Data root directory for sessions [#{default}]:")
      |> String.trim()

    if input == "", do: default, else: input
  end

  defp prompt_types_json(binary_path) do
    dir = Path.dirname(binary_path)
    candidate = Path.join(dir, "types.json")

    cond do
      File.exists?(candidate) ->
        answer =
          Mix.shell().prompt("Found types.json at #{candidate}. Generate types? [Y/n]:")
          |> String.trim()
          |> String.downcase()

        if answer in ["", "y", "yes"], do: candidate, else: prompt_custom_types()

      true ->
        Mix.shell().info("No types.json found near binary.")
        prompt_custom_types()
    end
  end

  defp prompt_custom_types do
    input =
      Mix.shell().prompt("Path to types.json (leave empty to skip):")
      |> String.trim()

    if input == "", do: nil, else: input
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
