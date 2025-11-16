defmodule Signal.Alpaca.StreamHandlerTest do
  use ExUnit.Case, async: false

  alias Signal.Alpaca.StreamHandler
  alias Signal.BarCache

  setup do
    # BarCache is already started by the application supervisor
    # Subscribe to PubSub topics for testing
    Phoenix.PubSub.subscribe(Signal.PubSub, "quotes:AAPL")
    Phoenix.PubSub.subscribe(Signal.PubSub, "bars:AAPL")
    Phoenix.PubSub.subscribe(Signal.PubSub, "trades:AAPL")
    Phoenix.PubSub.subscribe(Signal.PubSub, "statuses:AAPL")
    Phoenix.PubSub.subscribe(Signal.PubSub, "alpaca:connection")

    # Ensure :AAPL atom exists for tests
    _ = :AAPL

    :ok
  end

  describe "handle_message/2 for quotes" do
    test "processes quote and updates BarCache" do
      quote = %{
        type: :quote,
        symbol: "AAPL",
        bid_price: d("185.48"),
        ask_price: d("185.52"),
        bid_size: 100,
        ask_size: 200
      }

      state = StreamHandler.init_state()
      assert {:ok, _new_state} = StreamHandler.handle_message(quote, state)

      # Verify BarCache was updated
      assert quote_data = BarCache.get_quote(:AAPL)
      assert quote_data.bid_price == d("185.48")
      assert quote_data.ask_price == d("185.52")
    end

    test "broadcasts quote to PubSub" do
      quote = %{
        type: :quote,
        symbol: "AAPL",
        bid_price: d("185.48"),
        ask_price: d("185.52"),
        bid_size: 100,
        ask_size: 200
      }

      state = StreamHandler.init_state()
      StreamHandler.handle_message(quote, state)

      # Verify broadcast
      assert_receive {:quote, :AAPL, received_quote}, 1000
      assert received_quote.bid_price == d("185.48")
    end

    test "deduplicates identical quotes" do
      quote = %{
        type: :quote,
        symbol: "AAPL",
        bid_price: d("185.48"),
        ask_price: d("185.52"),
        bid_size: 100,
        ask_size: 200
      }

      state = StreamHandler.init_state()

      # First quote should be processed
      {:ok, state2} = StreamHandler.handle_message(quote, state)
      assert_receive {:quote, :AAPL, _}, 100

      # Second identical quote should be skipped
      {:ok, _state3} = StreamHandler.handle_message(quote, state2)
      refute_receive {:quote, :AAPL, _}, 100
    end

    test "processes quote when bid price changes" do
      quote1 = %{
        type: :quote,
        symbol: "AAPL",
        bid_price: d("185.48"),
        ask_price: d("185.52"),
        bid_size: 100,
        ask_size: 200
      }

      quote2 = %{
        type: :quote,
        symbol: "AAPL",
        bid_price: d("185.50"),
        ask_price: d("185.52"),
        bid_size: 100,
        ask_size: 200
      }

      state = StreamHandler.init_state()

      {:ok, state2} = StreamHandler.handle_message(quote1, state)
      assert_receive {:quote, :AAPL, _}, 100

      {:ok, _state3} = StreamHandler.handle_message(quote2, state2)
      assert_receive {:quote, :AAPL, received_quote}, 100
      assert received_quote.bid_price == d("185.50")
    end

    test "updates counters for quotes" do
      quote = %{
        type: :quote,
        symbol: "AAPL",
        bid_price: d("185.48"),
        ask_price: d("185.52")
      }

      state = StreamHandler.init_state()

      {:ok, state2} = StreamHandler.handle_message(quote, state)
      assert state2.counters.quotes == 1

      # Change quote and send again
      quote2 = Map.put(quote, :bid_price, d("185.50"))
      {:ok, state3} = StreamHandler.handle_message(quote2, state2)
      assert state3.counters.quotes == 2
    end
  end

  describe "handle_message/2 for bars" do
    test "processes bar and updates BarCache" do
      bar = %{
        type: :bar,
        symbol: "AAPL",
        open: d("185.20"),
        high: d("185.60"),
        low: d("185.15"),
        close: d("185.50"),
        volume: 12500
      }

      state = StreamHandler.init_state()
      assert {:ok, _new_state} = StreamHandler.handle_message(bar, state)

      # Verify BarCache was updated
      assert bar_data = BarCache.get_bar(:AAPL)
      assert bar_data.close == d("185.50")
      assert bar_data.volume == 12500
    end

    test "broadcasts bar to PubSub" do
      bar = %{
        type: :bar,
        symbol: "AAPL",
        open: d("185.20"),
        close: d("185.50"),
        volume: 12500
      }

      state = StreamHandler.init_state()
      StreamHandler.handle_message(bar, state)

      # Verify broadcast
      assert_receive {:bar, :AAPL, received_bar}, 1000
      assert received_bar.close == d("185.50")
    end

    test "updates counters for bars" do
      bar = %{
        type: :bar,
        symbol: "AAPL",
        close: d("185.50"),
        volume: 12500
      }

      state = StreamHandler.init_state()

      {:ok, state2} = StreamHandler.handle_message(bar, state)
      assert state2.counters.bars == 1
    end
  end

  describe "handle_message/2 for trades" do
    test "broadcasts trade to PubSub" do
      trade = %{
        type: :trade,
        symbol: "AAPL",
        price: d("185.50"),
        size: 100
      }

      state = StreamHandler.init_state()
      StreamHandler.handle_message(trade, state)

      # Verify broadcast
      assert_receive {:trade, :AAPL, received_trade}, 1000
      assert received_trade.price == d("185.50")
      assert received_trade.size == 100
    end

    test "updates counters for trades" do
      trade = %{
        type: :trade,
        symbol: "AAPL",
        price: d("185.50"),
        size: 100
      }

      state = StreamHandler.init_state()

      {:ok, state2} = StreamHandler.handle_message(trade, state)
      assert state2.counters.trades == 1
    end
  end

  describe "handle_message/2 for status" do
    test "broadcasts status to PubSub" do
      status = %{
        type: :status,
        symbol: "AAPL",
        status_code: "T",
        status_message: "Trading"
      }

      state = StreamHandler.init_state()
      StreamHandler.handle_message(status, state)

      # Verify broadcast
      assert_receive {:status, :AAPL, received_status}, 1000
      assert received_status.status_code == "T"
    end

    test "updates counters for statuses" do
      status = %{
        type: :status,
        symbol: "AAPL",
        status_code: "T",
        status_message: "Trading"
      }

      state = StreamHandler.init_state()

      {:ok, state2} = StreamHandler.handle_message(status, state)
      assert state2.counters.statuses == 1
    end
  end

  describe "handle_message/2 for connection" do
    test "broadcasts connection status to PubSub" do
      connection = %{
        type: :connection,
        status: :connected
      }

      state = StreamHandler.init_state()
      StreamHandler.handle_message(connection, state)

      # Verify broadcast
      assert_receive {:connection, :connected, _}, 1000
    end

    test "does not update counters for connection messages" do
      connection = %{
        type: :connection,
        status: :connected
      }

      state = StreamHandler.init_state()

      {:ok, state2} = StreamHandler.handle_message(connection, state)
      assert state2.counters.quotes == 0
      assert state2.counters.bars == 0
      assert state2.counters.trades == 0
      assert state2.counters.statuses == 0
    end
  end

  describe "handle_message/2 for unknown messages" do
    test "ignores unknown message types gracefully" do
      unknown = %{
        type: :unknown_type,
        data: "some data"
      }

      state = StreamHandler.init_state()

      assert {:ok, ^state} = StreamHandler.handle_message(unknown, state)
    end
  end

  describe "init_state/0" do
    test "returns initialized state with empty counters" do
      state = StreamHandler.init_state()

      assert state.last_quotes == %{}
      assert state.counters == %{quotes: 0, bars: 0, trades: 0, statuses: 0}
      assert %DateTime{} = state.last_log
    end
  end

  describe "stats logging" do
    test "logs stats after interval has passed" do
      # This is a complex test - we'll verify the state updates correctly
      state = StreamHandler.init_state()

      # Manually set last_log to more than 60 seconds ago
      old_time = DateTime.add(DateTime.utc_now(), -61, :second)
      state = Map.put(state, :last_log, old_time)

      # Process a quote
      quote = %{
        type: :quote,
        symbol: "AAPL",
        bid_price: d("185.48"),
        ask_price: d("185.52")
      }

      {:ok, new_state} = StreamHandler.handle_message(quote, state)

      # After logging, counters should be reset
      assert new_state.counters == %{quotes: 0, bars: 0, trades: 0, statuses: 0}

      # last_log should be updated
      assert DateTime.diff(new_state.last_log, state.last_log, :second) > 60
    end

    test "does not log stats if interval has not passed" do
      state = StreamHandler.init_state()

      # Process a quote
      quote = %{
        type: :quote,
        symbol: "AAPL",
        bid_price: d("185.48"),
        ask_price: d("185.52")
      }

      {:ok, new_state} = StreamHandler.handle_message(quote, state)

      # Counters should not be reset
      assert new_state.counters.quotes == 1
    end
  end

  # Helper function to create Decimal values
  defp d(string) when is_binary(string) do
    Decimal.new(string)
  end
end
