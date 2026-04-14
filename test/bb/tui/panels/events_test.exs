defmodule BB.TUI.Panels.EventsTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.Events

  alias BB.TUI.Panels.Events
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.List, as: WidgetList
  alias ExRatatui.Widgets.Scrollbar

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

  describe "render_panes/3" do
    setup do
      %{rect: %Rect{x: 2, y: 3, width: 40, height: 10}}
    end

    test "returns only the list pane when there are no events", %{rect: rect} do
      state = Fixtures.sample_state(%{events: []})

      assert [{list_widget, ^rect}] = Events.render_panes(state, false, rect)
      assert %WidgetList{} = list_widget
    end

    test "returns list + scrollbar when events exist", %{rect: rect} do
      events =
        for i <- 1..5 do
          {DateTime.add(~U[2026-03-30 12:00:00Z], i, :second), [:test], %{}}
        end

      state = Fixtures.sample_state(%{events: events, scroll_offset: 2})

      assert [{list_widget, list_rect}, {scrollbar, scrollbar_rect}] =
               Events.render_panes(state, true, rect)

      assert %WidgetList{} = list_widget
      assert list_rect == rect

      assert %Scrollbar{
               orientation: :vertical_right,
               content_length: 5,
               position: 2
             } = scrollbar

      # Inset by one cell on every side so the bar renders inside the block border.
      assert scrollbar_rect.x == rect.x + 1
      assert scrollbar_rect.y == rect.y + 1
      assert scrollbar_rect.width == rect.width - 2
      assert scrollbar_rect.height == rect.height - 2
    end

    test "sets viewport_content_length from the rect", %{rect: rect} do
      events = [{~U[2026-03-30 12:00:00Z], [:test], %{}}]
      state = Fixtures.sample_state(%{events: events})

      [{_list, _}, {%Scrollbar{viewport_content_length: viewport}, _}] =
        Events.render_panes(state, false, rect)

      assert viewport == rect.height - 2
    end

    test "clamps inset dimensions when rect is tiny" do
      tiny = %Rect{x: 0, y: 0, width: 1, height: 1}
      events = [{~U[2026-03-30 12:00:00Z], [:test], %{}}]
      state = Fixtures.sample_state(%{events: events})

      [{_list, _}, {_scrollbar, scrollbar_rect}] = Events.render_panes(state, false, tiny)

      assert scrollbar_rect.width == 0
      assert scrollbar_rect.height == 0
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

  describe "format_event_details/1" do
    test "formats struct payload with type and fields" do
      # Use a standard library struct to test the struct payload path
      uri = %URI{scheme: "https", host: "example.com"}

      event = {~U[2026-01-15 18:23:12.000Z], [:test], %{payload: uri}}

      details = Events.format_event_details(event)

      assert is_list(details)
      # type line with module name
      assert Enum.any?(details, &(&1 =~ "URI"))
      # field lines
      assert Enum.any?(details, &(&1 =~ "scheme"))
      assert Enum.any?(details, &(&1 =~ "host"))
    end

    test "formats plain map payload" do
      event = {~U[2026-01-15 18:23:12.000Z], [:test], %{payload: %{foo: 1, bar: 2}}}
      details = Events.format_event_details(event)

      assert is_list(details)
      assert Enum.any?(details, &(&1 =~ "bar"))
      assert Enum.any?(details, &(&1 =~ "foo"))
    end

    test "formats non-map message" do
      event = {~U[2026-01-15 18:23:12.000Z], [:test], :raw_atom}
      details = Events.format_event_details(event)

      assert is_list(details)
      assert Enum.any?(details, &(&1 =~ "raw_atom"))
    end

    test "formats list values inside payload" do
      event =
        {~U[2026-01-15 18:23:12.000Z], [:test],
         %{payload: %{positions: [1.5, 2.3], names: [:a, :b]}}}

      details = Events.format_event_details(event)

      assert Enum.any?(details, &(&1 =~ "1.500"))
      assert Enum.any?(details, &(&1 =~ ":a"))
    end
  end
end
