defmodule BB.TUI.State.DriveTest do
  use ExUnit.Case, async: true

  doctest BB.TUI.State.Drive

  alias BB.TUI.State.Drive

  describe "inference mode" do
    test "a held key keeps driving while its autorepeat arrives" do
      drive = Drive.press(%Drive{}, "up", 0)
      assert {{:publish, 1, 0}, drive} = Drive.step(drive, 500)

      # The OS starts repeating after ~500 ms; repeats arrive every ~33 ms.
      drive = Drive.press(drive, "up", 550)
      assert {{:publish, 1, 0}, drive} = Drive.step(drive, 650)
      drive = Drive.press(drive, "up", 680)
      assert {{:publish, 1, 0}, drive} = Drive.step(drive, 800)

      # Repeats stop: let go 150 ms after the last one.
      assert {{:publish, 1, 0}, drive} = Drive.step(drive, 830)
      assert {:stop, _drive} = Drive.step(drive, 840)
    end

    test "a single tap drives for the first-press window, then stops" do
      drive = Drive.press(%Drive{}, "left", 0)
      assert {{:publish, 0, 1}, drive} = Drive.step(drive, 600)
      assert {:stop, drive} = Drive.step(drive, 601)
      assert {:idle, _} = Drive.step(drive, 700)
    end

    test "the opposite arrow takes over its axis; releasing the old one changes nothing" do
      drive = %Drive{} |> Drive.press("left", 0) |> Drive.press("right", 10)
      assert {{:publish, 0, -1}, drive} = Drive.step(drive, 20)

      drive = Drive.release(drive, "left")
      assert {{:publish, 0, -1}, _} = Drive.step(drive, 30)
    end

    test "both axes at once" do
      drive = %Drive{} |> Drive.press("down", 0) |> Drive.press("right", 0)
      assert {{:publish, -1, -1}, _} = Drive.step(drive, 10)
    end
  end

  describe "release mode" do
    test "holds a key until its release, with no repeats needed" do
      drive = %Drive{mode: :release} |> Drive.press("up", 0)
      assert {{:publish, 1, 0}, drive} = Drive.step(drive, 900)

      drive = Drive.release(drive, "up")
      assert {:stop, _} = Drive.step(drive, 910)
    end

    test "lets go of a key whose release got lost after the safety window" do
      drive = %Drive{mode: :release} |> Drive.press("up", 0)
      drive = Drive.press(drive, "up", 900)
      assert {{:publish, 1, 0}, drive} = Drive.step(drive, 1_800)
      assert {:stop, _} = Drive.step(drive, 1_901)
    end
  end

  test "active? stays true until the owed stop is taken" do
    drive = Drive.press(%Drive{}, "up", 0)
    assert Drive.active?(drive)
    {_publish, drive} = Drive.step(drive, 0)
    {:stop, drive} = Drive.step(drive, 1_000)
    refute Drive.active?(drive)
  end
end
