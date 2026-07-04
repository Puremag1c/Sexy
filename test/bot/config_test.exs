defmodule Sexy.Bot.ConfigTest do
  use ExUnit.Case, async: false

  alias Sexy.Bot.Config

  @keys [:api_url, :session, :offset_ref]

  setup do
    on_exit(fn -> for k <- @keys, do: :persistent_term.erase({Sexy.Bot, k}) end)
    :ok
  end

  test "writes api_url/session/offset_ref on start, erases api_url/session on stop" do
    start_supervised!({Config, token: "abc", session: MyApp.FakeSession})

    assert :persistent_term.get({Sexy.Bot, :api_url}) == "https://api.telegram.org/botabc"
    assert :persistent_term.get({Sexy.Bot, :session}) == MyApp.FakeSession
    assert :atomics.get(:persistent_term.get({Sexy.Bot, :offset_ref}), 1) == 0

    stop_supervised!(Config)

    # a stopped bot must not keep sending with the stale token/session
    assert :persistent_term.get({Sexy.Bot, :api_url}, :gone) == :gone
    assert :persistent_term.get({Sexy.Bot, :session}, :gone) == :gone
  end

  test "offset_ref survives a bot restart (reused, not recreated)" do
    start_supervised!({Config, token: "a", session: M})
    ref = :persistent_term.get({Sexy.Bot, :offset_ref})
    :atomics.put(ref, 1, 42)
    stop_supervised!(Config)

    # offset_ref is intentionally NOT erased on stop
    assert :persistent_term.get({Sexy.Bot, :offset_ref}) == ref

    start_supervised!({Config, token: "a", session: M})
    # same ref, offset preserved across the restart
    assert :persistent_term.get({Sexy.Bot, :offset_ref}) == ref
    assert :atomics.get(ref, 1) == 42
  end
end
