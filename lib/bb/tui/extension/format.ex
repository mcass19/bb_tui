defmodule BB.TUI.Extension.Format do
  @moduledoc """
  Turns a source's value into readout text, following the readout's
  `scale`, `unit` and `decimals`.

  A plain number is taken to be in SI units, as bb works: with `unit:
  :degree` a joint's radians are shown in degrees, and with `unit:
  :centimeter_per_second` a speed in m/s in cm/s. A `Localize.Unit` value
  (a unit-typed parameter) converts from its own unit. `scale` multiplies
  the value first. Common units get their symbol (`°`, `cm/s`, `V`); any
  other shows its CLDR name.

  Floats show 2 decimals unless `decimals` says otherwise. A missing value
  shows as `-`, and anything that isn't a number as its plain text.
  """

  alias BB.TUI.Extension.Readout
  alias Localize.Unit.BaseUnit

  @symbols %{
    "degree" => "°",
    "degree-per-second" => "°/s",
    "radian" => "rad",
    "radian-per-second" => "rad/s",
    "revolution-per-minute" => "rpm",
    "meter" => "m",
    "centimeter" => "cm",
    "millimeter" => "mm",
    "meter-per-second" => "m/s",
    "centimeter-per-second" => "cm/s",
    "volt" => "V",
    "ampere" => "A",
    "watt" => "W",
    "percent" => "%",
    "hertz" => "Hz",
    "second" => "s",
    "millisecond" => "ms",
    "celsius" => "°C"
  }

  @doc """
  Formats `value` for `readout`.

  ## Examples

      iex> alias BB.TUI.Extension.{Format, Readout}
      iex> Format.readout(:math.pi() / 2, %Readout{unit: :degree, decimals: 1})
      "90.0°"
      iex> Format.readout(0.25, %Readout{unit: :centimeter_per_second})
      "25.00 cm/s"
      iex> Format.readout(2, %Readout{scale: 1.5})
      "3.00"
      iex> Format.readout(7, %Readout{})
      "7"
      iex> Format.readout(Localize.Unit.new!(5, "degree"), %Readout{})
      "5°"
      iex> Format.readout(nil, %Readout{})
      "-"
      iex> Format.readout(:balancing, %Readout{})
      "balancing"
  """
  @spec readout(term(), Readout.t()) :: String.t()
  def readout(nil, _readout), do: "-"

  def readout(value, readout) do
    case measure(value, readout) do
      {number, unit} -> number(number, readout) <> suffix(unit)
      :error when is_atom(value) or is_binary(value) -> to_string(value)
      :error -> inspect(value, limit: 5)
    end
  end

  @doc """
  The value of a source as a plain number for a chart, or `nil` when it
  isn't one. Follows the same `scale` and `unit` as `readout/2`.

  ## Examples

      iex> alias BB.TUI.Extension.{Format, Readout}
      iex> Format.number_value(:math.pi(), %Readout{unit: :degree})
      180.0
      iex> Format.number_value(:idle, %Readout{})
      nil
  """
  @spec number_value(term(), Readout.t()) :: float() | nil
  def number_value(value, readout) do
    case measure(value, readout) do
      {number, _unit} -> number * 1.0
      :error -> nil
    end
  end

  # `{number, unit name or nil}` after scaling and conversion, or `:error`
  # for a value that isn't a number.
  # A unit-typed value keeps its own unit when it can't be converted; a plain
  # number has none to keep.
  defp measure(%Localize.Unit{value: magnitude, name: name}, readout)
       when is_number(magnitude) do
    number = scaled(magnitude, readout)
    convert(number, name, readout.unit) || {number, name}
  end

  defp measure(value, readout) when is_number(value) do
    number = scaled(value, readout)

    convert(number, readout.unit && si_unit(unit_name(readout.unit)), readout.unit) ||
      {number, nil}
  end

  defp measure(_value, _readout), do: :error

  defp convert(_number, _from, nil), do: nil

  defp convert(number, from, unit) do
    target = unit_name(unit)

    with {:ok, value} <- Localize.Unit.new(number, from),
         {:ok, %Localize.Unit{value: converted}} when is_number(converted) <-
           Localize.Unit.convert(value, target) do
      {converted, target}
    else
      _ -> nil
    end
  end

  @doc false
  # Spark `:custom` type for a readout's `unit:` — a unit Localize knows, so a
  # misspelt one fails at compile time rather than showing a bare number.
  def validate_unit(unit) when is_atom(unit) do
    case Localize.Unit.new(1, unit_name(unit)) do
      {:ok, _value} -> {:ok, unit}
      {:error, _reason} -> {:error, "unknown unit #{inspect(unit)}"}
    end
  end

  def validate_unit(other), do: {:error, "expected a unit atom, got: #{inspect(other)}"}

  defp scaled(value, %Readout{scale: nil}), do: value
  defp scaled(value, %Readout{scale: scale}), do: value * scale

  # bb's unit atoms are CLDR names with underscores: :degree_per_second.
  defp unit_name(unit), do: unit |> Atom.to_string() |> String.replace("_", "-")

  # The unit a plain number from bb is in: the target's SI base, with angles
  # in radians (CLDR's base for angles is the revolution).
  defp si_unit(target) do
    case BaseUnit.base_unit(target) do
      {:ok, base} -> String.replace(base, "revolution", "radian")
      {:error, _reason} -> target
    end
  end

  defp number(value, %Readout{decimals: nil}) when is_integer(value), do: Integer.to_string(value)

  defp number(value, %Readout{decimals: nil}),
    do: :erlang.float_to_binary(value * 1.0, decimals: 2)

  defp number(value, %Readout{decimals: decimals}),
    do: :erlang.float_to_binary(value * 1.0, decimals: decimals)

  defp suffix(nil), do: ""

  defp suffix(name) do
    case Map.fetch(@symbols, name) do
      {:ok, "°" <> _ = symbol} -> symbol
      {:ok, symbol} -> " " <> symbol
      :error -> " " <> name
    end
  end
end
