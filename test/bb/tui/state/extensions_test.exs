defmodule BB.TUI.State.ExtensionsTest do
  use ExUnit.Case, async: true

  doctest BB.TUI.State.Extensions

  alias BB.TUI.Extension.Source
  alias BB.TUI.State.Extensions
  alias BB.TUI.Test

  describe "build/1" do
    test "merges panels, binds and hints in the order given" do
      assert {:ok, extensions} = Extensions.build([Test.Extension, Test.LaterHints])

      assert extensions.modules == [Test.Extension, Test.LaterHints]
      assert Enum.map(extensions.panels, & &1.name) == [:balance, :yaw]
      assert Enum.map(extensions.binds, & &1.key) == ["s"]
      # A later extension's hint for a state replaces an earlier one's.
      assert extensions.hints == %{idle: "later wins", armed: "careful"}
      assert extensions.values == %{}
    end

    test "keeps the one drive" do
      assert {:ok, %{drive: drive}} = Extensions.build([Test.EmptyExtension, Test.Extension])

      assert drive == %{
               extension: Test.Extension,
               publish: {Test.Drive, :command},
               stop: {Test.Drive, :stop},
               throttle_scale: 1.0,
               turn_scale: Source.param([:yaw, :turn_rate]),
               rate: 20
             }
    end

    test "has no drive when none is declared" do
      assert {:ok, %{drive: nil}} = Extensions.build([Test.EmptyExtension])
    end

    test "refuses a second drive" do
      assert {:error, message} = Extensions.build([Test.Extension, Test.SecondDrive])
      assert message =~ "only one extension can declare a drive"
    end

    test "refuses two binds on one key, and two panels of one name" do
      assert {:error, ~s(bound key "s" is declared by more than one extension)} =
               Extensions.build([Test.Extension, Test.ClashingBind])

      assert {:error, "panel :yaw is declared by more than one extension"} =
               Extensions.build([Test.Extension, Test.ClashingPanel])
    end
  end

  describe "what the sources read" do
    test "build/1 lists the topics and controllers to watch" do
      {:ok, extensions} = Extensions.build([Test.Extension])

      assert extensions.topics == [[:sensor, :wheel]]
      assert extensions.controllers == [:balancer, :yaw]
    end

    test "put_message/3 ignores messages when no source reads a topic" do
      assert Extensions.put_message(%Extensions{}, [:drive], %{vx: 1}) == %Extensions{}
    end

    test "put_message/3 matches an exact path, and a longer one only for [root, name]" do
      ext = %Extensions{topics: [[:drive], [:sensor, :imu, :raw]]}

      ext = Extensions.put_message(ext, [:drive], %{vx: 1})
      ext = Extensions.put_message(ext, [:sensor, :base, :imu, :raw], %{x: 2})

      assert ext.values == %{{:topic, [:drive]} => %{vx: 1}}
    end

    test "read/2 is nil for a joint the robot doesn't have and digs only into maps" do
      state = %BB.TUI.State{
        parameters: %BB.TUI.State.Parameters{list: [{[:other], 1}, {[:yaw, :rate], 2}]},
        extensions: %Extensions{values: %{{:topic, [:drive]} => %{vx: 1.0}}}
      }

      assert Extensions.read(state, Source.param([:yaw, :rate])) == 2

      assert Extensions.read(state, Source.joint(:missing)) == nil
      assert Extensions.read(state, Source.param([:missing])) == nil
      assert Extensions.read(state, Source.topic([:drive], [:vx, :deeper])) == nil
      assert Extensions.read(state, Source.topic([:drive], :vx)) == 1.0
    end
  end

  describe "sources/1 and subscribe_paths/2" do
    setup do
      {:ok, extensions} = Extensions.build([Test.Extension])
      %{extensions: extensions}
    end

    test "lists each source once, the drive's parameter scale included", %{extensions: ext} do
      assert Extensions.sources(ext) == [
               Source.joint(:lean),
               Source.controller(:balancer, :target),
               Source.topic([:sensor, :wheel], [:velocity, :x]),
               Source.controller(:yaw, :heading),
               Source.param([:yaw, :turn_rate])
             ]
    end

    test "skips topics already under a subscribed path", %{extensions: ext} do
      assert Extensions.subscribe_paths(ext, [[:sensor]]) == []
      assert Extensions.subscribe_paths(ext, [[:command]]) == [[:sensor, :wheel]]
    end

    test "keeps the shortest of overlapping extension paths" do
      readout = fn path ->
        %BB.TUI.Extension.Readout{label: "x", source: Source.topic(path, :x)}
      end

      ext = %Extensions{
        panels: [
          %BB.TUI.Extension.Panel{
            name: :p,
            items: [readout.([:sensor, :imu]), readout.([:sensor]), readout.([:drive])]
          }
        ]
      }

      assert Extensions.subscribe_paths(ext, []) == [[:sensor], [:drive]]
    end
  end
end
