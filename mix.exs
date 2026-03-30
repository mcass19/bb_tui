defmodule BB.TUI.MixProject do
  use Mix.Project

  @description "Terminal-based dashboard for Beam Bots robots"
  @source_url "https://github.com/beam-bots/bb_tui"
  @changelog_url @source_url <> "/blob/main/CHANGELOG.md"
  @version "0.1.0"

  def project do
    [
      app: :bb_tui,
      description: @description,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [
        threshold: 100,
        ignore_modules: [
          BB.TUI,
          Mix.Tasks.Bb.Tui,
          BB.TUI.TestRobot,
          BB.TUI.Test.Fixtures,
          Dev.Application,
          Dev.TestRobot
        ]
      ],
      package: package(),
      name: "BB.TUI",
      homepage_url: @source_url,
      source_url: @source_url,
      docs: docs(),
      dialyzer: [
        plt_local_path: "plts",
        plt_core_path: "plts/core",
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application, do: application(Mix.env())

  def application(:dev) do
    [
      extra_applications: [:logger],
      mod: {Dev.Application, []}
    ]
  end

  def application(_) do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_ratatui, "~> 0.5"},
      {:bb, "~> 0.15"},

      # Test
      {:mimic, "~> 2.2", only: :test},

      # Dev
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @changelog_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      keywords: ["beam-bots", "bb", "tui", "terminal", "dashboard", "robotics", "ratatui"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_modules: [
        Core: [
          BB.TUI,
          BB.TUI.App,
          BB.TUI.State
        ],
        Panels: [
          BB.TUI.Panels.Safety,
          BB.TUI.Panels.Runtime,
          BB.TUI.Panels.Joints,
          BB.TUI.Panels.Events,
          BB.TUI.Panels.Commands,
          BB.TUI.Panels.StatusBar,
          BB.TUI.Panels.Help,
          BB.TUI.Panels.ForceDisarm
        ],
        Styling: [
          BB.TUI.Theme
        ],
        "Mix Tasks": [
          Mix.Tasks.Bb.Tui
        ]
      ]
    ]
  end
end
