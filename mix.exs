defmodule BB.TUI.MixProject do
  use Mix.Project

  @description "Terminal-based dashboard for Beam Bots robots"
  @source_url "https://github.com/mcass19/bb_tui"
  @changelog_url @source_url <> "/blob/main/CHANGELOG.md"
  @version "0.2.0"

  def project do
    [
      app: :bb_tui,
      description: @description,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [
        summary: [threshold: 100],
        ignore_modules: [
          # fixtures - exercised by tests.
          BB.TUI.TestRobot,
          BB.TUI.Test.Fixtures
        ]
      ],
      dialyzer: [
        plt_local_path: "plts",
        plt_core_path: "plts/core",
        plt_add_apps: [:mix]
      ],
      package: package(),
      name: "BB.TUI",
      homepage_url: @source_url,
      source_url: @source_url,
      docs: docs()
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
      {:ex_ratatui, "~> 0.11"},
      {:bb, "~> 0.20"},

      # Test
      {:mimic, "~> 2.2", only: :test},

      # Dev
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:igniter, "~> 0.8", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @changelog_url,
        "Beam Bots" => "https://github.com/beam-bots"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md CONTRIBUTING.md),
      keywords: [
        "beam_bots",
        "robotics",
        "tui",
        "terminal",
        "dashboard",
        "ratatui",
        "ssh",
        "distributed",
        "nerves"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "guides/transports.md": [title: "Transports"],
        "guides/keybindings.md": [title: "Keybindings"],
        "guides/telemetry.md": [title: "Telemetry"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ],
      groups_for_modules: [
        Core: [
          BB.TUI,
          BB.TUI.App
        ],
        State: [
          BB.TUI.State,
          BB.TUI.State.Commands,
          BB.TUI.State.Parameters,
          BB.TUI.State.UI,
          BB.TUI.State.Events,
          BB.TUI.State.Joints,
          BB.TUI.State.Safety,
          BB.TUI.State.Power,
          BB.TUI.State.Viz,
          BB.TUI.State.Throttle
        ],
        Rendering: [
          BB.TUI.Panels.Safety,
          BB.TUI.Panels.Commands,
          BB.TUI.Panels.CommandEdit,
          BB.TUI.Panels.Joints,
          BB.TUI.Panels.Events,
          BB.TUI.Panels.EventDetail,
          BB.TUI.Panels.Parameters,
          BB.TUI.Panels.StatusBar,
          BB.TUI.Panels.TitleBar,
          BB.TUI.Panels.TabBar,
          BB.TUI.Panels.Help,
          BB.TUI.Panels.ForceDisarm,
          BB.TUI.Theme
        ],
        Visualization: [
          BB.TUI.Panels.Visualization,
          BB.TUI.Viz.RobotScene
        ],
        Robot: [
          BB.TUI.Robot,
          BB.TUI.Rpc
        ],
        "Mix Tasks": [
          Mix.Tasks.Bb.Tui,
          Mix.Tasks.BbTui.Install
        ],
        Development: [
          Dev.Application,
          Dev.TestRobot,
          Dev.MockBridge,
          Dev.MoveHandler,
          Dev.StreamHandler,
          Dev.EchoHandler,
          Dev.CalibrateHandler,
          Dev.WobbleHandler,
          Dev.DiagnosticsHandler,
          Dev.PowerHandler
        ]
      ]
    ]
  end
end
