defmodule BB.TUI.Panels.EventDetailTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.EventDetail

  alias BB.TUI.Panels.EventDetail
  alias ExRatatui.Widgets.CodeBlock
  alias ExRatatui.Widgets.Popup

  describe "render/1" do
    test "returns a Popup wrapping a CodeBlock with elixir language" do
      event =
        {~U[2026-01-15 18:23:12.000Z], [:sensor, :sim],
         %{payload: %{names: [:a], positions: [1.0]}}}

      assert %Popup{content: %CodeBlock{language: "elixir"}} = EventDetail.render(event)
    end

    test "code block renders the inspected payload, not the wrapping message map" do
      event =
        {~U[2026-01-15 18:23:12.000Z], [:state_machine],
         %{payload: %{from: :disarmed, to: :armed}}}

      widget = EventDetail.render(event)
      assert widget.content.content =~ ":disarmed"
      assert widget.content.content =~ ":armed"
      assert widget.content.content =~ "from:"
      refute widget.content.content =~ "payload:"
    end

    test "non-map messages still render through inspect/1" do
      event = {~U[2026-01-15 18:23:12.000Z], [:bb, :raw], "literal-string"}
      widget = EventDetail.render(event)
      assert widget.content.content == ~S("literal-string")
    end

    test "block title carries the one-line summary" do
      event = {~U[2026-01-15 18:23:12.000Z], [:test], %{payload: %{key: :val}}}
      widget = EventDetail.render(event)
      assert widget.block.title =~ "test"
      assert widget.block.title =~ "18:23:12"
    end
  end
end
