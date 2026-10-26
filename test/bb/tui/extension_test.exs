defmodule BB.TUI.ExtensionTest do
  use ExUnit.Case, async: true

  import Spark.Test

  doctest BB.TUI.Extension
  doctest BB.TUI.Extension.Source

  alias BB.TUI.Extension
  alias BB.TUI.Extension.{Bind, Format, Hint, Info, Panel, Plot, Readout, Source}
  alias BB.TUI.Test.EmptyExtension
  alias BB.TUI.Test.Extension, as: TestExtension
  alias Spark.Error.DslError

  describe "a declared extension" do
    test "is recognised as one" do
      assert Extension.extension?(TestExtension)
      refute Extension.extension?(:not_a_module)
    end

    test "reads its drive back" do
      assert Info.drive?(TestExtension)
      assert Info.drive_publish!(TestExtension) == {BB.TUI.Test.Drive, :command}
      assert Info.drive_stop!(TestExtension) == {BB.TUI.Test.Drive, :stop}
      assert Info.drive_throttle_scale!(TestExtension) == 1.0
      assert Info.drive_turn_scale!(TestExtension) == Source.param([:yaw, :turn_rate])
      assert Info.drive_rate!(TestExtension) == 20
    end

    test "reads its panels back, items in the order declared" do
      assert [%Panel{name: :balance, title: "Balance", tab: :drive, items: items}, yaw] =
               Info.panels(TestExtension)

      assert [
               %Readout{label: "lean", source: %Source{type: :joint}, unit: :degree, decimals: 1},
               %Plot{label: "lean vs target", sources: [_, _], window: 10_000, y_range: nil},
               %Readout{label: "speed", scale: 2.15, spark: false}
             ] = items

      assert %Panel{name: :yaw, title: nil, tab: nil} = yaw
    end

    test "reads its keys and hints back" do
      assert [%Bind{key: "s", command: :stand, label: "stand"}] = Info.keys(TestExtension)
      assert [%Hint{state: :idle, text: "s to stand"}] = Info.hints(TestExtension)
    end

    test "an empty extension declares no drive and nothing else" do
      refute Info.drive?(EmptyExtension)
      assert Info.panels(EmptyExtension) == []
      assert Info.keys(EmptyExtension) == []
      assert Info.hints(EmptyExtension) == []
    end
  end

  describe "verifiers" do
    test "a drive needs both publish and stop" do
      error =
        assert_dsl_error %DslError{path: [:drive]} do
          defmodule HalfDrive do
            use BB.TUI.Extension

            drive do
              publish {BB.TUI.Test.Drive, :command}
            end
          end
        end

      assert error.message =~ "both `publish` and `stop`"
    end

    test "drive functions must be exported with the right arity" do
      error =
        assert_dsl_error %DslError{path: [:drive, :publish]} do
          defmodule WrongArity do
            use BB.TUI.Extension

            drive do
              publish {BB.TUI.Test.Drive, :stop}
              stop {BB.TUI.Test.Drive, :stop}
            end
          end
        end

      assert error.message =~ "BB.TUI.Test.Drive.stop/3 is not exported"

      assert_dsl_error %DslError{path: [:drive, :stop]} do
        defmodule WrongStop do
          use BB.TUI.Extension

          drive do
            publish {BB.TUI.Test.Drive, :command}
            stop {BB.TUI.Test.Drive, :command}
          end
        end
      end
    end

    test "a drive module that can't be loaded here is left for the session to check" do
      refute_dsl_errors do
        defmodule RemoteDrive do
          use BB.TUI.Extension

          drive do
            publish {OnlyOnTheRobot.Drive, :command}
            stop {OnlyOnTheRobot.Drive, :stop}
          end
        end
      end
    end

    test "binds can't take bb_tui's own keys" do
      error =
        assert_dsl_error %DslError{path: [:keys, :bind, "q"]} do
          defmodule QuitBind do
            use BB.TUI.Extension

            keys do
              bind "q", command: :stand
            end
          end
        end

      assert error.message =~ ~s("q" is one of bb_tui's own keys)
    end

    test "a readout's unit must be one Localize knows" do
      assert_raise DslError, ~r/unknown unit :centimetre_per_second/, fn ->
        defmodule MisspeltUnit do
          use BB.TUI.Extension

          panels do
            panel :p do
              readout "speed", joint(:wheel), unit: :centimetre_per_second
            end
          end
        end
      end

      assert Format.validate_unit(:degree) == {:ok, :degree}

      assert {:error, "expected a unit atom" <> _} =
               Format.validate_unit("degree")
    end

    test "a key can only be bound once" do
      assert_dsl_error do
        defmodule DoubleBind do
          use BB.TUI.Extension

          keys do
            bind "s", command: :stand
            bind "s", command: :sit
          end
        end
      end
    end
  end

  describe "sources" do
    test "reject paths that aren't atoms" do
      assert_raise ArgumentError, fn -> Source.topic([:sensor, "imu"], :x) end
      assert_raise ArgumentError, fn -> Source.controller(:balancer, [:gains, "kp"]) end
    end

    test "collect the topics an extension needs" do
      sources =
        for %Panel{items: items} <- Info.panels(TestExtension),
            item <- items,
            source <- List.wrap(Map.get(item, :source) || item.sources),
            do: source

      assert Source.subscribe_paths(sources) == [[:sensor, :wheel]]
    end
  end
end
