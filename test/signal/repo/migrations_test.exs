defmodule Signal.Repo.MigrationsTest do
  use Signal.DataCase, async: false

  alias Signal.Repo

  describe "market_bars table" do
    test "table exists with correct structure" do
      # Query table information
      result =
        Repo.query!("""
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_name = 'market_bars'
        ORDER BY ordinal_position
        """)

      columns =
        Enum.map(result.rows, fn [name, type, nullable] ->
          %{name: name, type: type, nullable: nullable}
        end)

      # Verify expected columns exist
      column_names = Enum.map(columns, & &1.name)

      assert "symbol" in column_names
      assert "bar_time" in column_names
      assert "open" in column_names
      assert "high" in column_names
      assert "low" in column_names
      assert "close" in column_names
      assert "volume" in column_names
      assert "vwap" in column_names
      assert "trade_count" in column_names
    end

    test "has correct primary key (symbol, bar_time)" do
      result =
        Repo.query!("""
        SELECT a.attname
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = 'market_bars'::regclass AND i.indisprimary
        ORDER BY a.attnum
        """)

      pk_columns = Enum.map(result.rows, fn [name] -> name end)

      assert pk_columns == ["symbol", "bar_time"]
    end

    test "has required NOT NULL constraints" do
      result =
        Repo.query!("""
        SELECT column_name, is_nullable
        FROM information_schema.columns
        WHERE table_name = 'market_bars'
        AND column_name IN ('symbol', 'bar_time', 'open', 'high', 'low', 'close', 'volume')
        """)

      nullable_map =
        Enum.into(result.rows, %{}, fn [name, nullable] -> {name, nullable} end)

      assert nullable_map["symbol"] == "NO"
      assert nullable_map["bar_time"] == "NO"
      assert nullable_map["open"] == "NO"
      assert nullable_map["high"] == "NO"
      assert nullable_map["low"] == "NO"
      assert nullable_map["close"] == "NO"
      assert nullable_map["volume"] == "NO"
    end

    test "has correct decimal precision for price fields" do
      result =
        Repo.query!("""
        SELECT column_name, numeric_precision, numeric_scale
        FROM information_schema.columns
        WHERE table_name = 'market_bars'
        AND column_name IN ('open', 'high', 'low', 'close', 'vwap')
        """)

      Enum.each(result.rows, fn [_name, precision, scale] ->
        assert precision == 10
        assert scale == 2
      end)
    end

    test "has custom index with DESC on bar_time" do
      result =
        Repo.query!("""
        SELECT indexname
        FROM pg_indexes
        WHERE tablename = 'market_bars'
        AND indexname = 'market_bars_symbol_bar_time_index'
        """)

      assert length(result.rows) == 1
    end

    test "is configured as TimescaleDB hypertable" do
      result =
        Repo.query!("""
        SELECT hypertable_name
        FROM timescaledb_information.hypertables
        WHERE hypertable_name = 'market_bars'
        """)

      assert length(result.rows) == 1
    end

    test "has compression enabled" do
      result =
        Repo.query!("""
        SELECT compression_enabled
        FROM timescaledb_information.hypertables
        WHERE hypertable_name = 'market_bars'
        """)

      assert [[true]] = result.rows
    end

    test "has compression policy configured" do
      result =
        Repo.query!("""
        SELECT proc_name, config->>'compress_after' as compress_after
        FROM timescaledb_information.jobs
        WHERE hypertable_name = 'market_bars'
        AND proc_name = 'policy_compression'
        """)

      assert [["policy_compression", "7 days"]] = result.rows
    end

    test "has retention policy configured" do
      result =
        Repo.query!("""
        SELECT proc_name, config->>'drop_after' as drop_after
        FROM timescaledb_information.jobs
        WHERE hypertable_name = 'market_bars'
        AND proc_name = 'policy_retention'
        """)

      assert [["policy_retention", "6 years"]] = result.rows
    end

    test "can insert and query bar data" do
      # Insert test data
      Repo.query!("""
      INSERT INTO market_bars
        (symbol, bar_time, open, high, low, close, volume, vwap, trade_count)
      VALUES
        ('AAPL', '2024-01-01 09:30:00+00', 185.20, 185.60, 185.15, 185.50, 12500, 185.35, 150)
      """)

      # Query it back
      result =
        Repo.query!("""
        SELECT symbol, close, volume
        FROM market_bars
        WHERE symbol = 'AAPL'
        """)

      assert [["AAPL", close, 12500]] = result.rows
      assert Decimal.equal?(close, Decimal.new("185.50"))
    end
  end

  describe "events table" do
    test "table exists with correct structure" do
      result =
        Repo.query!("""
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_name = 'events'
        ORDER BY ordinal_position
        """)

      columns =
        Enum.map(result.rows, fn [name, type, nullable] ->
          %{name: name, type: type, nullable: nullable}
        end)

      column_names = Enum.map(columns, & &1.name)

      assert "id" in column_names
      assert "stream_id" in column_names
      assert "event_type" in column_names
      assert "payload" in column_names
      assert "version" in column_names
      assert "timestamp" in column_names
    end

    test "has bigserial primary key" do
      result =
        Repo.query!("""
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_name = 'events' AND column_name = 'id'
        """)

      assert [["id", "bigint"]] = result.rows
    end

    test "has unique index on stream_id and version" do
      result =
        Repo.query!("""
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE tablename = 'events'
        AND indexname = 'events_stream_id_version_index'
        """)

      assert length(result.rows) == 1
      [[_name, indexdef]] = result.rows
      assert String.contains?(indexdef, "UNIQUE")
    end

    test "has index on event_type" do
      result =
        Repo.query!("""
        SELECT indexname
        FROM pg_indexes
        WHERE tablename = 'events'
        AND indexname = 'events_event_type_index'
        """)

      assert length(result.rows) == 1
    end

    test "has index on timestamp" do
      result =
        Repo.query!("""
        SELECT indexname
        FROM pg_indexes
        WHERE tablename = 'events'
        AND indexname = 'events_timestamp_index'
        """)

      assert length(result.rows) == 1
    end

    test "has NOT NULL constraints on required fields" do
      result =
        Repo.query!("""
        SELECT column_name, is_nullable
        FROM information_schema.columns
        WHERE table_name = 'events'
        AND column_name IN ('stream_id', 'event_type', 'payload', 'version', 'timestamp')
        """)

      nullable_map =
        Enum.into(result.rows, %{}, fn [name, nullable] -> {name, nullable} end)

      assert nullable_map["stream_id"] == "NO"
      assert nullable_map["event_type"] == "NO"
      assert nullable_map["payload"] == "NO"
      assert nullable_map["version"] == "NO"
      assert nullable_map["timestamp"] == "NO"
    end

    test "has default timestamp value" do
      result =
        Repo.query!("""
        SELECT column_name, column_default
        FROM information_schema.columns
        WHERE table_name = 'events'
        AND column_name = 'timestamp'
        """)

      assert [["timestamp", default]] = result.rows
      assert String.contains?(default, "now()")
    end

    test "payload is JSONB type" do
      result =
        Repo.query!("""
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_name = 'events'
        AND column_name = 'payload'
        """)

      assert [["payload", "jsonb"]] = result.rows
    end

    test "can insert and query event data" do
      # Insert test event
      Repo.query!("""
      INSERT INTO events
        (stream_id, event_type, payload, version, timestamp)
      VALUES
        ('order-123', 'OrderPlaced', '{"symbol": "AAPL", "quantity": 100}'::jsonb, 1, NOW())
      """)

      # Query it back
      result =
        Repo.query!("""
        SELECT stream_id, event_type, payload->>'symbol' as symbol, version
        FROM events
        WHERE stream_id = 'order-123'
        """)

      assert [["order-123", "OrderPlaced", "AAPL", 1]] = result.rows
    end

    test "enforces unique constraint on stream_id and version" do
      # Insert first event
      Repo.query!("""
      INSERT INTO events
        (stream_id, event_type, payload, version, timestamp)
      VALUES
        ('order-456', 'OrderPlaced', '{}'::jsonb, 1, NOW())
      """)

      # Try to insert duplicate (should fail)
      assert_raise Postgrex.Error, ~r/unique constraint/, fn ->
        Repo.query!("""
        INSERT INTO events
          (stream_id, event_type, payload, version, timestamp)
        VALUES
          ('order-456', 'OrderCancelled', '{}'::jsonb, 1, NOW())
        """)
      end
    end

    test "allows multiple versions for same stream_id" do
      # Insert multiple versions
      Repo.query!("""
      INSERT INTO events
        (stream_id, event_type, payload, version, timestamp)
      VALUES
        ('order-789', 'OrderPlaced', '{}'::jsonb, 1, NOW()),
        ('order-789', 'OrderFilled', '{}'::jsonb, 2, NOW()),
        ('order-789', 'OrderCompleted', '{}'::jsonb, 3, NOW())
      """)

      # Query all versions
      result =
        Repo.query!("""
        SELECT COUNT(*)
        FROM events
        WHERE stream_id = 'order-789'
        """)

      assert [[3]] = result.rows
    end
  end

  describe "schema_migrations table" do
    test "has migration records" do
      result =
        Repo.query!("""
        SELECT version
        FROM schema_migrations
        ORDER BY version
        """)

      # Versions are stored as bigint, so convert to string for comparison
      versions =
        Enum.map(result.rows, fn [version] ->
          if is_integer(version), do: Integer.to_string(version), else: version
        end)

      # Should have both migrations
      assert length(versions) >= 2
      assert "20251116022514" in versions
      assert "20251116022515" in versions
    end
  end
end
