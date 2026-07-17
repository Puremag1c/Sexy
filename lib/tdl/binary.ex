defmodule Sexy.TDL.Binary do
  @moduledoc """
  Resolves the `tdlib_json_cli` executable for the current platform.

  Resolution order (first hit wins):

  1. `config :sexy, :tdlib_binary` — authoritative override. A broken
     configured path fails at port open; it never falls through to
     auto-detection.
  2. `SEXY_TDLIB_PATH` environment variable — same authority, for
     deployments where app config is inconvenient.
  3. Per-user cache: `<user cache>/sexy/tdlib_json_cli-<tdlib version>-<target>`,
     filled by `ensure_installed/0`.

  `ensure_installed/0` runs once at `Sexy.TDL` supervisor start (and from
  `mix sexy.tdl.install`): it downloads the platform binary from the GitHub
  release pinned in `priv/tdlib/manifest.json` and verifies its sha256.
  `resolve!/0` never touches the network — it runs on every port restart.
  """

  require Logger

  @doc "Path to the binary. Pure lookup, raises with instructions when absent."
  @spec resolve!() :: String.t()
  def resolve! do
    override() || existing_cache_path() ||
      raise """
      tdlib_json_cli binary not found for this machine.

      Run `mix sexy.tdl.install` (or let Sexy.TDL download it at startup),
      or point config :sexy, :tdlib_binary at your own build.
      """
  end

  @doc "Idempotent: download the pinned binary unless already resolvable."
  @spec ensure_installed() :: :ok | {:error, String.t()}
  def ensure_installed do
    cond do
      override() -> :ok
      existing_cache_path() -> :ok
      true -> download()
    end
  end

  @doc "Release target for this machine, e.g. \"linux-x64\" or \"macos-arm64\"."
  @spec target() :: String.t()
  def target do
    arch_parts =
      :erlang.system_info(:system_architecture) |> List.to_string() |> String.split("-")

    arch = hd(arch_parts)
    abi = List.last(arch_parts)
    wordsize = :erlang.system_info(:wordsize) * 8

    case {:os.type(), arch, abi, wordsize} do
      {{:unix, :darwin}, a, _abi, 64} when a in ~w(arm aarch64) -> "macos-arm64"
      {{:unix, :darwin}, "x86_64", _abi, 64} -> "macos-x64"
      {{:unix, :linux}, "aarch64", "musl", 64} -> "linux-arm64-musl"
      {{:unix, :linux}, "aarch64", _abi, 64} -> "linux-arm64"
      {{:unix, :linux}, a, "musl", 64} when a in ~w(x86_64 amd64) -> "linux-x64-musl"
      {{:unix, :linux}, a, _abi, 64} when a in ~w(x86_64 amd64) -> "linux-x64"
      {{:win32, _}, _a, _abi, 64} -> "windows-x64"
      other -> raise "unsupported platform for tdlib_json_cli auto-detection: #{inspect(other)}"
    end
  end

  @doc "The pinned-release manifest shipped with the package."
  @spec manifest() :: map()
  def manifest do
    Application.app_dir(:sexy, "priv/tdlib/manifest.json")
    |> File.read!()
    |> Jason.decode!()
  end

  # Private

  defp override,
    do: Application.get_env(:sexy, :tdlib_binary) || System.get_env("SEXY_TDLIB_PATH")

  defp existing_cache_path do
    path = cache_path(manifest(), target())
    if File.exists?(path), do: path
  end

  defp cache_path(manifest, target) do
    cache_dir = :filename.basedir(:user_cache, "sexy") |> List.to_string()
    Path.join(cache_dir, "tdlib_json_cli-#{manifest["tdlib_version"]}-#{target}")
  end

  defp download do
    manifest = manifest()
    target = target()

    case manifest["targets"][target] do
      %{"asset" => asset, "sha256" => sha256} ->
        url = manifest["release_url"] <> "/" <> asset
        do_download(url, sha256, cache_path(manifest, target))

      nil ->
        available = manifest["targets"] |> Map.keys() |> Enum.join(", ")

        {:error,
         "no prebuilt tdlib_json_cli for target #{target} " <>
           "(available: #{available}); set config :sexy, :tdlib_binary to your own build"}
    end
  end

  defp do_download(url, expected_sha256, dest) do
    Logger.info("Sexy.TDL: downloading #{url}")

    with {:ok, body} <- fetch(url),
         :ok <- verify_sha256(body, expected_sha256) do
      File.mkdir_p!(Path.dirname(dest))
      tmp = dest <> ".tmp"
      File.write!(tmp, body)
      File.chmod!(tmp, 0o755)
      File.rename!(tmp, dest)
      Logger.info("Sexy.TDL: installed #{dest}")
      :ok
    end
  end

  defp fetch(url) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    ssl_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    request = {String.to_charlist(url), []}
    http_opts = [ssl: ssl_opts, timeout: 120_000]

    case :httpc.request(:get, request, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, "download failed: HTTP #{status} for #{url}"}

      {:error, reason} ->
        {:error, "download failed: #{inspect(reason)} for #{url}"}
    end
  end

  defp verify_sha256(body, expected) do
    actual = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    if actual == expected,
      do: :ok,
      else: {:error, "checksum mismatch: expected #{expected}, got #{actual}"}
  end
end
