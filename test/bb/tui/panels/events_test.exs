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
      assert widget.block.title == " Events "
    end

    test "renders events with formatted entries" do
      events = [
        {~U[2026-03-30 12:00:00Z], [:state_machine], %{payload: %{from: :disarmed, to: :armed}}},
        {~U[2026-03-30 11:59:00Z], [:sensor, :joint],
         %{payload: %{names: [:a], positions: [1.0]}}}
      ]

      state = Fixtures.sample_state(%{events: events})
      widget = Events.render(state, true)

      assert length(widget.items) == 2
      assert widget.block.title == " Events (2) "

      first_item = hd(widget.items)
      assert first_item =~ "12:00:00"
      assert first_item =~ "state_machine"
      assert first_item =~ "\u{2192}"
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

    test "shows pause indicator when paused" do
      state = Fixtures.sample_state(%{events: [], events_paused: true})
      widget = Events.render(state, false)

      assert widget.block.title =~ "PAUSED"
    end

    test "shows count with pause indicator" do
      events = [{~U[2026-03-30 12:00:00Z], [:test], %{}}]
      state = Fixtures.sample_state(%{events: events, events_paused: true})
      widget = Events.render(state, false)

      assert widget.block.title =~ "1"
      assert widget.block.title =~ "PAUSED"
    end
  end

  describe "summarize/2" do
    test "summarizes sensor joint state events" do
      msg = %{payload: %{names: [:a, :b, :c], positions: [1.0, 2.0, 3.0]}}
      assert Events.summarize([:sensor, :sim], msg) == "JointState 3 joint(s)"
    end

    test "summarizes state machine transitions" do
      msg = %{payload: %{from: :armed, to: :idle}}
      assert Events.summarize([:state_machine], msg) == "armed \u{2192} idle"
    end

    test "summarizes parameter changes" do
      msg = %{payload: %{new_value: 42}}
      assert Events.summarize([:param, :speed], msg) == "speed = 42"
    end

    test "summarizes nested parameter paths" do
      msg = %{payload: %{new_value: 0.5}}
      assert Events.summarize([:param, :controller, :kp], msg) == "controller.kp = 0.5"
    end

    test "falls back to inspect for unknown payloads" do
      msg = %{payload: :something}
      result = Events.summarize([:unknown], msg)
      assert result == ":something"
    end

    test "falls back to inspect for non-map messages" do
      result = Events.summarize([:test], :raw_atom)
      assert result == ":raw_atom"
    end
  end
end
