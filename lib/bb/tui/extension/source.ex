defmodule BB.TUI.Extension.Source do
  @moduledoc """
  Where a readout, plot or drive scale gets its value from.

  The constructors below are imported into the `drive` and `panels`
  sections of `BB.TUI.Extension`, so a declaration reads
  `readout "lean", joint(:lean)` rather than building the struct:

    * `joint(name)` — a joint's position, as the joints panel shows it
    * `controller(name, key)` — a field of the state a controller returns
      from `handle_call(:inspect, ...)` (a key, or a path into nested maps)
    * `topic(path, field)` — a field of the latest message published under
      `path` (a key, or a path into the payload)
    * `param(path)` — a robot parameter's current value

  ## Examples

      iex> BB.TUI.Extension.Source.joint(:lean)
      %BB.TUI.Extension.Source{type: :joint, target: :lean, path: []}

      iex> BB.TUI.Extension.Source.controller(:pid_balancer, [:gains, :kp])
      %BB.TUI.Extension.Source{type: :controller, target: :pid_balancer, path: [:gains, :kp]}

      iex> BB.TUI.Extension.Source.topic([:sensor, :imu], :angular_velocity)
      %BB.TUI.Extension.Source{type: :topic, target: [:sensor, :imu], path: [:angular_velocity]}

      iex> BB.TUI.Extension.Source.param([:yaw, :turn_rate])
      %BB.TUI.Extension.Source{type: :param, target: [:yaw, :turn_rate], path: []}
  """

  defstruct [:type, :target, path: []]

  @type type :: :joint | :controller | :topic | :param

  @type t :: %__MODULE__{
          type: type(),
          target: atom() | [atom()],
          path: [atom()]
        }

  @doc "A joint's position."
  @spec joint(atom()) :: t()
  def joint(name) when is_atom(name), do: %__MODULE__{type: :joint, target: name}

  @doc "A field of a controller's `:inspect` state: a key, or a path into nested maps."
  @spec controller(atom(), atom() | [atom()]) :: t()
  def controller(name, key_or_path) when is_atom(name),
    do: %__MODULE__{type: :controller, target: name, path: path!(key_or_path)}

  @doc "A field of the latest message on a topic: a key, or a path into the payload."
  @spec topic([atom()], atom() | [atom()]) :: t()
  def topic(path, key_or_path) when is_list(path),
    do: %__MODULE__{type: :topic, target: atoms!(path), path: path!(key_or_path)}

  @doc "A robot parameter's current value."
  @spec param([atom()]) :: t()
  def param(path) when is_list(path) and path != [],
    do: %__MODULE__{type: :param, target: atoms!(path)}

  @doc """
  A short name for the source, for a chart's legend: the field it reads, or
  the joint's name.

  ## Examples

      iex> alias BB.TUI.Extension.Source
      iex> {Source.name(Source.joint(:lean)), Source.name(Source.controller(:pid, [:gains, :kp]))}
      {"lean", "kp"}
      iex> Source.name(Source.param([:yaw, :turn_rate]))
      "turn_rate"
  """
  @spec name(t()) :: String.t()
  def name(%__MODULE__{type: :joint, target: name}), do: Atom.to_string(name)
  def name(%__MODULE__{type: :param, target: path}), do: path |> List.last() |> Atom.to_string()
  def name(%__MODULE__{path: path}), do: path |> List.last() |> Atom.to_string()

  @doc """
  The topic paths an extension's sources need subscribing to, without
  duplicates.

  ## Examples

      iex> alias BB.TUI.Extension.Source
      iex> Source.subscribe_paths([Source.topic([:sensor, :imu], :x), Source.joint(:lean), Source.topic([:sensor, :imu], :y)])
      [[:sensor, :imu]]
  """
  @spec subscribe_paths([t()]) :: [[atom()]]
  def subscribe_paths(sources) do
    for %__MODULE__{type: :topic, target: path} <- sources, uniq: true, do: path
  end

  defp path!(key) when is_atom(key), do: [key]
  defp path!(path) when is_list(path) and path != [], do: atoms!(path)

  defp atoms!(path) do
    if Enum.all?(path, &is_atom/1),
      do: path,
      else: raise(ArgumentError, "expected a list of atoms, got: #{inspect(path)}")
  end
end
