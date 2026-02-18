defmodule Sexy do
  @moduledoc """
  Sexy - Telegram framework for Elixir.

  Two entry points:

    * `Sexy.Bot` — Telegram Bot API (polling, sending messages, callbacks)
    * `Sexy.TDL` — TDLib integration (userbot sessions via TDLib binary)

  Add the one you need to your application supervisor:

      children = [
        {Sexy.Bot, token: "BOT_TOKEN", session: MyApp.Session},
        # and/or
        Sexy.TDL,
      ]
  """
end
