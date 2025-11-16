defmodule Signal.Alpaca.StreamSupervisor do
  @moduledoc """
  Supervisor for the Alpaca WebSocket stream.

  Starts the AlpacaEx.Stream process with Signal's StreamHandler callback.
  Subscribes to configured symbols for real-time market data.

  Only starts if Alpaca credentials are configured, allowing the application
  to run in environments without API access (testing, development without keys).
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Check if Alpaca is configured
    unless alpaca_configured?() do
      Logger.warning("""
      [StreamSupervisor] Alpaca credentials not configured.
      Set ALPACA_API_KEY and ALPACA_API_SECRET environment variables to enable streaming.
      Running without real-time market data.
      """)

      # Return empty children list - supervisor starts but does nothing
      Supervisor.init([], strategy: :one_for_one)
    else
      Logger.info("[StreamSupervisor] Starting Alpaca WebSocket stream...")

      # Get configured symbols
      symbols = get_configured_symbols()

      # Build child spec for AlpacaEx.Stream
      children = [
        {AlpacaEx.Stream,
         callback_module: Signal.Alpaca.StreamHandler,
         callback_state: Signal.Alpaca.StreamHandler.init_state(),
         name: Signal.Alpaca.Stream}
      ]

      # Start supervisor with stream process
      {:ok, pid} = Supervisor.init(children, strategy: :one_for_one)

      # Subscribe to symbols after a short delay to allow connection
      Process.send_after(self(), :subscribe_symbols, 2000)

      # Store symbols in process state for later use
      Process.put(:symbols, symbols)

      {:ok, pid}
    end
  end

  @impl true
  def handle_info(:subscribe_symbols, state) do
    symbols = Process.get(:symbols, [])

    if symbols != [] do
      # Convert atom symbols to strings for AlpacaEx
      symbol_strings = Enum.map(symbols, &Atom.to_string/1)

      # Subscribe to bars and quotes for all symbols
      subscriptions = %{
        bars: symbol_strings,
        quotes: symbol_strings,
        statuses: symbol_strings
      }

      Logger.info("[StreamSupervisor] Subscribing to #{length(symbol_strings)} symbols: #{inspect(symbols)}")

      try do
        AlpacaEx.Stream.subscribe(Signal.Alpaca.Stream, subscriptions)
      rescue
        error ->
          Logger.error("[StreamSupervisor] Failed to subscribe: #{inspect(error)}")
      end
    end

    {:noreply, state}
  end

  ## Private Helpers

  defp alpaca_configured? do
    # Check if AlpacaEx.Config module exists and is configured
    Code.ensure_loaded?(AlpacaEx.Config) and
      AlpacaEx.Config.configured?()
  rescue
    _ -> false
  end

  defp get_configured_symbols do
    # Get symbols from application config, default to empty list
    Application.get_env(:signal, :symbols, [])
  end
end
