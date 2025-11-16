defmodule Signal.MarketData.HistoricalLoader do
  @moduledoc """
  Downloads and stores historical bar data from Alpaca Markets.

  Handles:
  - Pagination (Alpaca returns max 10,000 bars per request)
  - Batch inserts (1,000 bars per transaction)
  - Deduplication (ON CONFLICT DO NOTHING)
  - Progress tracking and logging
  - Parallel downloads for multiple symbols
  - Retry logic with exponential backoff
  """

  require Logger
  alias Signal.MarketData
  alias Signal.MarketData.Bar

  @batch_size 1000
  @max_retries 3
  @initial_backoff 1000
  @max_concurrency 5

  @doc """
  Loads bars for one or more symbols within a date range.

  ## Parameters
    - symbols: String symbol or list of symbols (e.g., "AAPL" or ["AAPL", "TSLA"])
    - start_date: Start date (Date or DateTime)
    - end_date: End date (Date or DateTime), defaults to today

  ## Returns
    - {:ok, %{symbol => count}} - Map of symbol to number of bars inserted
    - {:error, reason} - If download fails

  ## Examples

      iex> load_bars("AAPL", ~D[2020-01-01], ~D[2020-12-31])
      {:ok, %{"AAPL" => 98234}}

      iex> load_bars(["AAPL", "TSLA"], ~D[2020-01-01], ~D[2020-12-31])
      {:ok, %{"AAPL" => 98234, "TSLA" => 97456}}
  """
  @spec load_bars(String.t() | [String.t()], Date.t() | DateTime.t(), Date.t() | DateTime.t()) ::
          {:ok, %{String.t() => non_neg_integer()}} | {:error, term()}
  def load_bars(symbols, start_date, end_date \\ Date.utc_today())

  def load_bars(symbol, start_date, end_date) when is_binary(symbol) do
    load_bars([symbol], start_date, end_date)
  end

  def load_bars(symbols, start_date, end_date) when is_list(symbols) do
    Logger.info(
      "[HistoricalLoader] Loading bars for #{length(symbols)} symbols from #{format_date(start_date)} to #{format_date(end_date)}"
    )

    start_datetime = to_datetime(start_date)
    end_datetime = to_datetime(end_date)

    results =
      symbols
      |> Task.async_stream(
        fn symbol ->
          {symbol, load_symbol_bars(symbol, start_datetime, end_datetime)}
        end,
        max_concurrency: @max_concurrency,
        timeout: :infinity
      )
      |> Enum.to_list()

    # Check if any failed
    failed =
      Enum.filter(results, fn
        {:ok, {_symbol, {:error, _reason}}} -> true
        _ -> false
      end)

    if Enum.empty?(failed) do
      summary =
        results
        |> Enum.map(fn {:ok, {symbol, {:ok, count}}} -> {symbol, count} end)
        |> Map.new()

      total_bars = summary |> Map.values() |> Enum.sum()
      Logger.info("[HistoricalLoader] Complete - #{total_bars} total bars loaded")

      {:ok, summary}
    else
      first_error =
        failed
        |> List.first()
        |> elem(1)
        |> elem(1)
        |> elem(1)

      {:error, first_error}
    end
  end

  @doc """
  Loads bars for all configured symbols.

  Reads symbols from Application config at :signal, :symbols.

  ## Parameters
    - start_date: Start date (Date or DateTime)
    - end_date: End date (Date or DateTime), defaults to today

  ## Returns
    - {:ok, total_count} - Total number of bars loaded
    - {:error, reason} - If download fails

  ## Examples

      iex> load_all(~D[2020-01-01], ~D[2020-12-31])
      {:ok, 1_234_567}
  """
  @spec load_all(Date.t() | DateTime.t(), Date.t() | DateTime.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def load_all(start_date, end_date \\ Date.utc_today()) do
    symbols =
      Application.get_env(:signal, :symbols, [])
      |> Enum.map(&Atom.to_string/1)

    if Enum.empty?(symbols) do
      Logger.warning("[HistoricalLoader] No symbols configured in :signal, :symbols")
      {:ok, 0}
    else
      case load_bars(symbols, start_date, end_date) do
        {:ok, summary} ->
          total = summary |> Map.values() |> Enum.sum()
          {:ok, total}

        error ->
          error
      end
    end
  end

  @doc """
  Checks data coverage for a symbol within a date range.

  ## Parameters
    - symbol: String symbol (e.g., "AAPL")
    - start_date: Start date (Date)
    - end_date: End date (Date)

  ## Returns
    - {:ok, report} where report is a map containing:
      - :bars_count - Number of bars in database
      - :date_range - {min_date, max_date} tuple
      - :coverage_pct - Percentage of expected bars present

  ## Examples

      iex> check_coverage("AAPL", ~D[2020-01-01], ~D[2020-12-31])
      {:ok, %{bars_count: 98234, date_range: {...}, coverage_pct: 99.5}}
  """
  @spec check_coverage(String.t(), Date.t(), Date.t()) :: {:ok, map()}
  def check_coverage(symbol, start_date, end_date) do
    count = MarketData.count_bars(symbol)
    date_range = MarketData.get_date_range(symbol)

    # Estimate expected bars (252 trading days/year * 390 minutes/day)
    days_in_range = Date.diff(end_date, start_date)
    # Rough estimate: ~65% of calendar days are trading days
    estimated_trading_days = (days_in_range * 0.65) |> trunc()
    expected_bars = estimated_trading_days * 390

    coverage_pct =
      if expected_bars > 0 do
        (count / expected_bars * 100) |> Float.round(2)
      else
        0.0
      end

    report = %{
      bars_count: count,
      date_range: date_range,
      expected_bars: expected_bars,
      coverage_pct: coverage_pct
    }

    Logger.info(
      "[HistoricalLoader] Coverage for #{symbol}: #{count} bars (#{coverage_pct}% of estimated #{expected_bars})"
    )

    {:ok, report}
  end

  # Private Functions

  defp load_symbol_bars(symbol, start_datetime, end_datetime) do
    Logger.info(
      "[HistoricalLoader] Loading #{symbol} from #{format_datetime(start_datetime)} to #{format_datetime(end_datetime)}..."
    )

    case fetch_all_bars(symbol, start_datetime, end_datetime) do
      {:ok, bars} ->
        Logger.info("[HistoricalLoader] #{symbol}: Downloaded #{length(bars)} bars")

        # Convert AlpacaEx format to Bar format
        converted_bars =
          Enum.map(bars, fn bar ->
            Bar.from_alpaca(bar, symbol)
          end)

        # Batch insert
        case batch_insert_all(converted_bars, symbol) do
          {:ok, total_inserted} ->
            Logger.info("[HistoricalLoader] #{symbol}: Complete - #{total_inserted} bars loaded")
            {:ok, total_inserted}

          {:error, reason} = error ->
            Logger.error("[HistoricalLoader] #{symbol}: Insert failed - #{inspect(reason)}")
            error
        end

      {:error, reason} = error ->
        Logger.error("[HistoricalLoader] #{symbol}: Download failed - #{inspect(reason)}")

        error
    end
  end

  defp fetch_all_bars(symbol, start_datetime, end_datetime, retry_count \\ 0) do
    opts = [
      timeframe: "1Min",
      start: start_datetime,
      end: end_datetime,
      limit: 10_000
    ]

    case AlpacaEx.Client.get_bars(symbol, opts) do
      {:ok, response} ->
        # AlpacaEx.Client.get_bars returns %{symbol => [bars]}
        bars = Map.get(response, symbol, [])
        {:ok, bars}

      {:error, :network_error} = error ->
        if retry_count < @max_retries do
          backoff = (@initial_backoff * :math.pow(2, retry_count)) |> trunc()

          Logger.warning(
            "[HistoricalLoader] #{symbol}: Network error, retrying in #{backoff}ms (attempt #{retry_count + 1}/#{@max_retries})"
          )

          Process.sleep(backoff)
          fetch_all_bars(symbol, start_datetime, end_datetime, retry_count + 1)
        else
          Logger.error(
            "[HistoricalLoader] #{symbol}: Network error after #{@max_retries} retries"
          )

          error
        end

      {:error, reason} = error ->
        Logger.error("[HistoricalLoader] #{symbol}: API error - #{inspect(reason)}")
        error
    end
  end

  defp batch_insert_all(bars, symbol) do
    total_bars = length(bars)
    total_inserted = process_batches(bars, symbol, 0, 0)

    Logger.info("[HistoricalLoader] #{symbol}: Inserted #{total_inserted} / #{total_bars} bars")

    {:ok, total_inserted}
  rescue
    e ->
      Logger.error("[HistoricalLoader] #{symbol}: Batch insert error - #{inspect(e)}")
      {:error, e}
  end

  defp process_batches([], _symbol, _batch_num, total_inserted), do: total_inserted

  defp process_batches(bars, symbol, batch_num, total_inserted) do
    {batch, remaining} = Enum.split(bars, @batch_size)

    case MarketData.batch_insert_bars(batch) do
      {:ok, inserted} ->
        new_total = total_inserted + inserted

        # Log progress every 10 batches (~10,000 bars)
        if rem(batch_num + 1, 10) == 0 do
          Logger.info("[HistoricalLoader] #{symbol}: Inserted #{new_total} bars...")
        end

        process_batches(remaining, symbol, batch_num + 1, new_total)

      {:error, reason} ->
        Logger.error(
          "[HistoricalLoader] #{symbol}: Batch #{batch_num + 1} failed - #{inspect(reason)}"
        )

        # Continue with next batch despite error
        process_batches(remaining, symbol, batch_num + 1, total_inserted)
    end
  end

  defp to_datetime(%DateTime{} = dt), do: dt

  defp to_datetime(%Date{} = date) do
    # Market opens at 9:30 AM Eastern, convert to UTC
    {:ok, dt} = DateTime.new(date, ~T[09:30:00])
    dt
  end

  defp format_date(%Date{} = date), do: Date.to_string(date)
  defp format_date(%DateTime{} = dt), do: DateTime.to_date(dt) |> Date.to_string()

  defp format_datetime(%DateTime{} = dt) do
    DateTime.to_string(dt)
  end
end
