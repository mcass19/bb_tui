defmodule BB.TUI.Panels.CommandEditTest do
  use ExUnit.Case, async: true
  doctest BB.TUI.Panels.CommandEdit

  alias BB.TUI.Panels.CommandEdit
  alias BB.TUI.Test.Fixtures
  alias ExRatatui.Text.Line
  alias ExRatatui.Widgets.Popup

  defp text(%Line{spans: spans}), do: Enum.map_join(spans, "", & &1.content)
  defp text(s) when is_binary(s), do: s

  defp cmd do
    %{
      name: :move,
      allowed_states: [:idle],
      arguments: [
        %{name: :angle, type: "float", default: 1.5, required: true, doc: nil},
        %{name: :side, type: "atom", default: :left, required: false, doc: nil}
      ]
    }
  end

  defp state(opts) do
    Fixtures.sample_state(
      Map.merge(
        %{
          commands: [cmd()],
          command_selected: 0,
          command_edit_mode: true,
          command_focused_arg: 0
        },
        opts
      )
    )
  end

  describe "render/1" do
    test "returns nil when the selected command has no arguments" do
      no_args = %{name: :home, allowed_states: [:idle], arguments: []}
      s = Fixtures.sample_state(%{commands: [no_args], command_selected: 0})

      assert CommandEdit.render(s) == nil
    end

    test "returns nil when nothing is selected" do
      s = Fixtures.sample_state(%{commands: []})
      assert CommandEdit.render(s) == nil
    end

    test "renders a Popup titled with the command name" do
      assert %Popup{block: block} = CommandEdit.render(state(%{}))
      assert text(block.title) == " Edit move "
    end

    test "renders one row per declared argument plus a hint line" do
      assert %Popup{content: %{text: lines}} = CommandEdit.render(state(%{}))
      texts = Enum.map(lines, &text/1)

      # Two arg rows + blank separator + hint row
      assert Enum.count(texts, &String.contains?(&1, "angle (float)")) == 1
      assert Enum.count(texts, &String.contains?(&1, "side (atom)")) == 1
      assert Enum.any?(texts, &String.contains?(&1, "[Tab] next"))
    end

    test "focused argument gets the › prefix and ▏ cursor" do
      assert %Popup{content: %{text: lines}} =
               CommandEdit.render(state(%{command_focused_arg: 1}))

      texts = Enum.map(lines, &text/1)

      assert Enum.any?(texts, &(&1 =~ " › side (atom): :left▏"))
      refute Enum.any?(texts, &(&1 =~ " › angle"))
    end

    test "shows the current form value when set, falls back to default otherwise" do
      s = state(%{command_form_values: %{move: %{angle: "2.5"}}})
      assert %Popup{content: %{text: lines}} = CommandEdit.render(s)
      texts = Enum.map(lines, &text/1)

      assert Enum.any?(texts, &String.contains?(&1, "angle (float): 2.5"))
      assert Enum.any?(texts, &String.contains?(&1, "side (atom): :left"))
    end
  end
end
