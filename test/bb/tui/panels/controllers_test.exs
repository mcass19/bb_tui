defmodule BB.TUI.Panels.ControllersTest do
  use ExUnit.Case, async: true

  doctest BB.TUI.Panels.Controllers

  alias BB.TUI.Panels.Controllers
  alias BB.TUI.State
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.{CodeBlock, Popup, Table}

  defp statuses(state) do
    %Table{rows: rows} = Controllers.render(state)
    for [_name, _module, %Line{spans: spans}] <- rows, do: Enum.map_join(spans, & &1.content)
  end

  defp state(alive, simulation \\ nil) do
    list =
      for name <- [:balancer, :yaw, :leds],
          do: %{name: name, module: MyBot, simulation: if(name == :leds, do: :omit, else: :start)}

    %State{simulation: simulation, controllers: %State.Controllers{list: list, alive: alive}}
  end

  test "says whether each controller runs, or that it's unknown" do
    assert statuses(state(%{balancer: true, yaw: false})) ==
             ["● running", "○ not running", "?"]
  end

  test "a controller left out of simulation says so instead of not running" do
    assert statuses(state(%{balancer: true, yaw: true, leds: false}, :kinematic)) ==
             ["● running", "● running", "off in simulation"]
  end

  test "highlights the selected controller, and nothing when there are none" do
    state = state(%{})
    assert %Table{selected: 0} = Controllers.render(state)
    assert %Table{selected: 2} = Controllers.render(put_in(state.controllers.selected, 2))
    assert %Table{rows: [], selected: nil} = Controllers.render(%State{})
  end

  test "the popup says when it is waiting or got no answer" do
    assert %Popup{content: %CodeBlock{content: "# asking…"}, block: block} =
             Controllers.detail(%{name: :yaw, result: :loading})

    assert block.title =~ "yaw :inspect"

    assert %Popup{content: %CodeBlock{content: "# no answer: :noproc"}} =
             Controllers.detail(%{name: :yaw, result: {:error, :noproc}})
  end
end
