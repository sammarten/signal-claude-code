defmodule Signal.Repo.Migrations.CreateMarketBars do
  use Ecto.Migration

  def up do
    # Create the market_bars table
    create table(:market_bars, primary_key: false) do
      add :symbol, :string, null: false, primary_key: true
      add :bar_time, :timestamptz, null: false, primary_key: true
      add :open, :decimal, precision: 10, scale: 2, null: false
      add :high, :decimal, precision: 10, scale: 2, null: false
      add :low, :decimal, precision: 10, scale: 2, null: false
      add :close, :decimal, precision: 10, scale: 2, null: false
      add :volume, :bigint, null: false
      add :vwap, :decimal, precision: 10, scale: 2
      add :trade_count, :integer
    end

    # Convert to TimescaleDB hypertable partitioned on bar_time with 1-day chunks
    execute("""
    SELECT create_hypertable('market_bars', 'bar_time', chunk_time_interval => INTERVAL '1 day');
    """)

    # Enable compression on symbol with 7-day compression policy
    execute("""
    ALTER TABLE market_bars SET (
      timescaledb.compress,
      timescaledb.compress_segmentby = 'symbol'
    );
    """)

    execute("""
    SELECT add_compression_policy('market_bars', INTERVAL '7 days');
    """)

    # Add retention policy: keep 6 years of data (5 years historical + 1 year buffer)
    execute("""
    SELECT add_retention_policy('market_bars', INTERVAL '6 years');
    """)

    # Create index for efficient queries (symbol, bar_time DESC)
    execute("""
    CREATE INDEX market_bars_symbol_bar_time_index ON market_bars (symbol, bar_time DESC);
    """)
  end

  def down do
    # Drop the index
    execute("DROP INDEX IF EXISTS market_bars_symbol_bar_time_index;")

    # Drop the table (this will also remove hypertable, compression, and retention policies)
    drop table(:market_bars)
  end
end
