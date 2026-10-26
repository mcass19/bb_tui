defmodule BB.TUI.State.Extensions do
  @moduledoc """
  The session's `BB.TUI.Extension`s, merged, split out of `BB.TUI.State`.

  Built once when `BB.TUI.App` starts, from the `:extensions` option:
  `panels` and `binds` keep the order the extensions and their
  declarations came in, `hints` maps a runtime state to its banner, and
  `drive` holds the one extension allowed to declare driving. `values`
  holds the latest value of each source the panels read, keyed by source.
  """

  alias BB.TUI.Extension
  alias BB.TUI.Extension.Info
  alias BB.TUI.Extension.Panel
  alias BB.TUI.Extension.Source

  defstruct modules: [], panels: [], binds: [], hints: %{}, drive: nil, values: %{}

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
          values: %{Source.t() => term()}
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
      {:ok,
       %__MODULE__{
         modules: modules,
         panels: panels,
         binds: binds,
         hints: Map.new(Enum.flat_map(modules, &Info.hints/1), &{&1.state, &1.text}),
         drive: drive
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
      throttle_scale: Info.drive_throttle_scale!(module),
      turn_scale: Info.drive_turn_scale!(module),
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
end
