defmodule BB.TUI.State.Extensions do
  @moduledoc """
  The session's `BB.TUI.Extension`s, merged, split out of `BB.TUI.State`.

  Built once when `BB.TUI.App` starts, from the `:extensions` option:
  `panels` and `binds` keep the order the extensions and their
  declarations came in, `hints` maps a runtime state to its banner, and
  `drive` holds the one extension allowed to declare driving.

  `bound` maps each bound key to its bind, for the key handler's guard.

  `topics` and `controllers` are what the sources read: the topic paths
  whose latest payload is kept, and the controllers whose `:inspect` state
  is polled. `values` holds those, keyed `{:topic, path}` and
  `{:controller, name}`; `polling` is the controllers with a poll in flight.
  Joints and parameters are read from the rest of the session state, see
  `read/2`.

  `series` holds the recent history behind each plot line and sparkline,
  keyed `{panel, item_index, source_index}`; `series_sources` indexes them
  by the source that feeds them, with the readout settings that turn its
  value into a number. While `frozen_at` is set the charts stop at that
  moment and nothing is recorded, so a fall stays on screen.
  """

  alias BB.Math.Quaternion
  alias BB.Math.Transform
  alias BB.TUI.Extension
  alias BB.TUI.Extension.Format
  alias BB.TUI.Extension.Info
  alias BB.TUI.Extension.Panel
  alias BB.TUI.Extension.Source
  alias BB.TUI.State.Series

  defstruct modules: [],
            panels: [],
            binds: [],
            bound: %{},
            hints: %{},
            drive: nil,
            topics: [],
            controllers: [],
            values: %{},
            polling: MapSet.new(),
            series: %{},
            series_sources: %{},
            frozen_at: nil

  @type drive :: %{
          extension: module(),
          publish: {module(), atom()},
          stop: {module(), atom()},
          throttle_scale: number() | Source.t(),
          turn_scale: number() | Source.t(),
          rate: pos_integer()
        }

  @type t :: %__MODULE__{
          modules: [module()],
          panels: [Panel.t()],
          binds: [Extension.Bind.t()],
          bound: %{String.t() => Extension.Bind.t()},
          hints: %{atom() => String.t()},
          drive: drive() | nil,
          topics: [[atom()]],
          controllers: [atom()],
          values: %{({:topic, [atom()]} | {:controller, atom()}) => term()},
          polling: MapSet.t(atom()),
          series: %{series_key() => Series.t()},
          series_sources: %{Source.t() => [{series_key(), Extension.Readout.t()}]},
          frozen_at: integer() | nil
        }

  @type series_key :: {atom(), non_neg_integer(), non_neg_integer()}

  # A sparkline shows the last 10 s of its readout.
  @spark_window 10_000

  @doc """
  Merges `modules` into one set of extensions.

  Fails when a module isn't a `BB.TUI.Extension`, when more than one
  declares a drive, or when two bind the same key or name the same panel.
  A later extension's hint for a state replaces an earlier one's.

  ## Examples

      iex> {:ok, extensions} = BB.TUI.State.Extensions.build([])
      iex> extensions.panels
      []

      iex> BB.TUI.State.Extensions.build([Enum])
      {:error, "Enum is not a BB.TUI.Extension"}
  """
  @spec build([module()]) :: {:ok, t()} | {:error, String.t()}
  def build(modules) when is_list(modules) do
    with :ok <- all_extensions(modules),
         {:ok, drive} <- one_drive(modules),
         panels = Enum.flat_map(modules, &Info.panels/1),
         binds = Enum.flat_map(modules, &Info.keys/1),
         :ok <- unique(panels, & &1.name, "panel"),
         :ok <- unique(binds, & &1.key, "bound key") do
      extensions = %__MODULE__{
        modules: modules,
        panels: panels,
        binds: binds,
        bound: Map.new(binds, &{&1.key, &1}),
        hints: Map.new(Enum.flat_map(modules, &Info.hints/1), &{&1.state, &1.text}),
        drive: drive
      }

      sources = sources(extensions)

      {:ok,
       reindex(%{
         extensions
         | topics: Source.subscribe_paths(sources),
           controllers:
             for(%Source{type: :controller, target: name} <- sources, uniq: true, do: name)
       })}
    end
  end

  defp all_extensions(modules) do
    case Enum.reject(modules, &Extension.extension?/1) do
      [] -> :ok
      [module | _] -> {:error, "#{inspect(module)} is not a BB.TUI.Extension"}
    end
  end

  defp one_drive(modules) do
    case Enum.filter(modules, &Info.drive?/1) do
      [] -> {:ok, nil}
      [module] -> {:ok, drive(module)}
      many -> {:error, "only one extension can declare a drive, got: #{inspect(many)}"}
    end
  end

  defp drive(module) do
    %{
      extension: module,
      publish: Info.drive_publish!(module),
      stop: Info.drive_stop!(module),
      # Read untyped: Spark's generated spec for these options says
      # `:number | tuple()`, which hides the `Source` structs from dialyzer.
      throttle_scale: Spark.Dsl.Extension.get_opt(module, [:drive], :throttle_scale, 1.0),
      turn_scale: Spark.Dsl.Extension.get_opt(module, [:drive], :turn_scale, 1.0),
      rate: Info.drive_rate!(module)
    }
  end

  defp unique(entities, key, what) do
    entities
    |> Enum.frequencies_by(key)
    |> Enum.find(fn {_value, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {value, _count} ->
        {:error, "#{what} #{inspect(value)} is declared by more than one extension"}
    end
  end

  @doc """
  Every source the extensions read: their readouts and plots, and the
  drive's scales when those come from parameters.

  ## Examples

      iex> BB.TUI.State.Extensions.sources(%BB.TUI.State.Extensions{})
      []
  """
  @spec sources(t()) :: [Source.t()]
  def sources(%__MODULE__{panels: panels, drive: drive}) do
    item_sources =
      for %Panel{items: items} <- panels,
          item <- items,
          source <- item_sources(item),
          do: source

    Enum.uniq(item_sources ++ drive_sources(drive))
  end

  defp item_sources(%Extension.Readout{source: source}), do: [source]
  defp item_sources(%Extension.Plot{sources: sources}), do: sources

  defp item_sources(%Extension.Attitude{pitch: pitch, roll: roll}),
    do: for(%Source{} = source <- [pitch, roll], do: source)

  defp drive_sources(nil), do: []

  defp drive_sources(drive),
    do: for(%Source{} = scale <- [drive.throttle_scale, drive.turn_scale], do: scale)

  @doc """
  The topic paths the extensions read that `subscribed` doesn't already
  cover. A subscription to a path receives everything under it, so a path
  with a subscribed prefix needs no subscription of its own — subscribing
  again would deliver its messages twice.

  ## Examples

      iex> alias BB.TUI.Extension.Source
      iex> extensions = %BB.TUI.State.Extensions{
      ...>   panels: [%BB.TUI.Extension.Panel{name: :p, items: [
      ...>     %BB.TUI.Extension.Readout{label: "v", source: Source.topic([:sensor, :wheel], :v)},
      ...>     %BB.TUI.Extension.Readout{label: "d", source: Source.topic([:drive], :vx)}
      ...>   ]}]
      ...> }
      iex> BB.TUI.State.Extensions.subscribe_paths(extensions, [[:sensor], [:command]])
      [[:drive]]
      iex> BB.TUI.State.Extensions.subscribe_paths(extensions, [])
      [[:drive], [:sensor, :wheel]]
  """
  @spec subscribe_paths(t(), [[atom()]]) :: [[atom()]]
  def subscribe_paths(%__MODULE__{} = extensions, subscribed) do
    extensions
    |> sources()
    |> Source.subscribe_paths()
    |> Enum.sort_by(&length/1)
    |> Enum.reduce([], fn path, kept ->
      if Enum.any?(subscribed ++ kept, &List.starts_with?(path, &1)),
        do: kept,
        else: kept ++ [path]
    end)
  end

  @doc """
  The extensions' tabs, in the order their panels were declared, as
  `{name, label}`. A panel's tab is its `tab`, or its own name; a tab
  holding one panel of the same name is labelled with that panel's title.

  ## Examples

      iex> alias BB.TUI.Extension.Panel
      iex> ext = %BB.TUI.State.Extensions{panels: [
      ...>   %Panel{name: :balance, title: "Balance", tab: :drive},
      ...>   %Panel{name: :yaw_rate},
      ...>   %Panel{name: :wheels, tab: :hardware},
      ...>   %Panel{name: :power, tab: :hardware}
      ...> ]}
      iex> BB.TUI.State.Extensions.tabs(ext)
      [drive: "Drive", yaw_rate: "Yaw rate", hardware: "Hardware"]
  """
  @spec tabs(t()) :: [{atom(), String.t()}]
  def tabs(%__MODULE__{panels: panels} = extensions) do
    tabs =
      panels
      |> Enum.group_by(&tab_of/1)
      |> then(fn by_tab ->
        for tab <- panels |> Enum.map(&tab_of/1) |> Enum.uniq(),
            do: {tab, tab_label(tab, Map.fetch!(by_tab, tab))}
      end)

    # A declared drive gets its tab even with no panels on it.
    if extensions.drive && not List.keymember?(tabs, :drive, 0),
      do: [{:drive, "Drive"} | tabs],
      else: tabs
  end

  @doc """
  The panels on tab `tab`, in declaration order.

  ## Examples

      iex> alias BB.TUI.Extension.Panel
      iex> ext = %BB.TUI.State.Extensions{panels: [%Panel{name: :a, tab: :t}, %Panel{name: :b}, %Panel{name: :c, tab: :t}]}
      iex> ext |> BB.TUI.State.Extensions.panels_on(:t) |> Enum.map(& &1.name)
      [:a, :c]
  """
  @spec panels_on(t(), atom()) :: [Panel.t()]
  def panels_on(%__MODULE__{panels: panels}, tab), do: Enum.filter(panels, &(tab_of(&1) == tab))

  defp tab_of(%Panel{tab: nil, name: name}), do: name
  defp tab_of(%Panel{tab: tab}), do: tab

  defp tab_label(:drive, _panels), do: "Drive"
  defp tab_label(name, [%Panel{name: name} = panel]), do: panel_title(panel)
  defp tab_label(name, _panels), do: humanize(name)

  @doc """
  A panel's title: its `title`, or its name made readable.

  ## Examples

      iex> BB.TUI.State.Extensions.panel_title(%BB.TUI.Extension.Panel{name: :yaw_rate})
      "Yaw rate"
      iex> BB.TUI.State.Extensions.panel_title(%BB.TUI.Extension.Panel{name: :yaw, title: "Heading"})
      "Heading"
  """
  @spec panel_title(Panel.t()) :: String.t()
  def panel_title(%Panel{title: title}) when is_binary(title), do: title
  def panel_title(%Panel{name: name}), do: humanize(name)

  defp humanize(name),
    do: name |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  @doc """
  Whether tab `tab` shows any chart.

  ## Examples

      iex> alias BB.TUI.Extension.{Panel, Plot}
      iex> ext = %BB.TUI.State.Extensions{panels: [%Panel{name: :a, items: [%Plot{label: "x"}]}, %Panel{name: :b}]}
      iex> {BB.TUI.State.Extensions.plots_on?(ext, :a), BB.TUI.State.Extensions.plots_on?(ext, :b)}
      {true, false}
  """
  @spec plots_on?(t(), atom()) :: boolean()
  def plots_on?(%__MODULE__{} = extensions, tab) do
    extensions
    |> panels_on(tab)
    |> Enum.any?(fn panel -> Enum.any?(panel.items, &match?(%Extension.Plot{}, &1)) end)
  end

  @doc """
  The hint for the robot's runtime state, or `nil` when no extension has one.

  ## Examples

      iex> ext = %BB.TUI.State.Extensions{hints: %{idle: "s to stand"}}
      iex> BB.TUI.State.Extensions.hint(ext, :idle)
      "s to stand"
      iex> BB.TUI.State.Extensions.hint(ext, :armed)
      nil
  """
  @spec hint(t(), atom()) :: String.t() | nil
  def hint(%__MODULE__{hints: hints}, runtime_state), do: Map.get(hints, runtime_state)

  @doc """
  The controllers read by the panels on tab `tab` — the ones worth polling
  while it is on screen.

  ## Examples

      iex> alias BB.TUI.Extension.{Panel, Readout, Source}
      iex> ext = %BB.TUI.State.Extensions{panels: [
      ...>   %Panel{name: :a, items: [%Readout{source: Source.controller(:balancer, :lean)}]},
      ...>   %Panel{name: :b, items: [%Readout{source: Source.controller(:yaw, :heading)}]}
      ...> ]}
      iex> BB.TUI.State.Extensions.controllers_on(ext, :b)
      [:yaw]
  """
  @spec controllers_on(t(), atom()) :: [atom()]
  def controllers_on(%__MODULE__{} = extensions, tab) do
    for panel <- panels_on(extensions, tab),
        item <- panel.items,
        %Source{type: :controller, target: name} <- item_sources(item),
        uniq: true,
        do: name
  end

  @doc """
  Keeps `payload` for every topic source whose path `path` matches.

  A source path matches a message published on it, and — since bb publishes
  sensors and actuators under their full topology path — a two-segment
  `[root, name]` also matches any path that starts with `root` and ends with
  `name`, the way the event log names them.

  ## Examples

      iex> ext = %BB.TUI.State.Extensions{topics: [[:sensor, :imu], [:drive]]}
      iex> ext = BB.TUI.State.Extensions.put_message(ext, [:sensor, :base, :chassis, :imu], %{x: 1})
      iex> ext = BB.TUI.State.Extensions.put_message(ext, [:command, :stand], %{})
      iex> ext.values
      %{{:topic, [:sensor, :imu]} => %{x: 1}}
  """
  @spec put_message(t(), [term()], term()) :: t()
  def put_message(%__MODULE__{topics: []} = extensions, _path, _payload), do: extensions

  def put_message(%__MODULE__{topics: topics} = extensions, path, payload) do
    values =
      for topic <- topics, topic_matches?(topic, path), reduce: extensions.values do
        values -> Map.put(values, {:topic, topic}, payload)
      end

    %{extensions | values: values}
  end

  defp topic_matches?(path, path), do: true

  defp topic_matches?([root, name], [root | [_ | _] = rest]), do: List.last(rest) == name

  defp topic_matches?(_topic, _path), do: false

  @doc """
  The controllers to poll now: those of `controllers` with no poll in
  flight. They are marked in flight until `finish_poll/3`.

  ## Examples

      iex> ext = %BB.TUI.State.Extensions{}
      iex> {[:balancer, :yaw], ext} = BB.TUI.State.Extensions.start_polls(ext, [:balancer, :yaw])
      iex> {[], _ext} = BB.TUI.State.Extensions.start_polls(ext, [:balancer, :yaw])
  """
  @spec start_polls(t(), [atom()]) :: {[atom()], t()}
  def start_polls(%__MODULE__{polling: polling} = extensions, controllers) do
    due = Enum.reject(controllers, &MapSet.member?(polling, &1))
    {due, %{extensions | polling: MapSet.union(polling, MapSet.new(due))}}
  end

  @doc """
  Records a controller's answer to `:inspect` and frees its poll: the state
  it returned, or — when it couldn't answer — no value at all, so its
  readouts show as missing rather than stale.

  ## Examples

      iex> {_due, ext} = BB.TUI.State.Extensions.start_polls(%BB.TUI.State.Extensions{}, [:yaw])
      iex> ext = BB.TUI.State.Extensions.finish_poll(ext, :yaw, {:ok, %{heading: 0.5}})
      iex> {ext.values, MapSet.to_list(ext.polling)}
      {%{{:controller, :yaw} => %{heading: 0.5}}, []}
      iex> BB.TUI.State.Extensions.finish_poll(ext, :yaw, {:error, :noproc}).values
      %{}
  """
  @spec finish_poll(t(), atom(), {:ok, term()} | {:error, term()}) :: t()
  def finish_poll(%__MODULE__{} = extensions, name, result) do
    values =
      case result do
        {:ok, state} -> Map.put(extensions.values, {:controller, name}, state)
        {:error, _reason} -> Map.delete(extensions.values, {:controller, name})
      end

    %{extensions | values: values, polling: MapSet.delete(extensions.polling, name)}
  end

  @doc """
  The current value of `source` in the session `state`, or `nil` when there
  is none yet: a joint's position, a parameter's value, or the field the
  source names in a topic's latest payload or a controller's state.

  On the way, an orientation (`BB.Math.Quaternion`, an `Imu`'s
  `:orientation`) also answers `:roll`, `:pitch` and `:yaw` in radians
  (Z-Y-X, as in aviation), and a pose (`BB.Math.Transform`, an `Odometry`'s
  `:pose`) answers those and its translation's `:x`, `:y` and `:z`.

  ## Examples

      iex> alias BB.TUI.Extension.Source
      iex> state = %BB.TUI.State{
      ...>   joints: %BB.TUI.State.Joints{entries: %{lean: %{position: 0.1}}},
      ...>   parameters: %BB.TUI.State.Parameters{list: [{[:yaw, :rate], 2.0}]},
      ...>   extensions: %BB.TUI.State.Extensions{values: %{{:controller, :yaw} => %{gains: %{kp: 3}}}}
      ...> }
      iex> BB.TUI.State.Extensions.read(state, Source.joint(:lean))
      0.1
      iex> BB.TUI.State.Extensions.read(state, Source.param([:yaw, :rate]))
      2.0
      iex> BB.TUI.State.Extensions.read(state, Source.controller(:yaw, [:gains, :kp]))
      3
      iex> BB.TUI.State.Extensions.read(state, Source.topic([:drive], :vx))
      nil

      iex> alias BB.TUI.Extension.Source
      iex> pose = BB.Math.Transform.from_position_quaternion(
      ...>   BB.Math.Vec3.new(1.0, 2.0, 0.0),
      ...>   BB.Math.Quaternion.from_axis_angle(BB.Math.Vec3.unit_z(), 0.5)
      ...> )
      iex> state = %BB.TUI.State{
      ...>   extensions: %BB.TUI.State.Extensions{values: %{{:topic, [:odom]} => %{pose: pose}}}
      ...> }
      iex> BB.TUI.State.Extensions.read(state, Source.topic([:odom], [:pose, :x]))
      1.0
      iex> BB.TUI.State.Extensions.read(state, Source.topic([:odom], [:pose, :yaw])) |> Float.round(6)
      0.5
  """
  @spec read(map(), Source.t()) :: term()
  def read(state, %Source{type: :joint, target: name}) do
    case state.joints.entries do
      %{^name => %{position: position}} -> position
      _ -> nil
    end
  end

  def read(state, %Source{type: :param, target: path}) do
    Enum.find_value(state.parameters.list, fn
      {^path, value} -> value
      _ -> nil
    end)
  end

  def read(state, %Source{type: :topic, target: path, path: field}),
    do: dig(state.extensions.values[{:topic, path}], field)

  def read(state, %Source{type: :controller, target: name, path: field}),
    do: dig(state.extensions.values[{:controller, name}], field)

  defp dig(value, []), do: value

  defp dig(%Quaternion{} = orientation, [axis | rest]) when axis in [:roll, :pitch, :yaw] do
    {roll, pitch, yaw} = Quaternion.to_euler(orientation, :zyx)
    dig(%{roll: roll, pitch: pitch, yaw: yaw}[axis], rest)
  end

  defp dig(%Transform{} = pose, [axis | _rest] = path) when axis in [:roll, :pitch, :yaw],
    do: dig(Transform.get_quaternion(pose), path)

  defp dig(%Transform{} = pose, [axis | _rest] = path) when axis in [:x, :y, :z],
    do: dig(Transform.get_translation(pose), path)

  defp dig(%{} = map, [key | rest]), do: dig(Map.get(map, key), rest)
  defp dig(_value, _path), do: nil

  @doc """
  Rebuilds the series and their index from `panels`: one series per plot
  line, with the plot's unit and scale, and one per readout drawn with a
  sparkline. `build/1` does this; it is public for code that assembles
  panels by hand.
  """
  @spec reindex(t()) :: t()
  def reindex(%__MODULE__{panels: panels} = extensions) do
    plotted =
      for %Panel{name: name, items: items} <- panels,
          {item, index} <- Enum.with_index(items),
          entry <- plotted_item(name, index, item),
          do: entry

    %{
      extensions
      | series: Map.new(plotted, fn {key, _readout, window} -> {key, Series.new(window)} end),
        series_sources:
          Enum.group_by(plotted, fn {_key, readout, _window} -> readout.source end, fn
            {key, readout, _window} -> {key, readout}
          end)
    }
  end

  defp plotted_item(panel, index, %Extension.Plot{} = plot) do
    for {source, line} <- Enum.with_index(plot.sources) do
      readout = %Extension.Readout{
        label: plot.label,
        source: source,
        unit: plot.unit,
        scale: plot.scale
      }

      {{panel, index, line}, readout, plot.window}
    end
  end

  defp plotted_item(panel, index, %Extension.Readout{spark: true} = readout),
    do: [{{panel, index, 0}, readout, @spark_window}]

  defp plotted_item(_panel, _index, _readout), do: []

  @doc """
  The topic paths among `topics` that `path` matches (see `put_message/3`).

  ## Examples

      iex> ext = %BB.TUI.State.Extensions{topics: [[:sensor, :imu], [:drive]]}
      iex> BB.TUI.State.Extensions.matching_topics(ext, [:sensor, :base, :imu])
      [[:sensor, :imu]]
  """
  @spec matching_topics(t(), [term()]) :: [[atom()]]
  def matching_topics(%__MODULE__{topics: topics}, path),
    do: Enum.filter(topics, &topic_matches?(&1, path))

  @doc """
  Records, at `now`, a sample of every plotted source `filter` selects, read
  from the session `state` as it is now. Each series converts the value
  with its own unit and scale; values that aren't numbers, and everything
  while the charts are frozen, are skipped.

  ## Examples

      iex> alias BB.TUI.Extension.{Panel, Plot, Source}
      iex> panel = %Panel{name: :p, items: [%Plot{label: "lean", sources: [Source.joint(:lean)], window: 1_000}]}
      iex> ext = BB.TUI.State.Extensions.reindex(%BB.TUI.State.Extensions{panels: [panel]})
      iex> state = %BB.TUI.State{joints: %BB.TUI.State.Joints{entries: %{lean: %{position: 0.5}}}, extensions: ext}
      iex> state = BB.TUI.State.Extensions.record(state, 100, &(&1.type == :joint))
      iex> state.extensions.series |> Map.fetch!({:p, 0, 0}) |> BB.TUI.State.Series.values()
      [0.5]
  """
  @spec record(map(), integer(), (Source.t() -> boolean())) :: map()
  def record(
        %{extensions: %__MODULE__{frozen_at: nil, series_sources: by_source}} = state,
        now,
        filter
      )
      when map_size(by_source) > 0 do
    series =
      for {source, entries} <- by_source,
          filter.(source),
          value = read(state, source),
          {key, readout} <- entries,
          number = Format.number_value(value, readout),
          is_number(number),
          reduce: state.extensions.series do
        series -> Map.update!(series, key, &Series.push(&1, now, number))
      end

    %{state | extensions: %{state.extensions | series: series}}
  end

  def record(state, _now, _filter), do: state

  @doc """
  The throttle and turn to publish for directions `throttle` and `turn`
  (each -1, 0 or 1), scaled by the drive's `throttle_scale` and
  `turn_scale`. A scale read from a parameter that isn't set, or isn't a
  number, leaves its axis unscaled rather than zeroed.

  ## Examples

      iex> alias BB.TUI.Extension.Source
      iex> drive = %{throttle_scale: 0.5, turn_scale: Source.param([:yaw, :rate])}
      iex> state = %BB.TUI.State{
      ...>   parameters: %BB.TUI.State.Parameters{list: [{[:yaw, :rate], 2.0}]},
      ...>   extensions: %BB.TUI.State.Extensions{drive: drive}
      ...> }
      iex> BB.TUI.State.Extensions.drive_command(state, 1, -1)
      {0.5, -2.0}
  """
  @spec drive_command(map(), -1 | 0 | 1, -1 | 0 | 1) :: {float(), float()}
  def drive_command(%{extensions: %__MODULE__{drive: drive}} = state, throttle, turn) do
    {throttle * scale(state, drive.throttle_scale) * 1.0,
     turn * scale(state, drive.turn_scale) * 1.0}
  end

  defp scale(_state, scale) when is_number(scale), do: scale

  defp scale(state, %Source{} = source) do
    readout = %Extension.Readout{label: "scale", source: source}

    case Format.number_value(read(state, source), readout) do
      nil -> 1.0
      number -> number
    end
  end

  @doc """
  Freezes the charts at `now`, or lets them run again.

  ## Examples

      iex> ext = BB.TUI.State.Extensions.toggle_freeze(%BB.TUI.State.Extensions{}, 500)
      iex> ext.frozen_at
      500
      iex> BB.TUI.State.Extensions.toggle_freeze(ext, 900).frozen_at
      nil
  """
  @spec toggle_freeze(t(), integer()) :: t()
  def toggle_freeze(%__MODULE__{frozen_at: nil} = extensions, now),
    do: %{extensions | frozen_at: now}

  def toggle_freeze(%__MODULE__{} = extensions, _now), do: %{extensions | frozen_at: nil}

  @doc """
  The moment the charts end at: `now`, or when they were frozen.

  ## Examples

      iex> BB.TUI.State.Extensions.chart_time(%BB.TUI.State.Extensions{frozen_at: 5}, 9)
      5
      iex> BB.TUI.State.Extensions.chart_time(%BB.TUI.State.Extensions{}, 9)
      9
  """
  @spec chart_time(t(), integer()) :: integer()
  def chart_time(%__MODULE__{frozen_at: nil}, now), do: now
  def chart_time(%__MODULE__{frozen_at: frozen_at}, _now), do: frozen_at
end
