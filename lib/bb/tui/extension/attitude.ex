defmodule BB.TUI.Extension.Attitude do
  @moduledoc """
  An attitude indicator in a panel: an artificial horizon and pitch ladder,
  moved by `pitch` and tilted by `roll` behind a fixed aircraft symbol, with
  both angles in degrees underneath.

  Both sources read radians — an orientation's `:pitch` or `:roll`, a lean
  joint — and either may be left out. `scale` multiplies both first, so
  `scale: -1` flips a robot whose angles run the other way. The signs are
  bb's (x forward, y left, z up): positive pitch, about +Y, tips the nose
  down and moves the horizon up — a balancing robot leaning forward — and
  positive roll, about +X, tips the right side down and lifts the
  horizon's right end. `range` is the pitch, in degrees, from the centre
  to the top edge.
  """
  defstruct [:label, :pitch, :roll, :scale, range: 30, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          label: String.t(),
          pitch: BB.TUI.Extension.Source.t() | nil,
          roll: BB.TUI.Extension.Source.t() | nil,
          scale: number() | nil,
          range: pos_integer()
        }

  @doc """
  Checks a declared indicator reads at least one angle.

  ## Examples

      iex> alias BB.TUI.Extension.{Attitude, Source}
      iex> {:ok, _attitude} = Attitude.validate(%Attitude{label: "lean", pitch: Source.joint(:lean)})
      iex> Attitude.validate(%Attitude{label: "lean"})
      {:error, "attitude \\"lean\\" needs a pitch or a roll source"}
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{pitch: nil, roll: nil, label: label}),
    do: {:error, "attitude #{inspect(label)} needs a pitch or a roll source"}

  def validate(%__MODULE__{} = attitude), do: {:ok, attitude}
end
