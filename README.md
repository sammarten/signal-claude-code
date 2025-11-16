# Signal - Real-Time Day Trading System

Signal is a real-time day trading system built with Elixir/Phoenix that streams market data from Alpaca Markets, performs technical analysis, generates trading signals, and executes trades.

## Features

- **Real-time Market Data**: WebSocket streaming of quotes and bars from Alpaca Markets
- **Historical Data**: Store and analyze 5 years of 1-minute OHLCV data
- **TimescaleDB Integration**: Efficient time-series data storage with compression
- **Event Sourcing**: Complete audit trail via events table
- **Live Dashboard**: Phoenix LiveView real-time monitoring
- **ETS Caching**: Fast in-memory access to latest market data
- **Paper Trading**: Safe testing with Alpaca's paper trading environment

## Architecture

### Technology Stack

- **Elixir 1.15+** - Functional programming language
- **Phoenix 1.8.1** - Web framework
- **Phoenix LiveView 1.1.0** - Real-time web interface
- **TimescaleDB (PostgreSQL 16)** - Time-series database
- **AlpacaEx** - Custom Elixir library for Alpaca Markets API

### Data Flow

```
Alpaca WebSocket → AlpacaEx.Stream → StreamHandler → BarCache (ETS)
                                   ↓
                           Phoenix.PubSub → LiveView Dashboard
                                   ↓
                           TimescaleDB (Historical Storage)
```

### Key Components

- **BarCache** - ETS table for fast access to latest quotes/bars
- **AlpacaEx.Stream** - WebSocket client with automatic reconnection
- **StreamHandler** - Processes market data and broadcasts to PubSub
- **TimescaleDB** - Hypertable with compression and retention policies

## Prerequisites

- **Elixir 1.15+** and **Erlang/OTP 26+**
- **PostgreSQL client tools**
- **Docker and Docker Compose** (for TimescaleDB)
- **Node.js** (for asset compilation)
- **Alpaca Markets account** (free paper trading account)

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/signal-claude-code.git
cd signal-claude-code
```

### 2. Install Dependencies

```bash
mix deps.get
cd assets && npm install && cd ..
```

### 3. Start TimescaleDB

```bash
docker-compose up -d
```

This starts TimescaleDB on **port 5433** (not the default 5432).

Verify it's running:
```bash
docker-compose ps
```

### 4. Configure Alpaca API Credentials

Create a `.env` file in the project root (copy from `.env.example`):

```bash
cp .env.example .env
```

Edit `.env` and add your Alpaca API credentials:

```bash
# Get these from: https://app.alpaca.markets/paper/dashboard/overview
ALPACA_API_KEY=your_key_here
ALPACA_API_SECRET=your_secret_here

# Paper trading URLs (recommended for development)
ALPACA_BASE_URL=https://paper-api.alpaca.markets
ALPACA_WS_URL=wss://stream.data.alpaca.markets/v2/iex
```

Load the environment variables:
```bash
source .env
```

**Note**: The application will run without credentials but won't receive real-time market data.

### 5. Create and Migrate Database

```bash
# Create the database
mix ecto.create

# Run migrations (creates hypertables)
mix ecto.migrate
```

This creates:
- `market_bars` - TimescaleDB hypertable for OHLCV data
- `events` - Event sourcing table for domain events

### 6. Start the Phoenix Server

```bash
# Start server
mix phx.server

# Or start with IEx console
iex -S mix phx.server
```

Visit **http://localhost:4000** to see the live dashboard.

## Configuration

### Monitored Symbols

Edit `config/dev.exs` to change the symbols being tracked:

```elixir
config :signal,
  symbols: [
    # Tech stocks
    :AAPL, :TSLA, :NVDA, :PLTR, :GOOGL, :MSFT,
    # Index ETFs
    :SPY, :QQQ, :SMH
  ]
```

### Market Hours

```elixir
config :signal,
  market_open: ~T[09:30:00],
  market_close: ~T[16:00:00],
  timezone: "America/New_York"
```

## Development Workflow

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/signal/bar_cache_test.exs

# Run with coverage
mix test --cover
```

### Code Quality Checks

```bash
# Run all pre-commit checks
mix precommit
```

This runs:
- Compilation with warnings as errors
- Code formatting
- Unused dependency cleanup
- Full test suite

### Database Operations

```bash
# Create new migration
mix ecto.gen.migration migration_name

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database (drop, create, migrate)
mix ecto.reset
```

### Checking TimescaleDB Status

Connect to the database:
```bash
docker exec -it signal_timescaledb psql -U postgres -d signal_dev
```

Check hypertables:
```sql
SELECT * FROM timescaledb_information.hypertables;
```

Check compression policies:
```sql
SELECT * FROM timescaledb_information.compression_settings;
```

## Project Structure

```
signal-claude-code/
├── lib/
│   ├── signal/
│   │   ├── application.ex        # OTP application supervisor
│   │   ├── repo.ex               # Ecto repository
│   │   ├── bar_cache.ex          # ETS cache for market data
│   │   └── alpaca/
│   │       ├── stream_handler.ex # WebSocket message handler
│   │       └── stream_supervisor.ex # Alpaca stream supervisor
│   ├── signal_web/
│   │   ├── endpoint.ex           # Phoenix endpoint
│   │   ├── router.ex             # Route definitions
│   │   └── live/                 # LiveView pages
├── priv/
│   └── repo/
│       └── migrations/           # Database migrations
├── config/
│   ├── dev.exs                   # Development config
│   ├── runtime.exs               # Production config
│   └── config.exs                # Base config
├── docker-compose.yml            # TimescaleDB setup
└── .env.example                  # Environment template
```

## AlpacaEx Library

Signal uses the [AlpacaEx](https://github.com/sammarten/alpaca_ex) library for Alpaca Markets integration. This library provides:

- **REST API Client** - Historical bars, account info, order management
- **WebSocket Streaming** - Real-time quotes, bars, trades
- **Automatic Reconnection** - Resilient connection handling
- **Callback Architecture** - Flexible message handling

## Troubleshooting

### TimescaleDB Connection Issues

If you see database connection errors:

1. Check TimescaleDB is running:
   ```bash
   docker-compose ps
   ```

2. Verify port 5433 is available:
   ```bash
   lsof -i :5433
   ```

3. Check Docker logs:
   ```bash
   docker-compose logs timescaledb
   ```

### Alpaca WebSocket Not Connecting

1. Verify API credentials are set:
   ```bash
   echo $ALPACA_API_KEY
   ```

2. Check application logs for connection errors
3. Verify you're using paper trading URLs
4. Check Alpaca API status: https://status.alpaca.markets/

### ETS Table Errors

If you see ETS-related errors, the BarCache may not have started:

```bash
# In IEx console
Signal.BarCache.all_symbols()
```

## Next Steps (Roadmap)

### Phase 2: Historical Data Loading
- [ ] Bar schema and context
- [ ] Historical data loader
- [ ] Mix task for bulk downloads
- [ ] Data verification tools

### Phase 3: LiveView Dashboard
- [ ] Market data LiveView
- [ ] Real-time price updates
- [ ] System stats component

### Phase 4: Monitoring
- [ ] System health monitoring
- [ ] Metrics collection
- [ ] Integration tests

### Phase 5: Trading Logic
- [ ] Technical indicators
- [ ] Strategy engine
- [ ] Signal generation
- [ ] Order execution

## Contributing

See [CLAUDE.md](CLAUDE.md) for AI assistant guidelines and project conventions.

## Resources

- **Alpaca Markets**: https://alpaca.markets/
- **TimescaleDB Docs**: https://docs.timescale.com/
- **Phoenix Framework**: https://www.phoenixframework.org/
- **Elixir**: https://elixir-lang.org/

## License

MIT License - See LICENSE file for details

## Support

For issues and questions:
- Check the troubleshooting section above
- Review the detailed guides in [CLAUDE.md](CLAUDE.md)
- Open an issue on GitHub
