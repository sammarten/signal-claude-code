defmodule Signal.MarketData.Verifier do
  @moduledoc """
  Verifies data quality and identifies issues in historical bar data.

  Checks for:
  - OHLC relationship violations
  - Gaps in data during market hours
  - Duplicate bars
  - Coverage statistics
  """

  require Logger
  import Ecto.Query, warn: false
  alias Signal.Repo
  alias Signal.MarketData.Bar

  @type verification_report :: %{
          symbol: String.t(),
          total_bars: non_neg_integer(),
          date_range: {DateTime.t(), DateTime.t()} | nil,
          issues: [issue()],
          coverage: coverage_stats()
        }

  @type issue :: {:ohlc_violation, map()} | {:gaps, map()} | {:duplicate_bars, map()}

  @type coverage_stats :: %{
          expected_bars: non_neg_integer(),
          actual_bars: non_neg_integer(),
          coverage_pct: float()
        }

  @doc """
  Verifies data for one symbol.

  ## Parameters
    - symbol: String symbol (e.g., "AAPL")

  ## Returns
    - {:ok, report} where report contains statistics and issues

  ## Examples

      iex> verify_symbol("AAPL")
      {:ok, %{symbol: "AAPL", total_bars: 487234, ...}}
  """
  @spec verify_symbol(String.t()) :: {:ok, verification_report()}
  def verify_symbol(symbol) do
    Logger.info("[Verifier] Verifying data for #{symbol}...")

    # Get basic stats
    total_bars = count_bars(symbol)
    date_range = get_date_range(symbol)

    if total_bars == 0 do
      Logger.warning("[Verifier] #{symbol}: No data found")

      {:ok,
       %{
         symbol: symbol,
         total_bars: 0,
         date_range: nil,
         issues: [],
         coverage: %{expected_bars: 0, actual_bars: 0, coverage_pct: 0.0}
       }}
    else
      # Run checks
      ohlc_violations = check_ohlc_relationships(symbol)
      gaps_info = check_gaps(symbol, date_range)
      duplicate_info = check_duplicates(symbol)

      # Calculate coverage
      {start_dt, end_dt} = date_range
      coverage = calculate_coverage(total_bars, start_dt, end_dt)

      issues =
        [
          if(length(ohlc_violations) > 0,
            do:
              {:ohlc_violation,
               %{count: length(ohlc_violations), examples: Enum.take(ohlc_violations, 3)}},
            else: nil
          ),
          if(gaps_info.count > 0, do: {:gaps, gaps_info}, else: nil),
          if(duplicate_info.count > 0, do: {:duplicate_bars, duplicate_info}, else: nil)
        ]
        |> Enum.filter(&(&1 != nil))

      report = %{
        symbol: symbol,
        total_bars: total_bars,
        date_range: date_range,
        issues: issues,
        coverage: coverage
      }

      log_report(report)

      {:ok, report}
    end
  end

  @doc """
  Verifies all configured symbols.

  ## Returns
    - {:ok, [report]} - List of verification reports

  ## Examples

      iex> verify_all()
      {:ok, [%{symbol: "AAPL", ...}, %{symbol: "TSLA", ...}]}
  """
  @spec verify_all() :: {:ok, [verification_report()]}
  def verify_all do
    symbols =
      Application.get_env(:signal, :symbols, [])
      |> Enum.map(&Atom.to_string/1)

    Logger.info("[Verifier] Verifying #{length(symbols)} symbols...")

    reports =
      Enum.map(symbols, fn symbol ->
        {:ok, report} = verify_symbol(symbol)
        report
      end)

    # Summary
    total_issues =
      reports
      |> Enum.map(fn r -> length(r.issues) end)
      |> Enum.sum()

    avg_coverage =
      reports
      |> Enum.map(fn r -> r.coverage.coverage_pct end)
      |> Enum.sum()
      |> Kernel./(length(reports))
      |> Float.round(2)

    Logger.info(
      "[Verifier] Complete - #{total_issues} total issues found across all symbols, avg coverage: #{avg_coverage}%"
    )

    {:ok, reports}
  end

  # Private Functions

  defp count_bars(symbol) do
    from(b in Bar,
      where: b.symbol == ^symbol,
      select: count(b.symbol)
    )
    |> Repo.one()
  end

  defp get_date_range(symbol) do
    from(b in Bar,
      where: b.symbol == ^symbol,
      select: {min(b.bar_time), max(b.bar_time)}
    )
    |> Repo.one()
  end

  defp check_ohlc_relationships(symbol) do
    # Find bars where OHLC relationships are violated
    query = """
    SELECT symbol, bar_time, open, high, low, close
    FROM market_bars
    WHERE symbol = $1
      AND (
        high < open OR
        high < close OR
        high < low OR
        low > open OR
        low > close OR
        low > high
      )
    LIMIT 100
    """

    case Repo.query(query, [symbol]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [symbol, bar_time, open, high, low, close] ->
          %{
            symbol: symbol,
            bar_time: bar_time,
            open: open,
            high: high,
            low: low,
            close: close
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp check_gaps(symbol, {start_dt, end_dt}) do
    # Find gaps of more than 1 minute during market hours
    # This is a simplified check - a full implementation would:
    # 1. Filter to market hours only (9:30-16:00 ET)
    # 2. Exclude weekends
    # 3. Exclude market holidays
    # For now, we'll just look for gaps > 1 day

    query = """
    WITH bar_gaps AS (
      SELECT
        symbol,
        bar_time,
        LAG(bar_time) OVER (PARTITION BY symbol ORDER BY bar_time) as prev_bar_time,
        bar_time - LAG(bar_time) OVER (PARTITION BY symbol ORDER BY bar_time) as gap
      FROM market_bars
      WHERE symbol = $1
        AND bar_time >= $2
        AND bar_time <= $3
    )
    SELECT symbol, prev_bar_time, bar_time, gap
    FROM bar_gaps
    WHERE gap > INTERVAL '1 day'
    ORDER BY gap DESC
    LIMIT 20
    """

    case Repo.query(query, [symbol, start_dt, end_dt]) do
      {:ok, %{rows: rows}} ->
        gaps =
          Enum.map(rows, fn [symbol, prev_bar_time, bar_time, gap_interval] ->
            # Convert interval to minutes (approximate)
            %{
              symbol: symbol,
              gap_start: prev_bar_time,
              gap_end: bar_time,
              gap_interval: gap_interval
            }
          end)

        largest_gap = List.first(gaps)

        %{
          count: length(gaps),
          largest: largest_gap
        }

      {:error, _} ->
        %{count: 0, largest: nil}
    end
  end

  defp check_duplicates(symbol) do
    # With unique constraint on (symbol, bar_time), there shouldn't be duplicates
    # But we'll check just in case
    query = """
    SELECT symbol, bar_time, COUNT(*) as dup_count
    FROM market_bars
    WHERE symbol = $1
    GROUP BY symbol, bar_time
    HAVING COUNT(*) > 1
    LIMIT 10
    """

    case Repo.query(query, [symbol]) do
      {:ok, %{rows: rows}} ->
        duplicates =
          Enum.map(rows, fn [symbol, bar_time, count] ->
            %{symbol: symbol, bar_time: bar_time, count: count}
          end)

        %{
          count: length(duplicates),
          examples: duplicates
        }

      {:error, _} ->
        %{count: 0, examples: []}
    end
  end

  defp calculate_coverage(actual_bars, start_dt, end_dt) do
    # Estimate expected bars based on date range
    # 252 trading days/year * 390 minutes/day
    days_in_range = DateTime.diff(end_dt, start_dt, :day)
    # Rough estimate: ~65% of calendar days are trading days
    estimated_trading_days = (days_in_range * 0.65) |> trunc()
    expected_bars = estimated_trading_days * 390

    coverage_pct =
      if expected_bars > 0 do
        (actual_bars / expected_bars * 100) |> Float.round(2)
      else
        0.0
      end

    %{
      expected_bars: expected_bars,
      actual_bars: actual_bars,
      coverage_pct: coverage_pct
    }
  end

  defp log_report(report) do
    issue_count = length(report.issues)

    if issue_count == 0 do
      Logger.info(
        "[Verifier] #{report.symbol}: ✓ No issues found (#{report.total_bars} bars, #{report.coverage.coverage_pct}% coverage)"
      )
    else
      Logger.warning(
        "[Verifier] #{report.symbol}: #{issue_count} issue type(s) found (#{report.total_bars} bars, #{report.coverage.coverage_pct}% coverage)"
      )

      Enum.each(report.issues, fn
        {:ohlc_violation, info} ->
          Logger.warning("  - OHLC violations: #{info.count} bars")

        {:gaps, info} ->
          Logger.warning("  - Data gaps: #{info.count} gaps found")

        {:duplicate_bars, info} ->
          Logger.warning("  - Duplicate bars: #{info.count} duplicates")
      end)
    end
  end
end
