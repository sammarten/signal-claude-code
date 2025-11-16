defmodule Signal.Alpaca.SubscriptionManager do
  @moduledoc """
  Manages symbol subscriptions to the Alpaca WebSocket stream.

  Listens for connection events and automatically subscribes to
  configured symbols when the connection is authenticated.
  """

  use GenServer
  require Logger

  @reconnect_delay_ms 2000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Subscribe to Alpaca connection events
    Phoenix.PubSub.subscribe(Signal.PubSub, "alpaca:connection")

    {:ok, %{subscribed: false, symbols: get_configured_symbols()}}
  end

  @impl true
  def handle_info({:connection, :authenticated, _details}, state) do
    # Only subscribe once per connection
    unless state.subscribed do
      schedule_subscription()
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:connection, :connected, _details}, state) do
    # Reset subscription flag on new connection
    {:noreply, %{state | subscribed: false}}
  end

  @impl true
  def handle_info({:connection, _status, _details}, state) do
    # Ignore other connection status updates
    {:noreply, state}
  end

  @impl true
  def handle_info(:perform_subscription, state) do
    if state.symbols != [] do
      subscribe_to_symbols(state.symbols)
      {:noreply, %{state | subscribed: true}}
    else
      Logger.info("[SubscriptionManager] No symbols configured for subscription")
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    # Catch-all for unknown messages
    Logger.debug("[SubscriptionManager] Received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Helpers

  defp schedule_subscription do
    Process.send_after(self(), :perform_subscription, @reconnect_delay_ms)
  end

  defp subscribe_to_symbols(symbols) do
    # Convert atom symbols to strings for AlpacaEx
    symbol_strings = Enum.map(symbols, &Atom.to_string/1)

    subscriptions = %{
      bars: symbol_strings,
      quotes: symbol_strings,
      statuses: symbol_strings
    }

    Logger.info(
      "[SubscriptionManager] Subscribing to #{length(symbol_strings)} symbols: #{inspect(symbols)}"
    )

    try do
      AlpacaEx.Stream.subscribe(Signal.Alpaca.Stream, subscriptions)
      Logger.info("[SubscriptionManager] Successfully subscribed to all symbols")
    catch
      :exit, {:noproc, _} ->
        # Stream process not available (expected in test/dev without Alpaca configured)
        Logger.debug(
          "[SubscriptionManager] Stream not available, will retry when connection is established"
        )

        # Retry after delay
        schedule_subscription()

      kind, error ->
        Logger.error(
          "[SubscriptionManager] Failed to subscribe (#{kind}): #{inspect(error)}"
        )

        # Retry after delay
        schedule_subscription()
    end
  end

  defp get_configured_symbols do
    Application.get_env(:signal, :symbols, [])
  end
end
