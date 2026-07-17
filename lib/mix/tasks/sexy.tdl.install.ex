defmodule Mix.Tasks.Sexy.Tdl.Install do
  @shortdoc "Download the pinned tdlib_json_cli binary for this machine"

  @moduledoc """
  Download the `tdlib_json_cli` binary pinned in `priv/tdlib/manifest.json`
  into the per-user cache, verifying its sha256. Idempotent; no-op when
  `config :sexy, :tdlib_binary` (or `SEXY_TDLIB_PATH`) is set.

  `Sexy.TDL` does this automatically at startup — run the task explicitly to
  prefetch, e.g. in CI or a Dockerfile, so first boot needs no network:

      mix sexy.tdl.install
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")

    case Sexy.TDL.Binary.ensure_installed() do
      :ok -> Mix.shell().info("tdlib_json_cli ready: #{Sexy.TDL.Binary.resolve!()}")
      {:error, message} -> Mix.raise(message)
    end
  end
end
