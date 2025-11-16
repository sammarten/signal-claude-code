defmodule Mix.Tasks.Signal.LoadData do
  @moduledoc """
  Load historical market data from Alpaca Markets.

  ## Usage

      mix signal.load_data [options]

  ## Options

      --symbols AAPL,TSLA    Comma-separated list of symbols (default: all configured)
      --start-date 2019-11-15  Start date in YYYY-MM-DD format (default: 5 years ago)
      --end-date 2024-11-15    End date in YYYY-MM-DD format (default: today)
      --check-only           Only check coverage, don't download

  ## Examples

      # Load all symbols for 5 years
      mix signal.load_data

      # Load specific symbols
      mix signal.load_data --symbols AAPL,TSLA

      # Load custom date range
      mix signal.load_data --symbols AAPL --start-date 2020-01-01 --end-date 2020-12-31

      # Check coverage without downloading
      mix signal.load_data --check-only
  """

  use Mix.Task
  require Logger
  alias Signal.MarketData.HistoricalLoader

  @shortdoc "Load historical market data from Alpaca"

  @default_years_back 5

  @impl Mix.Task
  def run(args) do
    # Parse command-line arguments
    {opts, _remaining, _invalid} =
      OptionParser.parse(args,
        strict: [
          symbols: :string,
          start_date: :string,
          end_date: :string,
          check_only: :boolean
        ]
      )

    # Start the application (needed for Repo)
    Mix.Task.run("app.start")

    # Print header
    print_header()

    # Parse options
    symbols = parse_symbols(opts[:symbols])
    start_date = parse_date(opts[:start_date], :start)
    end_date = parse_date(opts[:end_date], :end)
    check_only = Keyword.get(opts, :check_only, false)

    # Validate Alpaca configuration
    unless AlpacaEx.Config.configured?() do
      Mix.shell().error("""

      Error: Alpaca API credentials not configured.

      Please set the following environment variables:
        - ALPACA_API_KEY
        - ALPACA_API_SECRET

      Or configure in config/dev.exs:
        config :alpaca_ex,
          api_key: "your_key",
          api_secret: "your_secret"
      """)

      exit({:shutdown, 1})
    end

    # Print configuration
    print_config(symbols, start_date, end_date, check_only)

    # Execute task
    if check_only do
      check_coverage(symbols, start_date, end_date)
    else
      load_data(symbols, start_date, end_date)
    end
  end

  # Private Functions

  defp print_header do
    Mix.shell().info("""

    Signal Historical Data Loader
    =============================
    """)
  end

  defp print_config(symbols, start_date, end_date, check_only) do
    mode = if check_only, do: "Coverage Check", else: "Data Loading"
    symbol_count = length(symbols)

    days = Date.diff(end_date, start_date)
    years = (days / 365.25) |> Float.round(1)

    Mix.shell().info("""
    Mode:        #{mode}
    Symbols:     #{Enum.join(symbols, ", ")} (#{symbol_count} total)
    Date Range:  #{start_date} to #{end_date} (#{years} years, #{days} days)

    """)
  end

  defp parse_symbols(nil) do
    # Use configured symbols
    Application.get_env(:signal, :symbols, [])
    |> Enum.map(&Atom.to_string/1)
  end

  defp parse_symbols(symbols_string) do
    symbols_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.upcase/1)
  end

  defp parse_date(nil, :start) do
    # Default: 5 years ago from today
    Date.utc_today()
    |> Date.add(-365 * @default_years_back)
  end

  defp parse_date(nil, :end) do
    # Default: today
    Date.utc_today()
  end

  defp parse_date(date_string, _type) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        date

      {:error, _} ->
        Mix.shell().error("Invalid date format: #{date_string}. Use YYYY-MM-DD.")
        exit({:shutdown, 1})
    end
  end

  defp check_coverage(symbols, start_date, end_date) do
    Mix.shell().info("Checking coverage...\n")

    reports =
      Enum.map(symbols, fn symbol ->
        {:ok, report} = HistoricalLoader.check_coverage(symbol, start_date, end_date)
        {symbol, report}
      end)

    # Print coverage table
    print_coverage_table(reports)
    print_coverage_summary(reports)
  end

  defp load_data(symbols, start_date, end_date) do
    Mix.shell().info("Loading data...\n")

    start_time = System.monotonic_time(:second)

    case HistoricalLoader.load_bars(symbols, start_date, end_date) do
      {:ok, summary} ->
        end_time = System.monotonic_time(:second)
        duration = end_time - start_time

        print_load_summary(summary, duration)

      {:error, reason} ->
        Mix.shell().error("\nError: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp print_coverage_table(reports) do
    Mix.shell().info(
      String.pad_trailing("Symbol", 10) <> String.pad_trailing("Bars", 15) <> "Coverage"
    )

    Mix.shell().info(String.duplicate("-", 45))

    Enum.each(reports, fn {symbol, report} ->
      symbol_str = String.pad_trailing(symbol, 10)
      bars_str = String.pad_trailing(format_number(report.bars_count), 15)
      coverage_str = "#{report.coverage_pct}%"

      Mix.shell().info(symbol_str <> bars_str <> coverage_str)
    end)

    Mix.shell().info("")
  end

  defp print_coverage_summary(reports) do
    total_bars =
      reports
      |> Enum.map(fn {_symbol, report} -> report.bars_count end)
      |> Enum.sum()

    avg_coverage =
      reports
      |> Enum.map(fn {_symbol, report} -> report.coverage_pct end)
      |> Enum.sum()
      |> Kernel./(length(reports))
      |> Float.round(2)

    Mix.shell().info("""
    Summary:
    ========
    Total bars: #{format_number(total_bars)}
    Average coverage: #{avg_coverage}%
    """)
  end

  defp print_load_summary(summary, duration) do
    total_bars = summary |> Map.values() |> Enum.sum()
    bars_per_second = if duration > 0, do: (total_bars / duration) |> trunc(), else: 0

    Mix.shell().info("\n" <> String.pad_trailing("Symbol", 10) <> "Bars Loaded")
    Mix.shell().info(String.duplicate("-", 30))

    summary
    |> Enum.sort()
    |> Enum.each(fn {symbol, count} ->
      symbol_str = String.pad_trailing(symbol, 10)
      Mix.shell().info(symbol_str <> format_number(count))
    end)

    Mix.shell().info("""

    Summary:
    ========
    Total bars loaded: #{format_number(total_bars)}
    Total time: #{format_duration(duration)}
    Average: #{format_number(bars_per_second)} bars/second
    """)
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_duration(seconds) when seconds < 60 do
    "#{seconds} seconds"
  end

  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end

  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    remaining_minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{remaining_minutes}m"
  end
end
