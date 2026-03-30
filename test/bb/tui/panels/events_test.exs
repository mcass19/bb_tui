defmodule BB.TUI.Panels.EventsTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Events

  alias BB.TUI.Panels.Events
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Widgets.List, as: WidgetList

  describe "render/2" do
    test "renders empty event list" do
      state = Fixtures.sample_state(%{events: []})
      widget = Events.render(state, false)

      assert %WidgetList{} = widget
      assert widget.items == []
      assert widget.block.title == " Events (0) "
    end

    test "renders events with formatted entries" do
      events = [
        {~U[2026-03-30 12:00:00Z], [:state_machine], %{to: :armed}},
        {~U[2026-03-30 11:59:00Z], [:sensor, :joint], %{position: 42.0}}
      ]

      state = Fixtures.sample_state(%{events: events})
      widget = Events.render(state, true)

      assert length(widget.items) == 2
      assert widget.block.title == " Events (2) "

      first_item = hd(widget.items)
      assert first_item =~ "12:00:00"
      assert first_item =~ "state_machine"
    end

    test "uses scroll_offset as selected index" do
      events = [
        {~U[2026-03-30 12:00:00Z], [:test], %{}},
        {~U[2026-03-30 11:59:00Z], [:test], %{}}
      ]

      state = Fixtures.sample_state(%{events: events, scroll_offset: 1})
      widget = Events.render(state, true)

      assert widget.selected == 1
    end

    test "selected is nil when no events" do
      state = Fixtures.sample_state(%{events: []})
      widget = Events.render(state, true)

      assert widget.selected == nil
    end
  end
end
