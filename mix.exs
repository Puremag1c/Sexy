defmodule Sexy.MixProject do
  use Mix.Project

  @version "0.9.4"
  @source_url "https://github.com/Puremag1c/Sexy"

  def project do
    [
      app: :sexy,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Sexy",
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    "Telegram framework for Elixir — Bot API with single-message UI pattern and TDLib userbot integration in one dependency."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"],
        "guides/bot-quickstart.md": [title: "Bot Quick Start"],
        "guides/tdl-quickstart.md": [title: "TDLib Quick Start"]
      ],
      filter_modules: fn module, _meta ->
        name = inspect(module)

        not String.starts_with?(name, "Sexy.TDL.Object.") and
          not String.starts_with?(name, "Sexy.TDL.Method.")
      end,
      groups_for_modules: [
        "Bot API": [
          Sexy.Bot,
          Sexy.Bot.Api,
          Sexy.Bot.Sender,
          Sexy.Bot.Screen,
          Sexy.Bot.Session,
          Sexy.Bot.Notification,
          Sexy.Bot.Poller
        ],
        TDLib: [
          Sexy.TDL,
          Sexy.TDL.Backend,
          Sexy.TDL.Handler,
          Sexy.TDL.Registry,
          Sexy.TDL.Riser,
          Sexy.TDL.Object,
          Sexy.TDL.Method
        ],
        Utilities: [
          Sexy.Utils,
          Sexy.Utils.Bot,
          Sexy.Utils.Object
        ]
      ],
      source_ref: "v#{@version}"
    ]
  end

  defp deps do
    [
      {:httpoison, "~> 1.8"},
      {:jason, "~> 1.2"},
      {:base62, "~> 1.2"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
