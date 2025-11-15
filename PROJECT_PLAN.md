# Signal Trading System - Revised Detailed Implementation Plan

## Project Context

You are building a real-time day trading system called "Signal" using Elixir/Phoenix with event sourcing architecture. The system streams market data from Alpaca Markets, performs technical analysis, generates trading signals, and executes trades.

**Current State:**
- Phoenix 1.7+ project created at `~/signal`
- TimescaleDB running in Docker on localhost:5433
- Phoenix configured to connect to TimescaleDB
- TimescaleDB extension enabled

**Architecture Principles:**
- Event sourcing for complete audit trail
- Event-driven via Phoenix.PubSub for loose coupling
- Bars (1-minute OHLCV) for strategy decisions
- Quotes (real-time bid/ask) for monitoring and execution
- ETS for fast in-memory state access
- Single WebSocket connection to Alpaca (multiplexed for 25 symbols)
- Clean, idiomatic Elixir - vertical slice architecture, not DDD aggregate ceremonies

**Target Symbols:**
- 10-20 tech stocks: AAPL, TSLA, NVDA, PLTR, GOOGL, MSFT, AMZN, META, etc.
- 3-5 index ETFs: SPY, QQQ, SMH, DIA, IWM

**Historical Data:** 5 years of 1-minute bars for backtesting

## Phase 0: AlpacaEx Library Creation

### Task 0.1: Create AlpacaEx Library Project

**Objective:** Create standalone Elixir library for Alpaca Markets API integration.

**Location:** Create new project at `~/alpaca_ex` (sibling to signal project)

**Requirements:**
- Create new Mix library project (not supervised application)
- Project name: `alpaca_ex`
- Module namespace: `AlpacaEx`
- No Phoenix, no Ecto - pure Elixir library
- Will be used as path dependency by Signal

**Command to create:**
```
cd ~
mix new alpaca_ex --module AlpacaEx
```

**Project structure:**
```
alpaca_ex/
├── lib/
│   ├── alpaca_ex.ex (main module)
│   ├── alpaca_ex/
│   │   ├── config.ex
│   │   ├── client.ex (REST API)
│   │   └── stream.ex (WebSocket)
├── test/
├── mix.exs
└── README.md
```

**Success Criteria:**
- New library project exists
- Compiles successfully
- Tests pass (default tests)
- Can be added as dependency

### Task 0.2: Configure AlpacaEx Dependencies

**Objective:** Add required dependencies to alpaca_ex library.

**Location:** `~/alpaca_ex/mix.exs`

**Dependencies to add:**
- `{:websockex, "~> 0.4.3"}` - WebSocket client
- `{:req, "~> 0.5"}` - HTTP client
- `{:jason, "~> 1.4"}` - JSON parsing
- `{:decimal, "~> 2.1"}` - Precise decimal math

**Configuration:**
- Elixir version: ~> 1.15
- Start permanent: false (it's a library, not an app)
- Description: "Elixir client for Alpaca Markets API - REST and WebSocket streaming"

**Success Criteria:**
- Dependencies install successfully
- mix deps.get completes
- mix compile succeeds

### Task 0.3: Create AlpacaEx.Config Module

**Objective:** Configuration management for Alpaca API credentials and endpoints.

**Location:** `~/alpaca_ex/lib/alpaca_ex/config.ex`

**Requirements:**
- Read configuration from application environment
- Support runtime configuration
- Provide validation
- Clear error messages when config missing

**Expected Configuration Format:**
```elixir
# In the consuming application's config
config :alpaca_ex,
  api_key: System.get_env("ALPACA_API_KEY"),
  api_secret: System.get_env("ALPACA_API_SECRET"),
  base_url: "https://paper-api.alpaca.markets",
  ws_url: "wss://stream.data.alpaca.markets/v2/iex"
```

**Public API:**
- `api_key!/0` - Get API key, raise if not configured
- `api_secret!/0` - Get API secret, raise if not configured
- `base_url/0` - Get REST API base URL with default
- `ws_url/0` - Get WebSocket URL with default
- `data_feed/0` - Extract feed from ws_url (iex/sip)
- `configured?/0` - Check if credentials exist
- `paper_trading?/0` - Check if using paper trading URL

**Defaults:**
- base_url: "https://paper-api.alpaca.markets"
- ws_url: "wss://stream.data.alpaca.markets/v2/iex"

**Success Criteria:**
- Can read config from application environment
- Raises informative error if credentials missing
- Returns correct URLs
- Helper functions work correctly

### Task 0.4: Create AlpacaEx.Client Module (REST API)

**Objective:** HTTP client for Alpaca REST API.

**Location:** `~/alpaca_ex/lib/alpaca_ex/client.ex`

**Requirements:**
- Use Req library for HTTP
- Authentication via headers (APCA-API-KEY-ID, APCA-API-SECRET-KEY)
- Handle pagination automatically
- Handle rate limiting (429 responses - sleep and retry)
- Parse responses to Elixir data structures
- Convert timestamps to DateTime
- Convert prices to Decimal
- Comprehensive error handling

**Public API - Market Data:**

`get_bars/2` - Get historical bars
- Parameters:
  - symbols: string or list of strings (e.g., "AAPL" or ["AAPL", "TSLA"])
  - opts: keyword list with:
    - timeframe: string (default "1Min")
    - start: DateTime (required)
    - end: DateTime (required)
    - limit: integer (optional, max 10000 per request)
    - adjustment: string (optional, "raw"/"split"/"dividend"/"all")
- Returns: `{:ok, %{symbol => [%{timestamp, open, high, low, close, volume, vwap, trade_count}]}}` or `{:error, reason}`
- Handles pagination automatically (Alpaca returns max 10,000 bars per request)
- Can request multiple symbols in one call

`get_latest_bar/1` - Get most recent bar for symbol
- Parameters: symbol string
- Returns: `{:ok, bar_map}` or `{:error, reason}`

`get_latest_quote/1` - Get most recent quote for symbol
- Parameters: symbol string
- Returns: `{:ok, %{bid_price, bid_size, ask_price, ask_size, timestamp}}` or `{:error, reason}`

`get_latest_trade/1` - Get most recent trade for symbol
- Parameters: symbol string
- Returns: `{:ok, %{price, size, timestamp}}` or `{:error, reason}`

**Public API - Account:**

`get_account/0` - Get account information
- Returns: `{:ok, %{account_number, status, buying_power, cash, portfolio_value, equity, ...}}` or `{:error, reason}`

`get_positions/0` - Get all positions
- Returns: `{:ok, [%{symbol, qty, avg_entry_price, current_price, market_value, unrealized_pl, ...}]}` or `{:error, reason}`

`get_position/1` - Get position for symbol
- Parameters: symbol string
- Returns: `{:ok, position_map}` or `{:error, reason}`

**Public API - Orders:**

`list_orders/1` - Get orders with filters
- Parameters: opts keyword list (status, limit, direction, symbols, etc.)
- Returns: `{:ok, [order_map]}` or `{:error, reason}`

`get_order/1` - Get specific order
- Parameters: order_id string
- Returns: `{:ok, order_map}` or `{:error, reason}`

`place_order/1` - Submit new order
- Parameters: map with required keys:
  - symbol: string
  - qty: integer (or notional for fractional shares)
  - side: "buy" or "sell"
  - type: "market", "limit", "stop", "stop_limit"
  - time_in_force: "day", "gtc", "ioc", "fok"
  - Optional: limit_price, stop_price, extended_hours, client_order_id
- Returns: `{:ok, order_map}` or `{:error, reason}`

`cancel_order/1` - Cancel order
- Parameters: order_id string
- Returns: `{:ok, %{}}` or `{:error, reason}`

`cancel_all_orders/0` - Cancel all open orders
- Returns: `{:ok, [order_map]}` or `{:error, reason}`

**Response Processing:**
- Parse JSON to maps
- Convert ISO8601 timestamp strings to DateTime structs
- Convert numeric strings to Decimal (prices) or integers (quantities)
- Normalize keys to atoms
- Handle nested structures (bars by symbol, etc.)

**Error Handling:**
- Network errors: return `{:error, :network_error, details}`
- 401: return `{:error, :unauthorized}`
- 403: return `{:error, :forbidden}`
- 404: return `{:error, :not_found}`
- 429: retry with exponential backoff, max 3 retries
- 500+: return `{:error, :server_error, details}`
- Invalid response: return `{:error, :invalid_response, details}`

**Pagination Handling:**
- Check for `next_page_token` in response
- Automatically fetch next page if exists
- Accumulate results
- Stop when no more pages
- Protect against infinite loops (max 100 pages)

**Success Criteria:**
- Can authenticate with Alpaca
- Can download historical bars for single symbol
- Can download bars for multiple symbols
- Handles pagination correctly
- Parses responses correctly (DateTime, Decimal)
- Retries on rate limits
- Returns properly typed data
- All error cases handled

### Task 0.5: Create AlpacaEx.Stream Module (WebSocket)

**Objective:** WebSocket client for real-time market data streaming.

**Location:** `~/alpaca_ex/lib/alpaca_ex/stream.ex`

**Requirements:**
- GenServer using WebSockex behavior
- Single persistent WebSocket connection
- Handle Alpaca's authentication and subscription protocol
- Process batched messages
- Automatic reconnection with exponential backoff
- Callback mechanism for message delivery (no hardcoded PubSub dependency)

**WebSocket Protocol Flow:**
1. Connect to ws_url
2. Receive: `[{"T":"success","msg":"connected"}]`
3. Send auth: `{"action":"auth","key":"KEY","secret":"SECRET"}`
4. Receive: `[{"T":"success","msg":"authenticated"}]`
5. Send subscribe: `{"action":"subscribe","bars":["AAPL"],"quotes":["AAPL"]}`
6. Receive: `[{"T":"subscription",...}]`
7. Receive market data: `[{"T":"q",...},{"T":"b",...}]`

**Message Types:**
- Control messages: `{"T":"success|error|subscription",...}`
- Quotes: `{"T":"q","S":"AAPL","bp":185.50,"bs":100,"ap":185.52,"as":200,"t":"2024-11-15T14:30:00Z",...}`
- Bars: `{"T":"b","S":"AAPL","o":185.20,"h":185.60,"l":184.90,"c":185.45,"v":2300000,"t":"2024-11-15T14:30:00Z","n":150,"vw":185.32}`
- Trades: `{"T":"t","S":"AAPL","p":185.50,"s":100,"t":"2024-11-15T14:30:00.123456Z",...}`
- Statuses: `{"T":"s","S":"AAPL","sc":"T","sm":"Trading",...}`

**GenServer State:**
- ws_conn: WebSocket connection reference
- status: :disconnected | :connecting | :connected | :authenticated | :subscribed
- subscriptions: %{bars: [...], quotes: [...], trades: [...], statuses: [...]}
- reconnect_attempt: integer
- callback_module: module that implements handle_message/2
- callback_state: any term passed to callbacks

**Public API:**

`start_link/1` - Start stream GenServer
- Parameters: keyword list with:
  - callback_module: module implementing handle_message/2
  - callback_state: initial state for callbacks (optional)
  - name: GenServer name (optional)
- Returns: `{:ok, pid}` or `{:error, reason}`

`subscribe/2` - Add subscriptions
- Parameters:
  - pid: GenServer pid or name
  - subscriptions: map like `%{bars: ["AAPL"], quotes: ["AAPL"]}`
- Returns: `:ok`

`unsubscribe/2` - Remove subscriptions
- Parameters:
  - pid: GenServer pid or name
  - subscriptions: map like `%{bars: ["AAPL"]}`
- Returns: `:ok`

`status/1` - Get connection status
- Parameters: pid or name
- Returns: :disconnected | :connected | :authenticated | :subscribed

`subscriptions/1` - Get current subscriptions
- Parameters: pid or name
- Returns: `%{bars: [...], quotes: [...], ...}`

**Callback Module Behavior:**

Consuming applications must implement:
```elixir
@callback handle_message(message :: map(), state :: any()) :: {:ok, new_state :: any()}
```

Messages delivered to callback:
- Quote: `%{type: :quote, symbol: "AAPL", bid_price: 185.50, bid_size: 100, ask_price: 185.52, ask_size: 200, timestamp: ~U[...]}`
- Bar: `%{type: :bar, symbol: "AAPL", open: 185.20, high: 185.60, low: 184.90, close: 185.45, volume: 2300000, timestamp: ~U[...], vwap: 185.32, trade_count: 150}`
- Trade: `%{type: :trade, symbol: "AAPL", price: 185.50, size: 100, timestamp: ~U[...]}`
- Status: `%{type: :status, symbol: "AAPL", status_code: "T", status_message: "Trading", ...}`
- Connection: `%{type: :connection, status: :connected | :disconnected | :reconnecting, attempt: 0}`

**Reconnection Logic:**
- Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, max 60s
- Reset backoff counter on successful connection
- Re-authenticate after reconnect
- Re-subscribe to all previous subscriptions
- Deliver connection status via callback

**Message Processing:**
- Messages arrive as JSON arrays: `[{msg1}, {msg2}, {msg3}]`
- Parse entire batch
- Process each message by type (T field)
- Convert to normalized map structure
- Deliver to callback module

**Error Handling:**
- WebSocket errors: log and reconnect
- Authentication failures: log and stop (bad credentials)
- Parse errors: log and skip message
- Callback errors: log but continue processing

**Success Criteria:**
- Connects to Alpaca successfully
- Authenticates correctly
- Subscribes to channels
- Receives and parses messages
- Delivers to callback module
- Reconnects automatically on disconnect
- Handles batched messages
- Processes control messages correctly

### Task 0.6: Create AlpacaEx Tests

**Objective:** Test suite for AlpacaEx library.

**Location:** `~/alpaca_ex/test/`

**Requirements:**

**Unit Tests:**
- Config module: test configuration reading and validation
- Client module: test request building, response parsing (use mocked HTTP)
- Stream module: test message parsing, state transitions (use mocked WebSocket)

**Integration Tests (optional, require credentials):**
- Mark with @tag :integration
- Test real API calls (account, latest bars, etc.)
- Test WebSocket connection (use test stream with FAKEPACA symbol)
- Skip by default (require --include integration flag)

**Test Helpers:**
- Mock HTTP responses from Alpaca
- Sample bar/quote/trade data
- WebSocket message fixtures

**Success Criteria:**
- Unit tests pass without credentials
- Integration tests pass with credentials
- Good test coverage (>80%)
- Tests are deterministic

### Task 0.7: Create AlpacaEx Documentation

**Objective:** Complete library documentation.

**Location:** `~/alpaca_ex/README.md`

**Content:**
- Library overview and features
- Installation instructions
- Configuration example
- Usage examples:
  - REST API (getting bars, placing orders)
  - WebSocket streaming (subscribing to data)
  - Callback module implementation
- API reference (link to hex docs)
- Testing instructions
- Contributing guidelines

**Also add:**
- Module docs (@moduledoc) for each module
- Function docs (@doc) for all public functions
- Type specs (@spec) for all public functions
- Usage examples in @doc

**Success Criteria:**
- README is comprehensive
- Examples are runnable
- All public APIs documented
- Can generate docs with `mix docs`

## Phase 1: Signal Project Setup

### Task 1.1: Add AlpacaEx Dependency to Signal

**Objective:** Configure Signal to use AlpacaEx library.

**Location:** `~/signal/mix.exs`

**Requirements:**
- Add alpaca_ex as path dependency
- Add tz library for timezone handling
- Add decimal if not already present

**Dependencies to add:**
```elixir
{:alpaca_ex, path: "../alpaca_ex"},
{:tz, "~> 0.26"},
{:decimal, "~> 2.1"}
```

**Success Criteria:**
- mix deps.get succeeds
- mix compile succeeds
- Can use AlpacaEx modules in Signal

### Task 1.2: Create Market Bars Hypertable Migration

**Objective:** Create TimescaleDB hypertable for storing 1-minute bar data.

**Location:** `~/signal/priv/repo/migrations/`

**Requirements:**
- Migration name: `create_market_bars`
- Table name: `market_bars`
- No auto-increment primary key - use composite key (symbol, bar_time)
- Convert to TimescaleDB hypertable partitioned on `bar_time` with 1-day chunks
- Enable compression on symbol with 7-day compression policy
- Add retention policy: keep 6 years of data (5 years historical + 1 year buffer)
- Index on (symbol, bar_time DESC) for efficient queries

**Schema:**
- `symbol` (string, not null) - Stock ticker
- `bar_time` (timestamptz, not null) - Bar timestamp from Alpaca
- `open` (decimal 10,2, not null) - Open price
- `high` (decimal 10,2, not null) - High price
- `low` (decimal 10,2, not null) - Low price
- `close` (decimal 10,2, not null) - Close price
- `volume` (bigint, not null) - Volume
- `vwap` (decimal 10,2, nullable) - Volume-weighted average price from Alpaca
- `trade_count` (integer, nullable) - Number of trades in bar from Alpaca

**Hypertable Configuration:**
- Chunk interval: 1 day
- Compression after: 7 days
- Retention: 6 years

**Success Criteria:**
- Migration runs without errors
- `SELECT * FROM timescaledb_information.hypertables;` shows market_bars
- Compression policy is active
- Retention policy is set
- Can insert and query sample data

### Task 1.3: Create Events Table Migration

**Objective:** Create event sourcing events table for domain events.

**Location:** `~/signal/priv/repo/migrations/`

**Requirements:**
- Migration name: `create_events`
- Table name: `events`
- Standard auto-increment primary key
- Unique constraint on (stream_id, version) for optimistic locking
- Indexes for efficient querying

**Schema:**
- `id` (bigserial, primary key)
- `stream_id` (string, not null) - Event stream identifier (e.g., "strategy:AAPL", "portfolio")
- `event_type` (string, not null) - Event type name (e.g., "SignalGenerated", "OrderPlaced")
- `payload` (jsonb, not null) - Event data
- `version` (integer, not null) - Stream version for optimistic locking
- `timestamp` (timestamptz, not null, default NOW()) - Event timestamp

**Indexes:**
- (stream_id, version) - unique, for reading stream in order
- (event_type) - for querying by event type
- (timestamp) - for time-based queries

**Success Criteria:**
- Migration runs without errors
- Can insert events
- Unique constraint prevents duplicate versions
- Indexes created correctly

### Task 1.4: Create BarCache ETS Module

**Objective:** In-memory ETS cache for latest bar and quote per symbol.

**Location:** `~/signal/lib/signal/bar_cache.ex`

**Requirements:**
- GenServer that creates and manages ETS table
- Table name: `:bar_cache`
- Table options: `:named_table, :public, read_concurrency: true`
- Key: symbol (atom)
- Value: map with %{last_bar: map, last_quote: map}

**Public API:**

`start_link/1` - Start GenServer
- Parameters: opts (ignored, for supervisor compatibility)
- Returns: `{:ok, pid}`

`get/1` - Get all cached data for symbol
- Parameters: symbol (atom)
- Returns: `{:ok, %{last_bar: map, last_quote: map}}` or `{:error, :not_found}`

`get_quote/1` - Get just latest quote
- Parameters: symbol (atom)
- Returns: map or nil

`get_bar/1` - Get just latest bar
- Parameters: symbol (atom)
- Returns: map or nil

`current_price/1` - Calculate current price
- Parameters: symbol (atom)
- Returns: Decimal (mid-point from quote) or Decimal (bar close) or nil
- Logic: If quote exists, use (bid + ask) / 2, else use bar close, else nil

`update_bar/2` - Update bar for symbol
- Parameters: symbol (atom), bar (map)
- Returns: :ok
- Creates entry if doesn't exist

`update_quote/2` - Update quote for symbol
- Parameters: symbol (atom), quote (map)
- Returns: :ok
- Creates entry if doesn't exist

`all_symbols/0` - List all cached symbols
- Returns: list of atoms

**Internal Functions:**
- `init/1` - Create ETS table, return {:ok, %{}}
- Helper to merge updates into existing data

**Success Criteria:**
- ETS table created on start
- Can store and retrieve data
- Multiple processes can read concurrently
- Updates are atomic
- current_price/1 correctly calculates mid-point

### Task 1.5: Create Alpaca Stream Handler Module

**Objective:** Implement AlpacaEx.Stream callback module for Signal.

**Location:** `~/signal/lib/signal/alpaca/stream_handler.ex`

**Requirements:**
- Implements callback for AlpacaEx.Stream
- Receives parsed messages from AlpacaEx
- Updates BarCache
- Publishes to Phoenix.PubSub
- Deduplicates quotes (skip if bid/ask unchanged)
- Logs message throughput

**Callback Implementation:**

`handle_message/2` - Process message from AlpacaEx
- Parameters:
  - message: normalized map from AlpacaEx
  - state: handler state (tracks previous quotes for dedup)
- Returns: `{:ok, new_state}`

**Message Processing:**

For quotes (type: :quote):
1. Check if bid_price/ask_price changed from previous quote for this symbol
2. If unchanged, skip (return state unchanged)
3. If changed:
   - Update BarCache.update_quote/2
   - Broadcast to "quotes:#{symbol}" PubSub topic
   - Update state with new quote for dedup
   - Increment quote counter

For bars (type: :bar):
1. Update BarCache.update_bar/2
2. Broadcast to "bars:#{symbol}" PubSub topic
3. Increment bar counter

For trades (type: :trade):
1. Broadcast to "trades:#{symbol}" PubSub topic (if anyone subscribed)
2. Increment trade counter

For statuses (type: :status):
1. Broadcast to "statuses:#{symbol}" PubSub topic
2. Log trading halts

For connection (type: :connection):
1. Broadcast to "alpaca:connection" PubSub topic
2. Log connection status changes

**State Structure:**
```elixir
%{
  last_quotes: %{AAPL: %{bid_price: 185.50, ask_price: 185.52}, ...},
  counters: %{quotes: 0, bars: 0, trades: 0, statuses: 0},
  last_log: DateTime.utc_now()
}
```

**Periodic Logging:**
- Every 60 seconds, log message counts
- Reset counters after logging

**PubSub Message Format:**
- Quote: `{:quote, symbol, quote_map}`
- Bar: `{:bar, symbol, bar_map}`
- Trade: `{:trade, symbol, trade_map}`
- Status: `{:status, symbol, status_map}`
- Connection: `{:connection, status, details}`

**Success Criteria:**
- Implements callback correctly
- Deduplicates unchanged quotes
- Updates BarCache
- Publishes to PubSub
- Logs throughput periodically
- Handles all message types

### Task 1.6: Create Alpaca Stream Supervisor

**Objective:** Supervisor to start AlpacaEx.Stream with Signal's handler.

**Location:** `~/signal/lib/signal/alpaca/stream_supervisor.ex`

**Requirements:**
- DynamicSupervisor or simple Supervisor
- Starts AlpacaEx.Stream with StreamHandler callback
- Configures initial subscriptions from application config
- Only starts if Alpaca credentials configured

**Child Spec:**
```elixir
{AlpacaEx.Stream, 
  callback_module: Signal.Alpaca.StreamHandler,
  callback_state: %{last_quotes: %{}, counters: %{}, last_log: DateTime.utc_now()},
  name: Signal.Alpaca.Stream
}
```

**Initial Subscriptions:**
- Read symbol list from Application.get_env(:signal, :symbols)
- Subscribe to bars and quotes for all symbols
- Subscribe to statuses for all symbols

**Conditional Start:**
- Check if AlpacaEx.Config.configured?() returns true
- If not configured, log warning and don't start
- Allows testing without credentials

**Success Criteria:**
- Starts AlpacaEx.Stream on application start
- Subscribes to configured symbols
- Connects to Alpaca WebSocket
- Skips gracefully if not configured

### Task 1.7: Update Application Supervision Tree

**Objective:** Add all new components to supervision tree.

**Location:** `~/signal/lib/signal/application.ex`

**Requirements:**
- Add children in correct order
- Handle conditional starts

**Children Order:**
1. SignalWeb.Telemetry
2. Signal.Repo
3. {DNSCluster, ...}
4. {Phoenix.PubSub, name: Signal.PubSub}
5. Signal.BarCache (NEW)
6. Signal.Alpaca.StreamSupervisor (NEW - conditional)
7. {Finch, name: Signal.Finch}
8. SignalWeb.Endpoint

**Conditional Start Example:**
```elixir
children = [
  # ... other children
  Signal.BarCache,
  # Conditionally start Alpaca stream
  if(alpaca_configured?(), do: Signal.Alpaca.StreamSupervisor, else: [])
] |> List.flatten()
```

**Success Criteria:**
- Application starts successfully
- BarCache is running
- Alpaca stream starts if configured
- Application handles missing config gracefully

### Task 1.8: Configure Alpaca Credentials

**Objective:** Set up environment-based configuration for Alpaca.

**Location:** `~/signal/config/dev.exs`, `~/signal/config/runtime.exs`

**Requirements:**

**In config/dev.exs:**
```elixir
# Configure AlpacaEx library
config :alpaca_ex,
  api_key: System.get_env("ALPACA_API_KEY"),
  api_secret: System.get_env("ALPACA_API_SECRET"),
  base_url: System.get_env("ALPACA_BASE_URL") || "https://paper-api.alpaca.markets",
  ws_url: System.get_env("ALPACA_WS_URL") || "wss://stream.data.alpaca.markets/v2/iex"

# Configure Signal app
config :signal,
  symbols: [
    # Tech stocks
    :AAPL, :TSLA, :NVDA, :PLTR, :GOOGL, :MSFT, :AMZN, :META,
    :AMD, :NFLX, :CRM, :ADBE,
    # Index ETFs
    :SPY, :QQQ, :SMH, :DIA, :IWM
  ],
  market_open: ~T[09:30:00],
  market_close: ~T[16:00:00],
  timezone: "America/New_York"
```

**In config/runtime.exs (for production):**
```elixir
if config_env() == :prod do
  config :alpaca_ex,
    api_key: System.fetch_env!("ALPACA_API_KEY"),
    api_secret: System.fetch_env!("ALPACA_API_SECRET"),
    base_url: System.get_env("ALPACA_BASE_URL", "https://paper-api.alpaca.markets"),
    ws_url: System.get_env("ALPACA_WS_URL", "wss://stream.data.alpaca.markets/v2/iex")
end
```

**Environment Variables:**
Create `~/signal/.env` (add to .gitignore):
```bash
export ALPACA_API_KEY="your_key_here"
export ALPACA_API_SECRET="your_secret_here"
export ALPACA_BASE_URL="https://paper-api.alpaca.markets"
export ALPACA_WS_URL="wss://stream.data.alpaca.markets/v2/iex"
```

**Update .gitignore:**
Add `.env` to gitignore

**Success Criteria:**
- Config reads from environment variables
- Application fails gracefully if credentials missing
- Can switch between paper and live easily
- Symbol list is configurable

## Phase 2: Historical Data Loading

### Task 2.1: Create Ecto Schema for Market Bar

**Objective:** Ecto schema for market_bars table.

**Location:** `~/signal/lib/signal/market_data/bar.ex`

**Requirements:**
- Schema for market_bars table
- No auto-increment ID (composite primary key)
- Ecto.Type for Decimal fields
- Timestamps in UTC

**Schema Definition:**
```elixir
schema "market_bars" do
  field :symbol, :string, primary_key: true
  field :bar_time, :utc_datetime_usec, primary_key: true
  field :open, :decimal
  field :high, :decimal
  field :low, :decimal
  field :close, :decimal
  field :volume, :integer
  field :vwap, :decimal
  field :trade_count, :integer
end
```

**Changeset:**
- Validate all required fields present
- Validate OHLC relationships (high >= open, high >= close, low <= open, low <= close)
- Validate volume >= 0
- Validate trade_count >= 0 if present

**Helper Functions:**
- `from_alpaca/1` - Convert AlpacaEx bar map to schema struct
- `to_map/1` - Convert schema to plain map

**Success Criteria:**
- Schema compiles
- Can insert bars via Ecto
- Validations work correctly
- Changeset handles Alpaca data

### Task 2.2: Create Historical Loader Module

**Objective:** Download and store historical bar data from Alpaca.

**Location:** `~/signal/lib/signal/market_data/historical_loader.ex`

**Requirements:**
- Use AlpacaEx.Client to fetch historical bars
- Store in market_bars table via Ecto
- Handle pagination (10,000 bar limit per request)
- Batch inserts for efficiency (1000 bars per insert)
- Check for existing data to avoid duplicates
- Progress tracking and logging
- Support date range queries

**Public API:**

`load_bars/3` - Load bars for symbols and date range
- Parameters:
  - symbols: list of strings or single string
  - start_date: Date or DateTime
  - end_date: Date or DateTime (default: today)
- Returns: `{:ok, %{symbol => count}}` or `{:error, reason}`
- Progress: Logs progress every 10,000 bars

`load_all/2` - Load bars for all configured symbols
- Parameters:
  - start_date: Date or DateTime
  - end_date: Date or DateTime (default: today)
- Returns: `{:ok, total_count}` or `{:error, reason}`

`check_coverage/2` - Check data coverage
- Parameters:
  - symbol: string
  - date_range: Date range
- Returns: `{:ok, %{bars_count: int, missing_days: [Date.t()], coverage_pct: float}}`

**Implementation Details:**

For each symbol:
1. Query existing data: `SELECT MIN(bar_time), MAX(bar_time), COUNT(*) FROM market_bars WHERE symbol = ?`
2. Determine missing ranges
3. For each missing range:
   - Call AlpacaEx.Client.get_bars with appropriate parameters
   - Handle pagination (accumulate results)
   - Convert to Bar schemas
   - Batch insert (1000 at a time using Ecto.Multi or Repo.insert_all)
   - Log progress
4. Return summary

**Optimization:**
- Multi.insert_all for batch inserts
- ON CONFLICT DO NOTHING for idempotency
- Parallel downloads for multiple symbols (Task.async_stream with max_concurrency: 5)
- Rate limit handling (AlpacaEx.Client handles this)

**Error Handling:**
- Network errors: retry up to 3 times with backoff
- Invalid data: log and skip that bar
- Database errors: stop and return error
- Partial success: return what was loaded

**Progress Logging:**
```
[HistoricalLoader] Loading AAPL from 2019-11-15 to 2024-11-15...
[HistoricalLoader] AAPL: Downloaded 50,000 / ~500,000 bars (10%)
[HistoricalLoader] AAPL: Inserted 50,000 bars
[HistoricalLoader] AAPL: Complete - 487,234 bars loaded
```

**Success Criteria:**
- Can download 5 years of data for one symbol
- Handles pagination correctly
- Batch inserts work efficiently
- Doesn't re-download existing data
- Logs progress clearly
- Works for all configured symbols

### Task 2.3: Create Mix Task for Data Loading

**Objective:** CLI task to load historical data easily.

**Location:** `~/signal/lib/mix/tasks/signal.load_data.ex`

**Requirements:**
- Mix task: `mix signal.load_data`
- Command-line options parsing
- Call HistoricalLoader
- Display progress and summary

**Options:**
- `--symbols AAPL,TSLA` - Comma-separated list (default: all configured)
- `--start-date 2019-11-15` - Start date in YYYY-MM-DD format (default: 5 years ago)
- `--end-date 2024-11-15` - End date in YYYY-MM-DD format (default: today)
- `--check-only` - Just check coverage, don't download

**Usage Examples:**
```bash
# Load all symbols for 5 years
mix signal.load_data

# Load specific symbols
mix signal.load_data --symbols AAPL,TSLA

# Load custom date range
mix signal.load_data --symbols AAPL --start-date 2020-01-01 --end-date 2020-12-31

# Check coverage without downloading
mix signal.load_data --check-only
```

**Output:**
```
Signal Historical Data Loader
=============================
Symbols: AAPL, TSLA, NVDA, ... (15 total)
Date Range: 2019-11-15 to 2024-11-15 (5 years)

Loading data...
[1/15] AAPL: 487,234 bars loaded
[2/15] TSLA: 456,123 bars loaded
...

Summary:
========
Total bars loaded: 6,234,567
Total time: 45 minutes
Average: 2,315 bars/second
```

**Implementation:**
- Parse command-line arguments
- Validate dates
- Get symbol list (from args or config)
- Start Repo if not started
- Call HistoricalLoader.load_all or load_bars
- Display results
- Handle errors gracefully

**Success Criteria:**
- Task runs from command line
- Parses options correctly
- Calls loader correctly
- Shows clear progress
- Displays summary
- Handles errors gracefully

### Task 2.4: Create Data Verification Module

**Objective:** Verify data quality and identify issues.

**Location:** `~/signal/lib/signal/market_data/verifier.ex`

**Requirements:**
- Check for data quality issues
- Report statistics
- Identify gaps in coverage

**Public API:**

`verify_symbol/1` - Verify data for one symbol
- Parameters: symbol string
- Returns: `{:ok, report_map}` or `{:error, reason}`

`verify_all/0` - Verify all configured symbols
- Returns: `{:ok, [report_map]}`

**Checks:**

1. **OHLC Relationships:**
   - high >= open, close, low
   - low <= open, close, high
   - Count violations

2. **Gaps in Data:**
   - Find missing minutes during market hours (9:30-16:00 ET on weekdays)
   - Exclude holidays (use tz library to determine market holidays)
   - Report gap count and largest gap

3. **Duplicate Bars:**
   - Check for duplicate (symbol, bar_time) pairs
   - Should be zero (unique constraint)

4. **Statistics:**
   - Total bars
   - Date range (min/max bar_time)
   - Average volume
   - Days with data vs expected days

**Report Format:**
```elixir
%{
  symbol: "AAPL",
  total_bars: 487_234,
  date_range: {~D[2019-11-15], ~D[2024-11-15]},
  issues: [
    {:ohlc_violation, count: 3, example: %{bar_time: ~U[...], ...}},
    {:gaps, count: 12, largest: {~D[2020-03-15], 390}},
    {:duplicate_bars, count: 0}
  ],
  coverage: %{
    expected_bars: 487_500,
    actual_bars: 487_234,
    coverage_pct: 99.95
  }
}
```

**Success Criteria:**
- Identifies OHLC violations
- Finds gaps in data
- Reports statistics accurately
- Clear output format
- Helps validate data integrity

## Phase 3: LiveView Dashboard

### Task 3.1: Create Market Data LiveView

**Objective:** Real-time dashboard showing live market data.

**Location:** `~/signal_web/live/market_live.ex`

**Requirements:**
- LiveView with real-time updates
- Subscribe to PubSub topics
- Display table of all symbols
- Connection status indicator
- Message throughput stats

**Mount Behavior:**
1. Get configured symbols list
2. Load initial data from BarCache for each symbol
3. Subscribe to PubSub topics:
   - "quotes:#{symbol}" for each symbol
   - "bars:#{symbol}" for each symbol
   - "alpaca:connection" for connection status
4. Set up initial assigns

**Assigns Structure:**
```elixir
%{
  symbols: [:AAPL, :TSLA, ...],
  symbol_data: %{
    AAPL: %{
      symbol: "AAPL",
      current_price: Decimal.new("185.50"),
      bid: Decimal.new("185.48"),
      ask: Decimal.new("185.52"),
      spread: Decimal.new("0.04"),
      last_bar: %{open: ..., high: ..., low: ..., close: ..., volume: ..., timestamp: ...},
      last_update: ~U[2024-11-15 14:30:00Z],
      price_change: :up  # or :down or :unchanged
    },
    TSLA: %{...},
    ...
  },
  connection_status: :connected,
  stats: %{
    quotes_per_sec: 145,
    bars_per_min: 25,
    uptime: "2h 34m"
  }
}
```

**Handle Info:**

For `{:quote, symbol, quote}`:
1. Get current data for symbol from assigns
2. Calculate new price (mid-point)
3. Determine price change direction (compare to previous)
4. Update assigns.symbol_data[symbol]
5. Render (Phoenix.LiveView handles efficient diff)

For `{:bar, symbol, bar}`:
1. Update assigns.symbol_data[symbol].last_bar
2. Render

For `{:connection, status, _details}`:
1. Update assigns.connection_status
2. Render

**Template Structure:**
- Header with connection status indicator
- System stats (message rates, uptime)
- Table with columns:
  - Symbol
  - Current Price (colored by change direction)
  - Bid/Ask/Spread
  - Last Bar (OHLCV)
  - Volume
  - Last Update (time ago)
- Auto-scroll for many symbols
- Responsive layout

**Styling:**
- Tailwind CSS
- Green for price increases
- Red for price decreases
- Gray for unchanged
- Monospace font for prices
- Status indicator: green dot (connected), red (disconnected), yellow (reconnecting)
- Table with zebra striping
- Fixed header (sticky)

**Performance:**
- Use `push_event` for minimal updates
- Debounce rapid updates (max 1 update per symbol per 100ms)
- Consider virtualized scrolling if many symbols

**Success Criteria:**
- Dashboard loads quickly
- Shows real-time price updates
- Connection status reflects reality
- Table is readable and well-formatted
- No lag with frequent updates
- Works on mobile and desktop

### Task 3.2: Add Dashboard Route

**Objective:** Route to market dashboard.

**Location:** `~/signal_web/router.ex`

**Requirements:**
- Add live route at "/"
- Use existing :browser pipeline
- Set page title

**Route:**
```elixir
scope "/", SignalWeb do
  pipe_through :browser

  live "/", MarketLive, :index
  # Other routes...
end
```

**Success Criteria:**
- Can access dashboard at http://localhost:4000/
- LiveView mounts successfully
- Page title shows "Market Data · Signal"

### Task 3.3: Create System Stats LiveView Component

**Objective:** Reusable component for system statistics.

**Location:** `~/signal_web/live/components/system_stats.ex`

**Requirements:**
- Function component showing system health
- Display:
  - WebSocket connection status
  - Message throughput (quotes/sec, bars/min)
  - Uptime
  - Active subscriptions count
  - Last message timestamp
- Color-coded health indicators

**Props:**
- connection_status: atom
- stats: map with rates and counts

**Renders:**
- Connection status badge (green/red/yellow)
- Grid of stat cards
- Icons for each stat (use Heroicons)

**Success Criteria:**
- Component is reusable
- Shows accurate stats
- Updates in real-time
- Good visual design

## Phase 4: Monitoring & Verification

### Task 4.1: Create System Monitor Module

**Objective:** Track system health metrics.

**Location:** `~/signal/lib/signal/monitor.ex`

**Requirements:**
- GenServer tracking metrics
- Periodic logging
- Expose metrics via API
- Detect anomalies

**Tracked Metrics:**
- Quote messages per second
- Bar messages per minute
- Trade messages per second (if subscribed)
- WebSocket connection uptime
- Last message timestamp per type
- Reconnection count
- Message processing errors

**GenServer State:**
```elixir
%{
  counters: %{quotes: 0, bars: 0, trades: 0, errors: 0},
  connection_status: :connected,
  connection_start: DateTime.utc_now(),
  last_message: %{quote: DateTime, bar: DateTime, trade: DateTime},
  reconnect_count: 0,
  window_start: DateTime.utc_now()
}
```

**Public API:**

`start_link/1` - Start monitor
- Returns: `{:ok, pid}`

`track_message/1` - Record message received
- Parameters: message type (:quote, :bar, :trade)
- Returns: :ok

`track_error/1` - Record error
- Parameters: error details
- Returns: :ok

`track_connection/1` - Update connection status
- Parameters: status (:connected, :disconnected, :reconnecting)
- Returns: :ok

`get_stats/0` - Get current statistics
- Returns: stats map

**Behavior:**
- Every 60 seconds:
  - Calculate rates (messages per second/minute)
  - Log summary
  - Publish stats to PubSub ("system:stats" topic)
  - Reset counters
  - Check for anomalies

**Anomaly Detection:**
- If quote rate = 0 for 60 seconds during market hours → log warning
- If bar rate = 0 for 5 minutes during market hours → log warning
- If reconnect count > 10 in 1 hour → log error
- If connection status = disconnected for > 5 minutes → alert

**Logging:**
```
[Monitor] Stats (60s window): quotes=8,234 (137/s), bars=1,485 (25/min), errors=0, uptime=2h34m
```

**Success Criteria:**
- Tracks metrics accurately
- Logs periodic summaries
- Detects connection issues
- Publishes to PubSub for dashboard
- Anomaly detection works

### Task 4.2: Add Monitoring to Dashboard

**Objective:** Display system metrics in LiveView.

**Location:** Update `~/signal_web/live/market_live.ex`

**Requirements:**
- Subscribe to "system:stats" PubSub topic
- Display system stats component
- Show health indicators

**Additional Assigns:**
```elixir
%{
  system_stats: %{
    quotes_per_sec: 137,
    bars_per_min: 25,
    uptime_seconds: 9240,
    last_quote: ~U[2024-11-15 14:30:45Z],
    last_bar: ~U[2024-11-15 14:30:00Z],
    health: :healthy  # or :degraded or :error
  }
}
```

**Health Calculation:**
- :healthy - all rates normal, connected
- :degraded - some rates low, or recently reconnected
- :error - disconnected or zero rates during market hours

**UI Updates:**
- Use SystemStats component
- Show at top of dashboard
- Color-coded health badge

**Success Criteria:**
- System stats display correctly
- Updates every 60 seconds
- Health status accurate
- Integrated with dashboard

### Task 4.3: Create Integration Tests

**Objective:** Test end-to-end data flow.

**Location:** `~/signal/test/signal/integration_test.exs`

**Requirements:**
- Test with Alpaca test stream (wss://stream.data.alpaca.markets/v2/test, symbol: FAKEPACA)
- Verify data flows correctly
- Test all components together

**Tests:**

1. **WebSocket Connection:**
   - Start AlpacaEx.Stream with test endpoint
   - Subscribe to FAKEPACA
   - Receive messages
   - Verify connection

2. **Message Flow:**
   - Receive quote message
   - Verify BarCache updated
   - Verify PubSub broadcast
   - Verify LiveView receives update

3. **Bar Storage:**
   - Create test bars
   - Insert into database
   - Query back
   - Verify integrity

4. **Historical Loader:**
   - Mock AlpacaEx.Client
   - Load test data
   - Verify database inserts
   - Check coverage

**Test Helpers:**
- Factory for creating test bars/quotes
- Mock AlpacaEx responses
- PubSub test helpers

**Success Criteria:**
- Integration tests pass
- End-to-end flow verified
- Can use for regression testing
- Tests are deterministic

## Phase 5: Documentation & Polish

### Task 5.1: Create AlpacaEx README

**Objective:** Comprehensive library documentation.

**Location:** `~/alpaca_ex/README.md`

**Content:**
- Overview and features
- Installation
- Configuration
- Usage examples (REST and WebSocket)
- API reference
- Testing
- Contributing

**Success Criteria:**
- README is complete
- Examples work
- Clear and professional

### Task 5.2: Create Signal README

**Objective:** Project documentation.

**Location:** `~/signal/README.md`

**Content:**
- Project overview
- Architecture diagram
- Setup instructions (Docker, env vars, database)
- Running the app
- Loading data
- Using the dashboard
- Development workflow
- Testing
- Roadmap (Phase 2+)

**Success Criteria:**
- Another dev can set up from README
- Clear and complete
- Includes troubleshooting

### Task 5.3: Add Module Documentation

**Objective:** @moduledoc and @doc for all modules.

**Location:** All modules in both projects

**Requirements:**
- Every module has @moduledoc
- Every public function has @doc and @spec
- Examples in docs where appropriate
- Can generate with `mix docs`

**Success Criteria:**
- All public APIs documented
- Hex docs can be generated
- Examples are accurate

## Implementation Order

Execute in this sequence:

1. **AlpacaEx Library (Phase 0)**
   - Task 0.1: Create project
   - Task 0.2: Add dependencies
   - Task 0.3: Config module
   - Task 0.4: REST client
   - Task 0.5: WebSocket client
   - Task 0.6: Tests
   - Task 0.7: Documentation

2. **Signal Setup (Phase 1)**
   - Task 1.1: Add alpaca_ex dependency
   - Task 1.2: Market bars migration
   - Task 1.3: Events table migration
   - Task 1.4: BarCache module
   - Task 1.5: Stream handler
   - Task 1.6: Stream supervisor
   - Task 1.7: Update supervision tree
   - Task 1.8: Configure credentials

3. **Historical Data (Phase 2)**
   - Task 2.1: Bar schema
   - Task 2.2: Historical loader
   - Task 2.3: Mix task
   - Task 2.4: Verifier

4. **Dashboard (Phase 3)**
   - Task 3.1: Market LiveView
   - Task 3.2: Routes
   - Task 3.3: System stats component

5. **Monitoring (Phase 4)**
   - Task 4.1: Monitor module
   - Task 4.2: Dashboard monitoring
   - Task 4.3: Integration tests

6. **Documentation (Phase 5)**
   - Task 5.1: AlpacaEx README
   - Task 5.2: Signal README
   - Task 5.3: Module docs

## Success Criteria for Phase 1 Completion

System should:
- ✅ Have standalone alpaca_ex library working
- ✅ Connect to Alpaca WebSocket and receive live data
- ✅ Display real-time prices in dashboard
- ✅ Store bars in TimescaleDB hypertable
- ✅ Load 5 years of historical data via Mix task
- ✅ Deduplicate unchanged quotes
- ✅ Monitor system health
- ✅ Handle reconnections gracefully
- ✅ Run stably for extended periods
- ✅ Have comprehensive documentation

## Notes

**Historical Data Volume:**
- 5 years × 252 trading days × 390 minutes/day = ~490,800 bars per symbol
- 15 symbols × 490,800 = ~7.4 million bars total
- At ~100 bytes/bar = ~740 MB uncompressed
- TimescaleDB compression will reduce this significantly
- Allow 2-4 hours for initial data load depending on network speed

**Code Quality:**
- Follow Elixir conventions
- Pattern matching over conditionals
- Tagged tuples for errors
- Pure functions where possible
- Comprehensive @spec and @doc
- Keep functions small (<20 lines ideal)
- Module organization: one clear purpose per module

**Testing:**
- Unit tests for pure functions
- Integration tests for external APIs
- Property tests where appropriate (use StreamData)
- Mock external dependencies
- Test error cases
- Aim for >80% coverage

This completes the detailed Phase 1 plan. Ready for Claude Code to execute!
