defmodule Signal.BarCacheTest do
  use ExUnit.Case, async: false

  alias Signal.BarCache

  setup do
    # BarCache is already started by the application supervisor
    # Clear the cache before each test to ensure isolation
    BarCache.clear()
    :ok
  end

  describe "get/1" do
    test "returns error when symbol not found" do
      assert {:error, :not_found} = BarCache.get(:UNKNOWN)
    end

    test "returns data after bar update" do
      bar = %{open: d("185.20"), high: d("185.60"), low: d("185.15"), close: d("185.50")}
      :ok = BarCache.update_bar(:AAPL, bar)

      assert {:ok, %{last_bar: ^bar, last_quote: nil}} = BarCache.get(:AAPL)
    end

    test "returns data after quote update" do
      quote = %{bid_price: d("185.48"), ask_price: d("185.52")}
      :ok = BarCache.update_quote(:AAPL, quote)

      assert {:ok, %{last_bar: nil, last_quote: ^quote}} = BarCache.get(:AAPL)
    end

    test "returns both bar and quote when both are updated" do
      bar = %{open: d("185.20"), close: d("185.50")}
      quote = %{bid_price: d("185.48"), ask_price: d("185.52")}

      :ok = BarCache.update_bar(:AAPL, bar)
      :ok = BarCache.update_quote(:AAPL, quote)

      assert {:ok, %{last_bar: ^bar, last_quote: ^quote}} = BarCache.get(:AAPL)
    end
  end

  describe "get_quote/1" do
    test "returns nil when symbol not found" do
      assert nil == BarCache.get_quote(:UNKNOWN)
    end

    test "returns quote when available" do
      quote = %{bid_price: d("185.48"), ask_price: d("185.52")}
      :ok = BarCache.update_quote(:AAPL, quote)

      assert ^quote = BarCache.get_quote(:AAPL)
    end

    test "returns nil when only bar is available" do
      bar = %{open: d("185.20"), close: d("185.50")}
      :ok = BarCache.update_bar(:AAPL, bar)

      assert nil == BarCache.get_quote(:AAPL)
    end
  end

  describe "get_bar/1" do
    test "returns nil when symbol not found" do
      assert nil == BarCache.get_bar(:UNKNOWN)
    end

    test "returns bar when available" do
      bar = %{open: d("185.20"), close: d("185.50")}
      :ok = BarCache.update_bar(:AAPL, bar)

      assert ^bar = BarCache.get_bar(:AAPL)
    end

    test "returns nil when only quote is available" do
      quote = %{bid_price: d("185.48"), ask_price: d("185.52")}
      :ok = BarCache.update_quote(:AAPL, quote)

      assert nil == BarCache.get_bar(:AAPL)
    end
  end

  describe "current_price/1" do
    test "returns nil when no data available" do
      assert nil == BarCache.current_price(:UNKNOWN)
    end

    test "returns quote mid-point when quote is available" do
      quote = %{bid_price: d("185.00"), ask_price: d("186.00")}
      :ok = BarCache.update_quote(:AAPL, quote)

      # Mid-point: (185.00 + 186.00) / 2 = 185.50
      assert d("185.50") == BarCache.current_price(:AAPL)
    end

    test "returns bar close when only bar is available" do
      bar = %{open: d("185.20"), close: d("185.50")}
      :ok = BarCache.update_bar(:AAPL, bar)

      assert d("185.50") == BarCache.current_price(:AAPL)
    end

    test "prefers quote mid-point over bar close when both available" do
      bar = %{open: d("185.20"), close: d("185.50")}
      quote = %{bid_price: d("186.00"), ask_price: d("187.00")}

      :ok = BarCache.update_bar(:AAPL, bar)
      :ok = BarCache.update_quote(:AAPL, quote)

      # Should return quote mid-point (186.50), not bar close (185.50)
      assert d("186.50") == BarCache.current_price(:AAPL)
    end

    test "handles quote with nil bid or ask" do
      quote = %{bid_price: nil, ask_price: d("185.52")}
      bar = %{open: d("185.20"), close: d("185.50")}

      :ok = BarCache.update_quote(:AAPL, quote)
      :ok = BarCache.update_bar(:AAPL, bar)

      # Should fall back to bar close when quote is incomplete
      assert d("185.50") == BarCache.current_price(:AAPL)
    end
  end

  describe "update_bar/2" do
    test "creates new entry when symbol doesn't exist" do
      bar = %{open: d("185.20"), close: d("185.50")}
      :ok = BarCache.update_bar(:AAPL, bar)

      assert {:ok, %{last_bar: ^bar, last_quote: nil}} = BarCache.get(:AAPL)
    end

    test "updates existing bar without affecting quote" do
      bar1 = %{open: d("185.20"), close: d("185.50")}
      quote = %{bid_price: d("185.48"), ask_price: d("185.52")}
      bar2 = %{open: d("186.00"), close: d("186.50")}

      :ok = BarCache.update_bar(:AAPL, bar1)
      :ok = BarCache.update_quote(:AAPL, quote)
      :ok = BarCache.update_bar(:AAPL, bar2)

      assert {:ok, %{last_bar: ^bar2, last_quote: ^quote}} = BarCache.get(:AAPL)
    end

    test "handles multiple symbols independently" do
      bar_aapl = %{open: d("185.20"), close: d("185.50")}
      bar_tsla = %{open: d("250.00"), close: d("255.00")}

      :ok = BarCache.update_bar(:AAPL, bar_aapl)
      :ok = BarCache.update_bar(:TSLA, bar_tsla)

      assert {:ok, %{last_bar: ^bar_aapl}} = BarCache.get(:AAPL)
      assert {:ok, %{last_bar: ^bar_tsla}} = BarCache.get(:TSLA)
    end
  end

  describe "update_quote/2" do
    test "creates new entry when symbol doesn't exist" do
      quote = %{bid_price: d("185.48"), ask_price: d("185.52")}
      :ok = BarCache.update_quote(:AAPL, quote)

      assert {:ok, %{last_bar: nil, last_quote: ^quote}} = BarCache.get(:AAPL)
    end

    test "updates existing quote without affecting bar" do
      bar = %{open: d("185.20"), close: d("185.50")}
      quote1 = %{bid_price: d("185.48"), ask_price: d("185.52")}
      quote2 = %{bid_price: d("186.00"), ask_price: d("186.04")}

      :ok = BarCache.update_bar(:AAPL, bar)
      :ok = BarCache.update_quote(:AAPL, quote1)
      :ok = BarCache.update_quote(:AAPL, quote2)

      assert {:ok, %{last_bar: ^bar, last_quote: ^quote2}} = BarCache.get(:AAPL)
    end

    test "handles multiple symbols independently" do
      quote_aapl = %{bid_price: d("185.48"), ask_price: d("185.52")}
      quote_tsla = %{bid_price: d("250.00"), ask_price: d("250.10")}

      :ok = BarCache.update_quote(:AAPL, quote_aapl)
      :ok = BarCache.update_quote(:TSLA, quote_tsla)

      assert {:ok, %{last_quote: ^quote_aapl}} = BarCache.get(:AAPL)
      assert {:ok, %{last_quote: ^quote_tsla}} = BarCache.get(:TSLA)
    end
  end

  describe "all_symbols/0" do
    test "returns empty list when cache is empty" do
      assert [] == BarCache.all_symbols()
    end

    test "returns all symbols after updates" do
      :ok = BarCache.update_bar(:AAPL, %{close: d("185.50")})
      :ok = BarCache.update_quote(:TSLA, %{bid_price: d("250.00"), ask_price: d("250.10")})
      :ok = BarCache.update_bar(:NVDA, %{close: d("500.00")})

      symbols = BarCache.all_symbols()
      assert length(symbols) == 3
      assert :AAPL in symbols
      assert :TSLA in symbols
      assert :NVDA in symbols
    end

    test "returns unique symbols even after multiple updates" do
      :ok = BarCache.update_bar(:AAPL, %{close: d("185.50")})
      :ok = BarCache.update_quote(:AAPL, %{bid_price: d("185.48"), ask_price: d("185.52")})
      :ok = BarCache.update_bar(:AAPL, %{close: d("186.00")})

      symbols = BarCache.all_symbols()
      assert [:AAPL] == symbols
    end
  end

  describe "concurrent access" do
    test "handles concurrent reads and writes" do
      # This tests ETS's concurrent read capability
      # Start with some data
      :ok = BarCache.update_bar(:AAPL, %{close: d("185.50")})

      # Spawn multiple readers
      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            BarCache.get(:AAPL)
          end)
        end

      # All reads should succeed
      results = Task.await_many(tasks)
      assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)
    end

    test "handles sequential writes correctly" do
      # Write multiple times from different processes
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            BarCache.update_bar(:AAPL, %{close: Decimal.new(i)})
          end)
        end

      Task.await_many(tasks)

      # Should have some final value (whichever write won the race)
      assert {:ok, %{last_bar: bar}} = BarCache.get(:AAPL)
      assert bar.close in Enum.map(1..10, &Decimal.new/1)
    end
  end

  # Helper function to create Decimal values
  defp d(string) when is_binary(string) do
    Decimal.new(string)
  end
end
