defmodule BB.TUI.State.Controllers do
  @moduledoc """
  The robot's controllers, for the Controllers tab, split out of
  `BB.TUI.State`.

  `list` holds each controller the robot declares, as
  `%{name:, module:, simulation:}` (see `BB.TUI.Robot.list_controllers/2`);
  `alive` maps a name to whether its process is running, as last checked;
  `selected` is the highlighted row. `detail` is the open inspect popup —
  the controller's name and its `:inspect` answer, `:loading` until it
  arrives — or `nil`.
  """

  defstruct list: [], alive: %{}, selected: 0, detail: nil

  @type controller :: %{name: atom(), module: module(), simulation: atom()}
  @type detail :: %{name: atom(), result: :loading | {:ok, term()} | {:error, term()}}

  @type t :: %__MODULE__{
          list: [controller()],
          alive: %{atom() => boolean()},
          selected: non_neg_integer(),
          detail: detail() | nil
        }

  @doc """
  Moves the selection by `delta` rows, staying on the list.

  ## Examples

      iex> alias BB.TUI.State.Controllers
      iex> controllers = %Controllers{list: [%{name: :a}, %{name: :b}]}
      iex> Controllers.move(controllers, 1).selected
      1
      iex> Controllers.move(controllers, -1).selected
      0
      iex> Controllers.move(%{controllers | selected: 1}, 1).selected
      1
  """
  @spec move(t(), integer()) :: t()
  def move(%__MODULE__{list: list, selected: selected} = controllers, delta),
    do: %{controllers | selected: (selected + delta) |> max(0) |> min(max(length(list) - 1, 0))}

  @doc """
  The selected controller's name, or `nil` when there are none.

  ## Examples

      iex> alias BB.TUI.State.Controllers
      iex> Controllers.selected_name(%Controllers{list: [%{name: :a}, %{name: :b}], selected: 1})
      :b
      iex> Controllers.selected_name(%Controllers{})
      nil
  """
  @spec selected_name(t()) :: atom() | nil
  def selected_name(%__MODULE__{list: list, selected: selected}) do
    case Enum.at(list, selected) do
      %{name: name} -> name
      nil -> nil
    end
  end
end
