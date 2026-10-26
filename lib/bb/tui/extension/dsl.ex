defmodule BB.TUI.Extension.Dsl do
  @moduledoc """
  The Spark DSL behind `BB.TUI.Extension`: the `drive`, `panels`, `keys`
  and `hints` sections. See `BB.TUI.Extension` for how they fit together.
  """

  alias BB.TUI.Extension
  alias BB.TUI.Extension.Source

  @mfa {:tuple, [:atom, :atom]}
  @scale {:or, [:number, {:struct, Source}]}

  @drive %Spark.Dsl.Section{
    name: :drive,
    describe: """
    Hold-to-drive. The arrow keys set a throttle (up/down) and a turn
    (left/right) of -1, 0 or 1, scaled by `throttle_scale` and
    `turn_scale`; while one is held, bb_tui calls `publish` at `rate` Hz,
    and calls `stop` when it is let go.
    """,
    imports: [Source],
    examples: [
      """
      drive do
        publish {MyKit.Drive, :command}
        stop {MyKit.Drive, :stop}
        turn_scale param([:yaw, :turn_rate])
      end
      """
    ],
    schema: [
      publish: [
        type: @mfa,
        doc: "`{module, function}` called as `function(robot, throttle, turn)` on every tick."
      ],
      stop: [
        type: @mfa,
        doc: "`{module, function}` called as `function(robot)` when driving stops."
      ],
      throttle_scale: [
        type: @scale,
        default: 1.0,
        doc: "Multiplies the throttle: a number, or a `param(path)` read when driving starts."
      ],
      turn_scale: [
        type: @scale,
        default: 1.0,
        doc: "Multiplies the turn: a number, or a `param(path)` read when driving starts."
      ],
      rate: [
        type: :pos_integer,
        default: 20,
        doc: "Ticks per second while a drive key is held."
      ]
    ]
  }

  @readout %Spark.Dsl.Entity{
    name: :readout,
    target: Extension.Readout,
    args: [:label, :source],
    describe: "A labelled value read from a source.",
    examples: [~s{readout "lean", joint(:lean), unit: :degree, decimals: 1}],
    schema: [
      label: [type: :string, required: true, doc: "Text shown before the value."],
      source: [type: {:struct, Source}, required: true, doc: "Where the value comes from."],
      unit: [
        type: {:custom, BB.TUI.Extension.Format, :validate_unit, []},
        doc: "Unit to show the value in, e.g. `:degree` for a radian joint."
      ],
      scale: [type: :number, doc: "Multiplies the value before it is shown."],
      decimals: [type: :non_neg_integer, doc: "Decimal places to round to."],
      spark: [type: :boolean, default: false, doc: "Draw a sparkline of recent values."]
    ]
  }

  @plot %Spark.Dsl.Entity{
    name: :plot,
    target: Extension.Plot,
    args: [:label, :sources],
    describe: "A live chart with one line per source.",
    examples: [~s{plot "lean vs target", [joint(:lean), controller(:balancer, :target)]}],
    schema: [
      label: [type: :string, required: true, doc: "The chart's title."],
      sources: [
        type: {:list, {:struct, Source}},
        required: true,
        doc: "One line per source."
      ],
      window: [
        type: :pos_integer,
        default: 10_000,
        doc: "How much history the chart shows, in milliseconds."
      ],
      y_range: [
        type: {:tuple, [:number, :number]},
        doc: "A fixed `{min, max}` for the y axis; follows the data when unset."
      ]
    ]
  }

  @panel %Spark.Dsl.Entity{
    name: :panel,
    target: Extension.Panel,
    args: [:name],
    identifier: :name,
    entities: [items: [@readout, @plot]],
    describe: "A titled box of readouts and plots, in the order declared.",
    examples: [
      """
      panel :balance do
        title "Balance"
        readout "lean", joint(:lean), unit: :degree
        plot "lean", [joint(:lean)]
      end
      """
    ],
    schema: [
      name: [type: :atom, required: true, doc: "Identifies the panel; also its tab's name."],
      title: [type: :string, doc: "Shown on the panel's border. Defaults to the name."],
      tab: [
        type: :atom,
        doc: "`:drive` to sit beside the drive pad; another atom to share a tab."
      ]
    ]
  }

  @panels %Spark.Dsl.Section{
    name: :panels,
    describe:
      "Panels of readouts and plots, each on a tab of its own unless `tab` says otherwise.",
    imports: [Source],
    entities: [@panel]
  }

  @bind %Spark.Dsl.Entity{
    name: :bind,
    target: Extension.Bind,
    args: [:key],
    identifier: :key,
    describe: "Runs a robot command when `key` is pressed.",
    examples: [~s{bind "s", command: :stand, label: "stand"}],
    schema: [
      key: [type: :string, required: true, doc: "The key, as `ExRatatui.Event.Key` names it."],
      command: [type: :atom, required: true, doc: "The robot command to run."],
      label: [type: :string, doc: "Shown in the help popup and status bar."]
    ]
  }

  @keys %Spark.Dsl.Section{
    name: :keys,
    describe: "Keys bound to robot commands. bb_tui's own keys can't be rebound.",
    entities: [@bind]
  }

  @hint %Spark.Dsl.Entity{
    name: :state,
    target: Extension.Hint,
    args: [:state, :text],
    identifier: :state,
    describe: "The banner shown while the robot is in `state`.",
    examples: [~s{state :idle, "hold it upright, then s to stand"}],
    schema: [
      state: [type: :atom, required: true, doc: "A robot runtime state."],
      text: [type: :string, required: true, doc: "The banner text."]
    ]
  }

  @hints %Spark.Dsl.Section{
    name: :hints,
    describe: "Per-state banner text shown under the title bar.",
    entities: [@hint]
  }

  use Spark.Dsl.Extension,
    sections: [@drive, @panels, @keys, @hints],
    verifiers: [
      Extension.Verifiers.Drive,
      Extension.Verifiers.Keys
    ]
end
