defmodule BB.TUI.Panels.EventDetailTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.EventDetail

  alias BB.TUI.Panels.EventDetail
  alias ExRatatui.Widgets.Popup

  describe "render/1" do
    test "returns a Popup widget" do
      event =
        {~U[2026-01-15 18:23:12.000Z], [:sensor, :sim],
         %{payload: %{names: [:a], positions: [1.0]}}}

      widget = EventDetail.render(event)
      assert %Popup{} = widget
    end

    test "contains event summary and details" do
      event =
        {~U[2026-01-15 18:23:12.000Z], [:state_machine],
         %{payload: %{from: :disarmed, to: :armed}}}

      widget = EventDetail.render(event)
      assert widget.content.text =~ "state_machine"
      assert widget.content.text =~ "from"
      assert widget.content.text =~ "to"
    end

    test "has Event Detail title" do
      event = {~U[2026-01-15 18:23:12.000Z], [:test], %{payload: %{key: :val}}}
      widget = EventDetail.render(event)
      assert widget.block.title == " Event Detail "
    end
  end
end
