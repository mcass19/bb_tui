defmodule BB.TUI.Extension.FormatTest do
  use ExUnit.Case, async: true

  doctest BB.TUI.Extension.Format

  alias BB.TUI.Extension.{Format, Readout}

  describe "readout/2" do
    test "converts a unit-typed value into the readout's unit" do
      assert Format.readout(Localize.Unit.new!(90, "degree"), %Readout{unit: :radian}) =~
               "1.57 rad"
    end

    test "scales before converting" do
      # 0.5 m/s * 2 = 1 m/s = 100 cm/s
      assert Format.readout(0.5, %Readout{scale: 2, unit: :centimeter_per_second, decimals: 0}) ==
               "100 cm/s"
    end

    test "keeps a number as it is when the unit can't be reached from SI" do
      assert Format.readout(1.0, %Readout{unit: :not_a_unit}) == "1.00"
    end

    test "names a unit it has no symbol for" do
      assert Format.readout(Localize.Unit.new!(3, "foot"), %Readout{}) == "3 foot"
    end

    test "shows integers whole and rounds when asked" do
      assert Format.readout(3, %Readout{}) == "3"
      assert Format.readout(3, %Readout{decimals: 1}) == "3.0"
    end

    test "falls back to text for anything that isn't a number" do
      assert Format.readout("ok", %Readout{}) == "ok"
      assert Format.readout({:error, :x}, %Readout{}) == "{:error, :x}"
    end
  end

  describe "number_value/2" do
    test "follows the readout's unit for unit-typed values" do
      assert Format.number_value(Localize.Unit.new!(2, "meter"), %Readout{unit: :centimeter}) ==
               200.0

      assert Format.number_value(Localize.Unit.new!(2, "meter"), %Readout{}) == 2.0
    end
  end
end
