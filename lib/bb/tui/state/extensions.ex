defmodule BB.TUI.State.Extensions do
  @moduledoc """
  The session's `BB.TUI.Extension`s, merged, split out of `BB.TUI.State`.

  Built once when `BB.TUI.App` starts, from the `:extensions` option:
  `panels` and `binds` keep the order the extensions and their
  declarations came in, `hints` maps a runtime state to its banner, and
  `drive` holds the one extension allowed to declare driving.

  `topics` and `controllers` are what the sources read: the topic paths
  whose latest payload is kept, and the controllers whose `:inspect` state
  is polled. `values` holds those, keyed `{:topic, path}` and
  `{:controller, name}`; `polling` is the controllers with a poll in flight.
  Joints and parameters are read from the rest of the session state, see
  `read/2`.
  """

  alias BB.TUI.Extension
  alias BB.TUI.Extension.Info
  alias BB.TUI.Extension.Panel
  alias BB.TUI.Extension.Source

  defstruct modules: [],
            panels: [],
            binds: [],
            hints: %{},
            drive: nil,
            topics: [],
            controllers: [],
            values: %{},
            polling: MapSet.new()

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
          hints: %{atom() => String.t()},
          drive: drive() | nil,
          topics: [[atom()]],
          controllers: [atom()],
          values: %{({:topic, [atom()]} | {:controller, atom()}) => term()},
          polling: MapSet.t(atom())
        }

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
        hints: Map.new(Enum.flat_map(modules, &Info.hints/1), &{&1.state, &1.text}),
        drive: drive
      }

      sources = sources(extensions)

      {:ok,
       %{
         extensions
         | topics: Source.subscribe_paths(sources),
           controllers:
             for(%Source{type: :controller, target: name} <- sources, uniq: true, do: name)
       }}
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
  The controllers to poll now: every controller a source reads that has no
  poll in flight. They are marked in flight until `finish_poll/3`.

  ## Examples

      iex> ext = %BB.TUI.State.Extensions{controllers: [:balancer, :yaw]}
      iex> {[:balancer, :yaw], ext} = BB.TUI.State.Extensions.start_polls(ext)
      iex> {[], _ext} = BB.TUI.State.Extensions.start_polls(ext)
  """
  @spec start_polls(t()) :: {[atom()], t()}
  def start_polls(%__MODULE__{controllers: controllers, polling: polling} = extensions) do
    due = Enum.reject(controllers, &MapSet.member?(polling, &1))
    {due, %{extensions | polling: MapSet.union(polling, MapSet.new(due))}}
  end

  @doc """
  Records a controller's answer to `:inspect` and frees its poll: the state
  it returned, or — when it couldn't answer — no value at all, so its
  readouts show as missing rather than stale.

  ## Examples

      iex> {_due, ext} = BB.TUI.State.Extensions.start_polls(%BB.TUI.State.Extensions{controllers: [:yaw]})
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
  defp dig(%{} = map, [key | rest]), do: dig(Map.get(map, key), rest)
  defp dig(_value, _path), do: nil
end
