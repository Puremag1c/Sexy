defmodule Sexy.TDL.BinaryTest do
  # Resolution order and target detection only — the actual download is
  # exercised by `mix sexy.tdl.install` in CI, not unit tests (network).
  use ExUnit.Case, async: false

  alias Sexy.TDL.Binary

  setup do
    saved = Application.get_env(:sexy, :tdlib_binary)

    on_exit(fn ->
      System.delete_env("SEXY_TDLIB_PATH")

      if saved,
        do: Application.put_env(:sexy, :tdlib_binary, saved),
        else: Application.delete_env(:sexy, :tdlib_binary)
    end)

    :ok
  end

  test "target maps this machine to a known release target" do
    assert Binary.target() in ~w(linux-x64 linux-x64-musl linux-arm64 linux-arm64-musl macos-arm64 macos-x64 windows-x64)
  end

  test "configured :tdlib_binary is authoritative and skips install work" do
    Application.put_env(:sexy, :tdlib_binary, "/bin/cat")
    assert Binary.resolve!() == "/bin/cat"
    assert Binary.ensure_installed() == :ok
  end

  test "SEXY_TDLIB_PATH wins when config is absent" do
    Application.delete_env(:sexy, :tdlib_binary)
    System.put_env("SEXY_TDLIB_PATH", "/bin/echo")
    assert Binary.resolve!() == "/bin/echo"
    assert Binary.ensure_installed() == :ok
  end

  test "manifest pins version, commit, and per-target checksums" do
    manifest = Binary.manifest()

    assert manifest["tdlib_version"] =~ ~r/^\d+\.\d+\.\d+$/
    assert manifest["tdlib_commit"] =~ ~r/^[0-9a-f]{40}$/
    assert manifest["release_url"] =~ ~r{^https://}

    assert %{"asset" => asset, "sha256" => sha} = manifest["targets"]["linux-x64"]
    assert asset =~ manifest["tdlib_version"]
    assert sha =~ ~r/^[0-9a-f]{64}$/
  end
end
