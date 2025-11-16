defmodule Signal.Alpaca.StreamSupervisor do
  @moduledoc """
  Supervisor for the Alpaca WebSocket stream and subscription manager.

  Starts the AlpacaEx.Stream process with Signal's StreamHandler callback
  and the SubscriptionManager that handles symbol subscriptions.

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
    unless alpaca_configured?() do
      Logger.info("""
      [StreamSupervisor] Alpaca credentials not configured.
      Set ALPACA_API_KEY and ALPACA_API_SECRET environment variables to enable streaming.
      Running without real-time market data.
      """)

      # Return empty children list - supervisor starts but does nothing
      Supervisor.init([], strategy: :one_for_one)
    else
      Logger.info("[StreamSupervisor] Starting Alpaca WebSocket stream...")

      # Start both the stream and the subscription manager
      children = [
        # The WebSocket stream connection
        {AlpacaEx.Stream,
         callback_module: Signal.Alpaca.StreamHandler,
         callback_state: Signal.Alpaca.StreamHandler.init_state(),
         name: Signal.Alpaca.Stream},
        # The subscription manager (subscribes after connection is established)
        Signal.Alpaca.SubscriptionManager
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  ## Private Helpers

  defp alpaca_configured? do
    # Check if AlpacaEx.Config module exists and is configured
    Code.ensure_loaded?(AlpacaEx.Config) and
      AlpacaEx.Config.configured?()
  rescue
    _ -> false
  end
end
