defmodule Sexy do
  @moduledoc """
  Telegram framework for Elixir — bots and userbots from one dependency.

  Sexy provides two independent engines that can run side by side:

  ## Sexy.Bot — Bot API

  A framework built around the **single-message UI pattern**: every screen replaces the
  previous one, creating an app-like experience inside Telegram. Sexy handles the full
  message lifecycle — type detection, API calls, old message deletion, and state persistence
  via your `Sexy.Bot.Session` implementation.

      children = [
        {Sexy.Bot, token: System.get_env("BOT_TOKEN"), session: MyApp.Session}
      ]

  See `Sexy.Bot` for the public API and `Sexy.Bot.Session` for the behaviour you implement.

  ## Sexy.TDL — TDLib Integration

  Manages userbot sessions through a port to `tdlib_json_cli`. JSON responses are
  automatically deserialized into Elixir structs (`Sexy.TDL.Object.*` and `Sexy.TDL.Method.*`).

      children = [
        Sexy.TDL
      ]

      # Then open a session:
      config = %{Sexy.TDL.default_config() | api_id: "12345", api_hash: "abc123"}
      Sexy.TDL.open("my_account", config, app_pid: self())

  See `Sexy.TDL` for the full API.

  ## Architecture

      Sexy.Bot (Supervisor)                Sexy.TDL (Supervisor)
        └── Poller (GenServer)               ├── Registry (ETS)
              ↓ routes updates               └── AccountVisor (DynamicSupervisor)
              Session (your app)                   └── Riser per session
              ↓ builds screens                           ├── Backend (Port)
              Sender → Telegram API                      └── Handler (JSON→structs)
  """
end
