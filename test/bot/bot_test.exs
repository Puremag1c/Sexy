defmodule Sexy.BotTest do
  use ExUnit.Case, async: true

  # Boot-time validation: bad config must crash at start_link, not run a
  # silently-dead bot. All three raise before any process is started.

  test "raises on a nil token (unset env var)" do
    assert_raise ArgumentError, ~r/token/, fn ->
      Sexy.Bot.start_link(token: nil, session: Sexy.Bot.Session)
    end
  end

  test "raises on an empty token" do
    assert_raise ArgumentError, ~r/token/, fn ->
      Sexy.Bot.start_link(token: "", session: Sexy.Bot.Session)
    end
  end

  test "raises on an unloadable session module" do
    assert_raise ArgumentError, fn ->
      Sexy.Bot.start_link(token: "abc", session: NoSuchSessionModuleXYZ)
    end
  end

  test "raises when :token is missing entirely" do
    assert_raise KeyError, fn -> Sexy.Bot.start_link(session: Sexy.Bot.Session) end
  end

  test "supervision tree wires Config, TaskSupervisor, Dispatchers and Poller" do
    {:ok, {_flags, children}} = Sexy.Bot.init(token: "x", session: Sexy.Bot.Session)
    ids = Enum.map(children, fn spec -> Supervisor.child_spec(spec, []).id end)

    assert Sexy.Bot.Config in ids
    assert Sexy.Bot.TaskSupervisor in ids
    assert Sexy.Bot.Dispatchers in ids
    assert Sexy.Bot.Poller in ids
  end
end
