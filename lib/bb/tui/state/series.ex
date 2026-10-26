defmodule BB.TUI.State.Series do
  @moduledoc """
  The recent history of one plotted value: `{monotonic_ms, value}` samples
  kept for `window` milliseconds, and never more than `max` of them, so a
  200 Hz topic can't grow it without bound.

  Backed by a `:queue` with its length kept alongside, so recording a
  sample costs the same however full the series is.
  """

  # Built with `new/2`: a `:queue.new()` default would be evaluated at
  # compile time, into a literal that breaks the queue's opaque type.
  defstruct [:queue, count: 0, window: 10_000, max: 1_000]

  @type t :: %__MODULE__{
          queue: :queue.queue({integer(), number()}),
          count: non_neg_integer(),
          window: pos_integer(),
          max: pos_integer()
        }

  @doc """
  An empty series keeping `window` milliseconds of samples.

  ## Examples

      iex> BB.TUI.State.Series.new(5_000).window
      5000
  """
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(window, max \\ 1_000),
    do: %__MODULE__{queue: :queue.new(), window: window, max: max}

  @doc """
  Records `value` at `now`, dropping samples older than the window and the
  oldest beyond `max`.

  ## Examples

      iex> alias BB.TUI.State.Series
      iex> series = Series.new(1_000) |> Series.push(0, 1.0) |> Series.push(500, 2.0) |> Series.push(1_200, 3.0)
      iex> Series.values(series)
      [2.0, 3.0]
      iex> series = Series.new(10_000, 2) |> Series.push(0, 1) |> Series.push(1, 2) |> Series.push(2, 3)
      iex> Series.values(series)
      [2, 3]
  """
  @spec push(t(), integer(), number()) :: t()
  def push(%__MODULE__{} = series, now, value) do
    trim(%{series | queue: :queue.in({now, value}, series.queue), count: series.count + 1}, now)
  end

  defp trim(%__MODULE__{count: count, max: max} = series, now) do
    case :queue.peek(series.queue) do
      {:value, {at, _value}} when count > max or at < now - series.window ->
        trim(%{series | queue: :queue.drop(series.queue), count: count - 1}, now)

      _ ->
        series
    end
  end

  @doc """
  The samples as chart points: `{seconds_before_now, value}`, oldest first,
  limited to the window ending at `now`.

  ## Examples

      iex> alias BB.TUI.State.Series
      iex> series = Series.new(10_000) |> Series.push(1_000, 1.0) |> Series.push(3_000, 2.0)
      iex> Series.points(series, 4_000)
      [{-3.0, 1.0}, {-1.0, 2.0}]
  """
  @spec points(t(), integer()) :: [{float(), number()}]
  def points(%__MODULE__{} = series, now) do
    for {at, value} <- :queue.to_list(series.queue),
        at >= now - series.window,
        do: {(at - now) / 1000, value}
  end

  @doc """
  The sample values, oldest first.

  ## Examples

      iex> BB.TUI.State.Series.new(1_000) |> BB.TUI.State.Series.push(0, 4) |> BB.TUI.State.Series.values()
      [4]
  """
  @spec values(t()) :: [number()]
  def values(%__MODULE__{queue: queue}), do: for({_at, value} <- :queue.to_list(queue), do: value)
end
