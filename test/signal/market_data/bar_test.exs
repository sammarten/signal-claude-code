defmodule Signal.MarketData.BarTest do
  use Signal.DataCase

  alias Signal.MarketData.Bar

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Bar.changeset(%Bar{}, %{})

      refute changeset.valid?

      assert %{
               symbol: ["can't be blank"],
               bar_time: ["can't be blank"],
               open: ["can't be blank"],
               high: ["can't be blank"],
               low: ["can't be blank"],
               close: ["can't be blank"],
               volume: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "accepts valid bar data" do
      attrs = %{
        symbol: "AAPL",
        bar_time: ~U[2024-11-15 09:30:00Z],
        open: Decimal.new("185.20"),
        high: Decimal.new("185.60"),
        low: Decimal.new("184.90"),
        close: Decimal.new("185.45"),
        volume: 2_300_000,
        vwap: Decimal.new("185.32"),
        trade_count: 150
      }

      changeset = Bar.changeset(%Bar{}, attrs)
      assert changeset.valid?
    end

    test "validates volume >= 0" do
      attrs = valid_bar_attrs() |> Map.put(:volume, -100)
      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      assert %{volume: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "validates trade_count >= 0 when present" do
      attrs = valid_bar_attrs() |> Map.put(:trade_count, -5)
      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      assert %{trade_count: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end
  end

  describe "OHLC validations" do
    test "rejects high < open" do
      attrs =
        valid_bar_attrs()
        |> Map.merge(%{open: Decimal.new("185.00"), high: Decimal.new("184.00")})

      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert "must be greater than or equal to open" in errors.high
    end

    test "rejects high < close" do
      attrs =
        valid_bar_attrs()
        |> Map.merge(%{close: Decimal.new("185.00"), high: Decimal.new("184.00")})

      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert "must be greater than or equal to close" in errors.high
    end

    test "rejects high < low" do
      attrs =
        valid_bar_attrs() |> Map.merge(%{low: Decimal.new("185.00"), high: Decimal.new("184.00")})

      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert "must be greater than or equal to low" in errors.high
    end

    test "rejects low > open" do
      attrs =
        valid_bar_attrs() |> Map.merge(%{open: Decimal.new("184.00"), low: Decimal.new("185.00")})

      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      assert %{low: ["must be less than or equal to open"]} = errors_on(changeset)
    end

    test "rejects low > close" do
      attrs =
        valid_bar_attrs()
        |> Map.merge(%{close: Decimal.new("184.00"), low: Decimal.new("185.00")})

      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      assert %{low: ["must be less than or equal to close"]} = errors_on(changeset)
    end

    test "rejects low > high" do
      attrs =
        valid_bar_attrs() |> Map.merge(%{high: Decimal.new("184.00"), low: Decimal.new("185.00")})

      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      assert %{low: ["must be less than or equal to high"]} = errors_on(changeset)
    end

    test "accepts valid OHLC relationships" do
      # High is the highest, low is the lowest
      attrs =
        valid_bar_attrs()
        |> Map.merge(%{
          open: Decimal.new("185.00"),
          high: Decimal.new("186.00"),
          low: Decimal.new("184.00"),
          close: Decimal.new("185.50")
        })

      changeset = Bar.changeset(%Bar{}, attrs)
      assert changeset.valid?
    end

    test "accepts doji bar (all prices equal)" do
      # Doji bar where open = high = low = close
      price = Decimal.new("185.00")

      attrs =
        valid_bar_attrs()
        |> Map.merge(%{open: price, high: price, low: price, close: price})

      changeset = Bar.changeset(%Bar{}, attrs)
      assert changeset.valid?
    end
  end

  describe "price validations" do
    test "rejects zero prices" do
      attrs = valid_bar_attrs() |> Map.put(:open, Decimal.new("0"))
      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      assert %{open: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "rejects negative prices" do
      attrs = valid_bar_attrs() |> Map.put(:close, Decimal.new("-5.00"))
      changeset = Bar.changeset(%Bar{}, attrs)

      refute changeset.valid?
      assert %{close: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "accepts positive prices" do
      attrs =
        valid_bar_attrs()
        |> Map.merge(%{
          open: Decimal.new("0.01"),
          high: Decimal.new("0.02"),
          low: Decimal.new("0.005"),
          close: Decimal.new("0.015")
        })

      changeset = Bar.changeset(%Bar{}, attrs)
      assert changeset.valid?
    end
  end

  describe "from_alpaca/2" do
    test "converts AlpacaEx bar to Bar attributes" do
      alpaca_bar = %{
        timestamp: ~U[2024-11-15 09:30:00Z],
        open: Decimal.new("185.20"),
        high: Decimal.new("185.60"),
        low: Decimal.new("184.90"),
        close: Decimal.new("185.45"),
        volume: 2_300_000,
        vwap: Decimal.new("185.32"),
        trade_count: 150
      }

      result = Bar.from_alpaca(alpaca_bar, "AAPL")

      assert result == %{
               symbol: "AAPL",
               bar_time: ~U[2024-11-15 09:30:00Z],
               open: Decimal.new("185.20"),
               high: Decimal.new("185.60"),
               low: Decimal.new("184.90"),
               close: Decimal.new("185.45"),
               volume: 2_300_000,
               vwap: Decimal.new("185.32"),
               trade_count: 150
             }
    end

    test "handles missing optional fields" do
      alpaca_bar = %{
        timestamp: ~U[2024-11-15 09:30:00Z],
        open: Decimal.new("185.20"),
        high: Decimal.new("185.60"),
        low: Decimal.new("184.90"),
        close: Decimal.new("185.45"),
        volume: 2_300_000
      }

      result = Bar.from_alpaca(alpaca_bar, "TSLA")

      assert result.symbol == "TSLA"
      assert result.vwap == nil
      assert result.trade_count == nil
    end

    test "converts string prices to Decimal" do
      alpaca_bar = %{
        timestamp: ~U[2024-11-15 09:30:00Z],
        open: "185.20",
        high: "185.60",
        low: "184.90",
        close: "185.45",
        volume: 2_300_000
      }

      result = Bar.from_alpaca(alpaca_bar, "NVDA")

      assert result.open == Decimal.new("185.20")
      assert result.high == Decimal.new("185.60")
      assert result.low == Decimal.new("184.90")
      assert result.close == Decimal.new("185.45")
    end

    test "converts integer prices to Decimal" do
      alpaca_bar = %{
        timestamp: ~U[2024-11-15 09:30:00Z],
        open: 185,
        high: 186,
        low: 184,
        close: 185,
        volume: 2_300_000
      }

      result = Bar.from_alpaca(alpaca_bar, "GOOGL")

      assert result.open == Decimal.new(185)
      assert result.high == Decimal.new(186)
      assert result.low == Decimal.new(184)
      assert result.close == Decimal.new(185)
    end
  end

  describe "to_map/1" do
    test "converts Bar struct to map" do
      bar = %Bar{
        symbol: "AAPL",
        bar_time: ~U[2024-11-15 09:30:00Z],
        open: Decimal.new("185.20"),
        high: Decimal.new("185.60"),
        low: Decimal.new("184.90"),
        close: Decimal.new("185.45"),
        volume: 2_300_000,
        vwap: Decimal.new("185.32"),
        trade_count: 150
      }

      result = Bar.to_map(bar)

      assert is_map(result)
      assert result.symbol == "AAPL"
      assert result.bar_time == ~U[2024-11-15 09:30:00Z]
      assert result.open == Decimal.new("185.20")
    end
  end

  # Helper functions

  defp valid_bar_attrs do
    %{
      symbol: "AAPL",
      bar_time: ~U[2024-11-15 09:30:00Z],
      open: Decimal.new("185.20"),
      high: Decimal.new("185.60"),
      low: Decimal.new("184.90"),
      close: Decimal.new("185.45"),
      volume: 2_300_000
    }
  end
end
