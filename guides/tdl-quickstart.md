# TDLib Quick Start

Build a Telegram userbot with `Sexy.TDL`.

## Prerequisites

- `tdlib_json_cli` binary installed (or built from TDLib source)
- Telegram API credentials from [my.telegram.org](https://my.telegram.org)

## 1. Configure

```elixir
# config/config.exs
config :sexy,
  tdlib_binary: "/usr/local/bin/tdlib_json_cli",
  tdlib_data_root: "/tmp/tdlib_data"
```

Or use the interactive wizard:

```bash
mix sexy.tdl.setup
```

## 2. Add to supervision tree

```elixir
children = [
  Sexy.TDL
]
```

## 3. Open a session

```elixir
config = %{Sexy.TDL.default_config() |
  api_id: "12345",
  api_hash: "abc123def456",
  database_directory: "/tmp/tdlib_data/my_account"
}

{:ok, _pid} = Sexy.TDL.open("my_account", config, app_pid: self())
```

## 4. Handle events

All TDLib events arrive as messages to the `app_pid` process:

```elixir
defmodule MyApp.TDLWorker do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def init(opts) do
    config = %{Sexy.TDL.default_config() |
      api_id: opts[:api_id],
      api_hash: opts[:api_hash],
      database_directory: "/tmp/tdlib_data/my_account"
    }

    {:ok, _} = Sexy.TDL.open("my_account", config, app_pid: self())
    {:ok, %{}}
  end

  # TDLib authorization flow
  def handle_info({:recv, %Sexy.TDL.Object.UpdateAuthorizationState{authorization_state: state}}, s) do
    handle_auth(state, s)
  end

  # New incoming message
  def handle_info({:recv, %Sexy.TDL.Object.UpdateNewMessage{message: msg}}, state) do
    IO.puts("New message in chat #{msg.chat_id}")
    {:noreply, state}
  end

  # All other TDLib events
  def handle_info({:recv, _other}, state), do: {:noreply, state}

  # System events
  def handle_info({:system_event, type, details}, state) do
    IO.puts("System event: #{type} — #{inspect(details)}")
    {:noreply, state}
  end

  defp handle_auth(%Sexy.TDL.Object.AuthorizationStateWaitPhoneNumber{}, state) do
    Sexy.TDL.transmit("my_account", %Sexy.TDL.Method.SetAuthenticationPhoneNumber{
      phone_number: "+1234567890"
    })
    {:noreply, state}
  end

  defp handle_auth(_state, s), do: {:noreply, s}
end
```

## 5. Send commands

```elixir
# Get current user info
Sexy.TDL.transmit("my_account", %Sexy.TDL.Method.GetMe{})

# Send a message
Sexy.TDL.transmit("my_account", %Sexy.TDL.Method.SendMessage{
  chat_id: 123456,
  input_message_content: %Sexy.TDL.Object.InputMessageText{
    text: %Sexy.TDL.Object.FormattedText{text: "Hello from Elixir!"}
  }
})

# Or use a plain map
Sexy.TDL.transmit("my_account", %{
  "@type" => "sendMessage",
  "chat_id" => 123456,
  "input_message_content" => %{
    "@type" => "inputMessageText",
    "text" => %{"@type" => "formattedText", "text" => "Hello!"}
  }
})
```

## 6. Close session

```elixir
Sexy.TDL.close("my_account")
```

## Auto-generated types

Sexy ships 2558 structs matching the TDLib API:

- `Sexy.TDL.Method.*` — 786 methods (GetMe, SendMessage, GetChat, ...)
- `Sexy.TDL.Object.*` — 1772 types (UpdateNewMessage, User, Chat, Message, ...)

Each struct has `@moduledoc` with field descriptions and a link to the official
Telegram documentation.

To regenerate from a newer TDLib version:

```bash
mix sexy.tdl.generate_types /path/to/types.json
```

## Proxy support

Open a session with proxy:

```elixir
Sexy.TDL.open("my_account", config, app_pid: self(), proxy: true)
```

This requires a `proxy.conf` file at `<tdlib_data_root>/my_account/proxy.conf`
(proxychains4 format).

## Running alongside Bot API

Both engines can coexist in the same supervision tree:

```elixir
children = [
  Sexy.TDL,
  {Sexy.Bot, token: "BOT_TOKEN", session: MyApp.Session}
]
```
