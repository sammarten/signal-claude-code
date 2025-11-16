defmodule Signal.Alpaca.StreamHandler do
  @moduledoc """
  Callback handler for AlpacaEx.Stream.

  Receives parsed market data messages from AlpacaEx, processes them,
  updates the BarCache, and broadcasts to Phoenix.PubSub.

  Implements quote deduplication to avoid unnecessary updates when
  bid/ask prices haven't changed.
  """

  require Logger

  @behaviour AlpacaEx.Stream.Callback

  # Configuration
  @log_interval_seconds 60

  @doc """
  Handles incoming messages from the Alpaca WebSocket stream.

  Processes quotes, bars, trades, statuses, and connection events.
  Updates BarCache and broadcasts to PubSub for LiveView consumption.

  ## Message Types
    * `:quote` - Real-time bid/ask quotes
    * `:bar` - Completed 1-minute bars
    * `:trade` - Individual trades
    * `:status` - Trading status changes (halts, etc.)
    * `:connection` - WebSocket connection status
  """
  @impl true
  def handle_message(message, state)

  # Handle quote messages
  def handle_message(%{type: :quote, symbol: symbol} = quote, state) do
    symbol_atom = safe_symbol_to_atom(symbol)

    # Check for deduplication
    last_quotes = Map.get(state, :last_quotes, %{})
    last_quote = Map.get(last_quotes, symbol_atom)

    should_process? =
      is_nil(last_quote) or
      quote.bid_price != last_quote.bid_price or
      quote.ask_price != last_quote.ask_price

    if should_process? do
      # Update BarCache
      Signal.BarCache.update_quote(symbol_atom, quote)

      # Broadcast to PubSub
      Phoenix.PubSub.broadcast(
        Signal.PubSub,
        "quotes:#{symbol}",
        {:quote, symbol_atom, quote}
      )

      # Update state with new quote for deduplication
      new_last_quotes = Map.put(last_quotes, symbol_atom, quote)
      new_counters = increment_counter(state, :quotes)
      new_state = state
                  |> Map.put(:last_quotes, new_last_quotes)
                  |> Map.put(:counters, new_counters)

      # Check if we should log stats
      maybe_log_stats(new_state)
    else
      {:ok, state}
    end
  end

  # Handle bar messages
  def handle_message(%{type: :bar, symbol: symbol} = bar, state) do
    symbol_atom = safe_symbol_to_atom(symbol)

    # Update BarCache
    Signal.BarCache.update_bar(symbol_atom, bar)

    # Broadcast to PubSub
    Phoenix.PubSub.broadcast(
      Signal.PubSub,
      "bars:#{symbol}",
      {:bar, symbol_atom, bar}
    )

    # Update counters
    new_counters = increment_counter(state, :bars)
    new_state = Map.put(state, :counters, new_counters)

    maybe_log_stats(new_state)
  end

  # Handle trade messages
  def handle_message(%{type: :trade, symbol: symbol} = trade, state) do
    symbol_atom = safe_symbol_to_atom(symbol)

    # Broadcast to PubSub (no caching needed for individual trades)
    Phoenix.PubSub.broadcast(
      Signal.PubSub,
      "trades:#{symbol}",
      {:trade, symbol_atom, trade}
    )

    # Update counters
    new_counters = increment_counter(state, :trades)
    new_state = Map.put(state, :counters, new_counters)

    maybe_log_stats(new_state)
  end

  # Handle status messages (trading halts, etc.)
  def handle_message(%{type: :status, symbol: symbol} = status, state) do
    symbol_atom = safe_symbol_to_atom(symbol)

    # Log trading halts
    if status.status_code != "T" do
      Logger.warning("[StreamHandler] Trading status change for #{symbol}: #{status.status_message}")
    end

    # Broadcast to PubSub
    Phoenix.PubSub.broadcast(
      Signal.PubSub,
      "statuses:#{symbol}",
      {:status, symbol_atom, status}
    )

    # Update counters
    new_counters = increment_counter(state, :statuses)
    new_state = Map.put(state, :counters, new_counters)

    maybe_log_stats(new_state)
  end

  # Handle connection status messages
  def handle_message(%{type: :connection, status: status} = message, state) do
    Logger.info("[StreamHandler] Connection status: #{status}")

    # Broadcast to PubSub
    Phoenix.PubSub.broadcast(
      Signal.PubSub,
      "alpaca:connection",
      {:connection, status, message}
    )

    {:ok, state}
  end

  # Handle unknown message types
  def handle_message(message, state) do
    Logger.debug("[StreamHandler] Received unknown message type: #{inspect(message)}")
    {:ok, state}
  end

  ## Private Helpers

  @doc false
  defp safe_symbol_to_atom(symbol) when is_binary(symbol) do
    # Use String.to_existing_atom/1 to prevent atom table exhaustion
    # This will raise ArgumentError if the symbol isn't already an atom,
    # which is desired behavior - we only accept configured symbols
    String.to_existing_atom(symbol)
  rescue
    ArgumentError ->
      Logger.warning("[StreamHandler] Received data for unconfigured symbol: #{symbol}")
      reraise ArgumentError, __STACKTRACE__
  end

  defp increment_counter(state, counter_type) do
    counters = Map.get(state, :counters, %{quotes: 0, bars: 0, trades: 0, statuses: 0})
    current_count = Map.get(counters, counter_type, 0)
    Map.put(counters, counter_type, current_count + 1)
  end

  defp maybe_log_stats(state) do
    last_log = Map.get(state, :last_log, DateTime.utc_now())
    now = DateTime.utc_now()
    seconds_since_log = DateTime.diff(now, last_log, :second)

    if seconds_since_log >= @log_interval_seconds do
      counters = Map.get(state, :counters, %{quotes: 0, bars: 0, trades: 0, statuses: 0})

      Logger.info("""
      [StreamHandler] Stats (60s window):
        - Quotes: #{counters.quotes}
        - Bars: #{counters.bars}
        - Trades: #{counters.trades}
        - Statuses: #{counters.statuses}
      """)

      # Reset counters and update last_log
      new_state = state
                  |> Map.put(:counters, %{quotes: 0, bars: 0, trades: 0, statuses: 0})
                  |> Map.put(:last_log, now)

      {:ok, new_state}
    else
      {:ok, state}
    end
  end

  @doc """
  Initializes the handler state.

  Called when the AlpacaEx.Stream starts with the initial callback_state.
  """
  @spec init_state() :: map()
  def init_state do
    %{
      last_quotes: %{},
      counters: %{quotes: 0, bars: 0, trades: 0, statuses: 0},
      last_log: DateTime.utc_now()
    }
  end
end
