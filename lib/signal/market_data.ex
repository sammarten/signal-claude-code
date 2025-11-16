defmodule Signal.MarketData do
  @moduledoc """
  Market data context for bars, quotes, and symbols.

  Handles historical bar data storage, retrieval, and verification.
  """

  import Ecto.Query, warn: false
  alias Signal.Repo
  alias Signal.MarketData.Bar

  @doc """
  Gets bars for a symbol within a date range.

  ## Parameters
    - symbol: String symbol (e.g., "AAPL")
    - start_datetime: Start of range (DateTime)
    - end_datetime: End of range (DateTime)

  ## Returns
    - List of Bar structs ordered by bar_time ASC

  ## Examples

      iex> Signal.MarketData.list_bars("AAPL", ~U[2024-01-01 09:30:00Z], ~U[2024-01-01 16:00:00Z])
      [%Bar{}, ...]
  """
  @spec list_bars(String.t(), DateTime.t(), DateTime.t()) :: [Bar.t()]
  def list_bars(symbol, start_datetime, end_datetime) do
    from(b in Bar,
      where: b.symbol == ^symbol,
      where: b.bar_time >= ^start_datetime,
      where: b.bar_time <= ^end_datetime,
      order_by: [asc: b.bar_time]
    )
    |> Repo.all()
  end

  @doc """
  Gets the latest bar for a symbol.

  ## Parameters
    - symbol: String symbol (e.g., "AAPL")

  ## Returns
    - Bar struct or nil if not found

  ## Examples

      iex> Signal.MarketData.get_latest_bar("AAPL")
      %Bar{symbol: "AAPL", ...}
  """
  @spec get_latest_bar(String.t()) :: Bar.t() | nil
  def get_latest_bar(symbol) do
    from(b in Bar,
      where: b.symbol == ^symbol,
      order_by: [desc: b.bar_time],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets the date range of available data for a symbol.

  ## Parameters
    - symbol: String symbol (e.g., "AAPL")

  ## Returns
    - Tuple of {min_datetime, max_datetime} or nil if no data

  ## Examples

      iex> Signal.MarketData.get_date_range("AAPL")
      {~U[2019-11-15 09:30:00Z], ~U[2024-11-15 16:00:00Z]}
  """
  @spec get_date_range(String.t()) :: {DateTime.t(), DateTime.t()} | nil
  def get_date_range(symbol) do
    from(b in Bar,
      where: b.symbol == ^symbol,
      select: {min(b.bar_time), max(b.bar_time)}
    )
    |> Repo.one()
    |> case do
      {nil, nil} -> nil
      range -> range
    end
  end

  @doc """
  Counts bars for a symbol.

  ## Parameters
    - symbol: String symbol (e.g., "AAPL")

  ## Returns
    - Integer count of bars

  ## Examples

      iex> Signal.MarketData.count_bars("AAPL")
      487234
  """
  @spec count_bars(String.t()) :: non_neg_integer()
  def count_bars(symbol) do
    from(b in Bar,
      where: b.symbol == ^symbol,
      select: count(b.symbol)
    )
    |> Repo.one()
  end

  @doc """
  Creates a bar.

  ## Parameters
    - attrs: Map of bar attributes

  ## Returns
    - {:ok, %Bar{}} on success
    - {:error, %Ecto.Changeset{}} on failure

  ## Examples

      iex> create_bar(%{symbol: "AAPL", bar_time: ~U[...], open: 185.20, ...})
      {:ok, %Bar{}}
  """
  @spec create_bar(map()) :: {:ok, Bar.t()} | {:error, Ecto.Changeset.t()}
  def create_bar(attrs \\ %{}) do
    %Bar{}
    |> Bar.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Batch inserts bars efficiently.

  Uses Repo.insert_all with ON CONFLICT DO NOTHING for idempotency.

  ## Parameters
    - bars: List of bar attribute maps

  ## Returns
    - {:ok, count} where count is number of inserted rows
    - {:error, reason} on failure

  ## Examples

      iex> batch_insert_bars([%{symbol: "AAPL", ...}, ...])
      {:ok, 1000}
  """
  @spec batch_insert_bars([map()]) :: {:ok, non_neg_integer()} | {:error, term()}
  def batch_insert_bars(bars) when is_list(bars) do
    # Convert DateTime to UTC if needed and prepare for insert_all
    prepared_bars =
      Enum.map(bars, fn bar ->
        %{
          symbol: bar.symbol,
          bar_time: bar.bar_time,
          open: bar.open,
          high: bar.high,
          low: bar.low,
          close: bar.close,
          volume: bar.volume,
          vwap: bar[:vwap],
          trade_count: bar[:trade_count]
        }
      end)

    try do
      {count, _} =
        Repo.insert_all(
          Bar,
          prepared_bars,
          on_conflict: :nothing,
          conflict_target: [:symbol, :bar_time]
        )

      {:ok, count}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Deletes all bars for a symbol.

  ## Parameters
    - symbol: String symbol (e.g., "AAPL")

  ## Returns
    - {:ok, count} where count is number of deleted rows
  """
  @spec delete_bars(String.t()) :: {:ok, non_neg_integer()}
  def delete_bars(symbol) do
    {count, _} =
      from(b in Bar, where: b.symbol == ^symbol)
      |> Repo.delete_all()

    {:ok, count}
  end
end
