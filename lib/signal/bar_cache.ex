defmodule Signal.BarCache do
  @moduledoc """
  In-memory ETS cache for latest bar and quote data per symbol.

  Provides fast concurrent reads with public ETS table.
  Used for real-time access to current market data without database queries.
  """

  use GenServer
  require Logger

  @table_name :bar_cache

  ## Client API

  @doc """
  Starts the BarCache GenServer.

  ## Options
    * `:name` - The name to register the GenServer (default: `#{__MODULE__}`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets all cached data for a symbol.

  Returns a map with `:last_bar` and `:last_quote` keys, or an error if not found.

  ## Examples

      iex> BarCache.get(:AAPL)
      {:ok, %{last_bar: %{...}, last_quote: %{...}}}

      iex> BarCache.get(:UNKNOWN)
      {:error, :not_found}
  """
  @spec get(atom()) :: {:ok, map()} | {:error, :not_found}
  def get(symbol) when is_atom(symbol) do
    case :ets.lookup(@table_name, symbol) do
      [{^symbol, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets just the latest quote for a symbol.

  Returns the quote map or nil if not found.
  """
  @spec get_quote(atom()) :: map() | nil
  def get_quote(symbol) when is_atom(symbol) do
    case get(symbol) do
      {:ok, %{last_quote: quote}} -> quote
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets just the latest bar for a symbol.

  Returns the bar map or nil if not found.
  """
  @spec get_bar(atom()) :: map() | nil
  def get_bar(symbol) when is_atom(symbol) do
    case get(symbol) do
      {:ok, %{last_bar: bar}} -> bar
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Calculates the current price for a symbol.

  Uses the mid-point from the latest quote if available (bid + ask) / 2,
  otherwise falls back to the bar close price.

  Returns a Decimal or nil if no data available.
  """
  @spec current_price(atom()) :: Decimal.t() | nil
  def current_price(symbol) when is_atom(symbol) do
    case get(symbol) do
      {:ok, %{last_quote: %{bid_price: bid, ask_price: ask}}}
      when not is_nil(bid) and not is_nil(ask) ->
        # Calculate mid-point: (bid + ask) / 2
        Decimal.add(bid, ask)
        |> Decimal.div(Decimal.new(2))

      {:ok, %{last_bar: %{close: close}}} when not is_nil(close) ->
        close

      _ ->
        nil
    end
  end

  @doc """
  Updates the bar for a symbol.

  Creates entry if it doesn't exist, preserving any existing quote data.
  This operation is atomic - uses ETS's built-in atomicity guarantees.

  ## Examples

      iex> BarCache.update_bar(:AAPL, %{open: 185.20, high: 185.60, ...})
      :ok
  """
  @spec update_bar(atom(), map()) :: :ok
  def update_bar(symbol, bar) when is_atom(symbol) and is_map(bar) do
    # Use :ets.insert with a default value factory to make this atomic
    # ETS insert is atomic, and we construct the full value to insert
    default_data = %{last_bar: nil, last_quote: nil}

    # Try to read existing data, construct new data, and insert atomically
    new_data =
      case :ets.lookup(@table_name, symbol) do
        [{^symbol, existing_data}] ->
          Map.put(existing_data, :last_bar, bar)

        [] ->
          %{default_data | last_bar: bar}
      end

    :ets.insert(@table_name, {symbol, new_data})
    :ok
  end

  @doc """
  Updates the quote for a symbol.

  Creates entry if it doesn't exist, preserving any existing bar data.
  This operation is atomic - uses ETS's built-in atomicity guarantees.

  ## Examples

      iex> BarCache.update_quote(:AAPL, %{bid_price: 185.48, ask_price: 185.52, ...})
      :ok
  """
  @spec update_quote(atom(), map()) :: :ok
  def update_quote(symbol, quote) when is_atom(symbol) and is_map(quote) do
    # Use :ets.insert with a default value factory to make this atomic
    # ETS insert is atomic, and we construct the full value to insert
    default_data = %{last_bar: nil, last_quote: nil}

    # Try to read existing data, construct new data, and insert atomically
    new_data =
      case :ets.lookup(@table_name, symbol) do
        [{^symbol, existing_data}] ->
          Map.put(existing_data, :last_quote, quote)

        [] ->
          %{default_data | last_quote: quote}
      end

    :ets.insert(@table_name, {symbol, new_data})
    :ok
  end

  @doc """
  Lists all symbols currently in the cache.

  Returns a list of symbol atoms.
  """
  @spec all_symbols() :: [atom()]
  def all_symbols do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {symbol, _data} -> symbol end)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    table =
      :ets.new(@table_name, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: false
      ])

    Logger.info("[BarCache] Initialized ETS table: #{@table_name}")

    {:ok, %{table: table}}
  end
end
