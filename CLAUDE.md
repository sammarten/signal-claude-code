# CLAUDE.md - AI Assistant Guide for Signal Trading System

## Project Overview

**Signal** is a real-time day trading system built with Elixir/Phoenix that streams market data from Alpaca Markets, performs technical analysis, generates trading signals, and executes trades. This is a greenfield project currently in early development stages.

### Project Goals
- Stream real-time market data (quotes and bars) from Alpaca Markets
- Store historical bar data (5 years of 1-minute OHLCV data) in TimescaleDB
- Perform technical analysis and generate trading signals
- Execute automated trades based on signals
- Provide a real-time LiveView dashboard for monitoring

### Current State
- Phoenix 1.7+ project initialized
- TimescaleDB configured via Docker (localhost:5433)
- Basic Phoenix structure in place
- **No migrations yet** - database schema is planned but not implemented
- **No AlpacaEx library yet** - will be created as a separate Elixir library
- Project follows detailed implementation plan (see PROJECT_PLAN.md)

## Architecture & Technology Stack

### Core Technologies
- **Elixir 1.15+** - Functional programming language
- **Phoenix 1.8.1** - Web framework
- **Phoenix LiveView 1.1.0** - Real-time web interface
- **Ecto 3.13** - Database wrapper and query language
- **TimescaleDB (PostgreSQL 16)** - Time-series database for market data
- **Bandit 1.5** - HTTP server adapter

### Architecture Principles
1. **Event Sourcing** - Complete audit trail via events table
2. **Event-Driven** - Phoenix.PubSub for loose coupling between components
3. **ETS Caching** - Fast in-memory access to latest market data
4. **Single WebSocket** - One connection to Alpaca, multiplexed for 25 symbols
5. **Vertical Slice Architecture** - Organized by feature, not technical layers
6. **Idiomatic Elixir** - Pattern matching, immutability, supervised processes

### Data Flow
```
Alpaca WebSocket → AlpacaEx.Stream → StreamHandler → BarCache (ETS)
                                   ↓
                           Phoenix.PubSub → LiveView Dashboard
                                   ↓
                           TimescaleDB (Historical Storage)
```

### Target Symbols
- **Tech Stocks (10-20)**: AAPL, TSLA, NVDA, PLTR, GOOGL, MSFT, AMZN, META, AMD, NFLX, CRM, ADBE
- **Index ETFs (3-5)**: SPY, QQQ, SMH, DIA, IWM

## Directory Structure

```
signal-claude-code/
├── assets/                    # Frontend assets
│   ├── css/                  # Stylesheets (Tailwind CSS v4)
│   │   └── app.css          # Main CSS file
│   ├── js/                   # JavaScript files
│   │   └── app.js           # Main JS entry point
│   ├── vendor/              # Third-party assets
│   └── tsconfig.json        # TypeScript configuration
├── config/                   # Application configuration
│   ├── config.exs           # Base config
│   ├── dev.exs              # Development config (DB: port 5433)
│   ├── test.exs             # Test config
│   ├── prod.exs             # Production config
│   └── runtime.exs          # Runtime config
├── lib/
│   ├── signal/              # Core business logic
│   │   ├── application.ex   # OTP application supervisor
│   │   ├── repo.ex          # Ecto repository
│   │   └── mailer.ex        # Email functionality
│   ├── signal_web/          # Web layer
│   │   ├── components/      # Reusable UI components
│   │   │   ├── core_components.ex
│   │   │   └── layouts.ex
│   │   ├── controllers/     # HTTP controllers
│   │   ├── router.ex        # Route definitions
│   │   ├── endpoint.ex      # Phoenix endpoint
│   │   └── telemetry.ex     # Metrics and monitoring
│   ├── signal.ex            # Main module
│   └── signal_web.ex        # Web module
├── priv/
│   ├── repo/
│   │   ├── migrations/      # Database migrations (empty - to be created)
│   │   └── seeds.exs        # Database seeds
│   ├── static/              # Static assets
│   └── gettext/             # Internationalization
├── test/                     # Test files
│   ├── signal_web/
│   ├── support/
│   └── test_helper.exs
├── .formatter.exs           # Code formatter config
├── .gitignore
├── docker-compose.yml       # TimescaleDB setup
├── mix.exs                  # Project dependencies
├── mix.lock                 # Locked dependencies
├── AGENTS.md                # Agent architecture documentation
├── PROJECT_PLAN.md          # Detailed implementation roadmap
└── README.md                # Project setup instructions
```

## Development Setup

### Prerequisites
- Elixir 1.15+ and Erlang/OTP 26+
- PostgreSQL client tools
- Docker and Docker Compose (for TimescaleDB)
- Node.js (for asset compilation)

### Initial Setup
```bash
# Install dependencies
mix setup

# Start TimescaleDB
docker-compose up -d

# Start Phoenix server
mix phx.server

# Or start with IEx (interactive Elixir)
iex -S mix phx.server
```

### Database Configuration
- **Host**: localhost
- **Port**: 5433 (not default 5432!)
- **Database**: signal_dev
- **User**: postgres
- **Password**: postgres

### Running Tests
```bash
# Run all tests
mix test

# Run specific test file
mix test test/signal_web/controllers/page_controller_test.exs

# Run previously failed tests
mix test --failed
```

### Pre-commit Checks
Always run before committing:
```bash
mix precommit
```
This runs: compile with warnings as errors, format, and tests.

## Key Conventions & Guidelines

### Elixir Best Practices

#### 1. Pattern Matching Over Conditionals
```elixir
# Good
case result do
  {:ok, data} -> process(data)
  {:error, reason} -> handle_error(reason)
end

# Avoid
if result[:status] == :ok do
  process(result[:data])
end
```

#### 2. Tagged Tuples for Return Values
```elixir
def fetch_data do
  {:ok, data}     # Success case
  {:error, reason} # Error case
end
```

#### 3. Immutability and Rebinding
```elixir
# INVALID - rebinding inside if doesn't work
if connected?(socket) do
  socket = assign(socket, :val, val)
end

# VALID - rebind the result
socket =
  if connected?(socket) do
    assign(socket, :val, val)
  else
    socket
  end
```

#### 4. List Access
```elixir
# NEVER use index syntax on lists (not supported)
mylist[0]  # ❌ Error!

# ALWAYS use Enum or pattern matching
Enum.at(mylist, 0)  # ✅
[first | _rest] = mylist  # ✅
```

#### 5. Module Documentation
```elixir
defmodule Signal.BarCache do
  @moduledoc """
  In-memory ETS cache for latest bar and quote data per symbol.

  Provides fast concurrent reads with public ETS table.
  """

  @doc """
  Gets the current price for a symbol.

  Returns mid-point from quote if available, otherwise bar close.
  """
  @spec current_price(atom()) :: Decimal.t() | nil
  def current_price(symbol) do
    # implementation
  end
end
```

### Phoenix Framework Conventions

#### 1. Phoenix 1.8 LiveView Structure
```elixir
# Always wrap LiveView content in Layouts.app
def render(assigns) do
  ~H"""
  <.header>
    Market Dashboard
  </.header>

  <div class="mt-8">
    <!-- content -->
  </div>
  """
end
```

#### 2. Form Handling
```elixir
# In LiveView mount/handle_event
socket = assign(socket, form: to_form(changeset))

# In template - ALWAYS use @form, NEVER @changeset
<.form for={@form} id="order-form" phx-submit="place_order">
  <.input field={@form[:symbol]} type="text" label="Symbol" />
  <.input field={@form[:quantity]} type="number" label="Quantity" />
</.form>
```

#### 3. Navigation
```elixir
# In templates - use .link component
<.link navigate={~p"/market"}>Market Data</.link>
<.link patch={~p"/market?filter=tech"}>Tech Stocks</.link>

# In LiveView - use push functions
push_navigate(socket, to: ~p"/market")
push_patch(socket, to: ~p"/market?filter=tech")

# NEVER use deprecated live_redirect or live_patch
```

#### 4. LiveView Streams (for collections)
```elixir
# In LiveView
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:symbols_empty?, false)
   |> stream(:symbols, list_symbols())}
end

# In template
<div id="symbols" phx-update="stream">
  <div :for={{id, symbol} <- @streams.symbols} id={id}>
    {symbol.name}
  </div>
</div>

# To update
stream(socket, :symbols, [new_symbol])           # Append
stream(socket, :symbols, [new_symbol], at: -1)   # Prepend
stream_delete(socket, :symbols, symbol)          # Delete
stream(socket, :symbols, symbols, reset: true)   # Reset
```

### Ecto Guidelines

#### 1. Schema Fields
```elixir
schema "market_bars" do
  field :symbol, :string
  field :open, :decimal      # Use :decimal for prices
  field :volume, :integer
  field :bar_time, :utc_datetime_usec
end
```

#### 2. Changesets
```elixir
def changeset(bar, attrs) do
  bar
  |> cast(attrs, [:symbol, :open, :high, :low, :close, :volume])
  |> validate_required([:symbol, :open, :high, :low, :close, :volume])
  |> validate_number(:volume, greater_than_or_equal_to: 0)
  # No :allow_nil option - not supported!
end
```

#### 3. Accessing Changeset Fields
```elixir
# Use get_field/2
symbol = Ecto.Changeset.get_field(changeset, :symbol)

# NEVER use map syntax
symbol = changeset[:symbol]  # ❌ Error!
```

#### 4. Preloading Associations
```elixir
# Always preload when needed in templates
from(o in Order,
  where: o.user_id == ^user_id,
  preload: [:user, :symbol]
)
|> Repo.all()
```

### Frontend Guidelines (Tailwind + LiveView)

#### 1. Tailwind CSS v4
```css
/* app.css - New import syntax */
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/signal_web";

/* NEVER use @apply */
```

#### 2. HEEx Templates

**Class Lists:**
```heex
<a class={[
  "px-2 text-white",
  @active && "bg-blue-500",
  if(@status == :error, do: "border-red-500", else: "border-gray-300")
]}>
  Link Text
</a>
```

**Interpolation:**
```heex
<!-- Use {...} in attributes -->
<div id={@id} class={@class}>
  <!-- Use {...} for simple values in body -->
  {@value}

  <!-- Use <%= ... %> for block constructs -->
  <%= if @show_details do %>
    <p>Details here</p>
  <% end %>
</div>

<!-- NEVER do this -->
<div id="<%= @id %>">  ❌
```

**Conditionals:**
```heex
<!-- NO else if in Elixir! Use cond -->
<%= cond do %>
  <% @status == :connected -> %>
    <span class="text-green-500">Connected</span>
  <% @status == :disconnected -> %>
    <span class="text-red-500">Disconnected</span>
  <% true -> %>
    <span class="text-yellow-500">Unknown</span>
<% end %>
```

**Comments:**
```heex
<%!-- This is a HEEx comment --%>
```

#### 3. Icons
```heex
<!-- Use built-in icon component -->
<.icon name="hero-check-circle" class="w-5 h-5 text-green-500" />
```

## Database Information

### TimescaleDB Configuration
The project uses TimescaleDB (PostgreSQL with time-series extensions) running in Docker.

**Connection Details:**
- Container: `signal_timescaledb`
- Image: `timescale/timescaledb:latest-pg16`
- Port Mapping: `5433:5432` (localhost:5433)
- Volume: `timescale_data` (persistent)
- Timezone: America/Chicago

### Planned Schema

#### Market Bars Table (Hypertable)
```sql
CREATE TABLE market_bars (
  symbol VARCHAR NOT NULL,
  bar_time TIMESTAMPTZ NOT NULL,
  open DECIMAL(10,2) NOT NULL,
  high DECIMAL(10,2) NOT NULL,
  low DECIMAL(10,2) NOT NULL,
  close DECIMAL(10,2) NOT NULL,
  volume BIGINT NOT NULL,
  vwap DECIMAL(10,2),
  trade_count INTEGER,
  PRIMARY KEY (symbol, bar_time)
);

-- Convert to hypertable with 1-day chunks
SELECT create_hypertable('market_bars', 'bar_time', chunk_time_interval => INTERVAL '1 day');

-- Compression after 7 days
ALTER TABLE market_bars SET (timescaledb.compress, timescaledb.compress_segmentby = 'symbol');
SELECT add_compression_policy('market_bars', INTERVAL '7 days');

-- Retention: 6 years
SELECT add_retention_policy('market_bars', INTERVAL '6 years');
```

#### Events Table (Event Sourcing)
```sql
CREATE TABLE events (
  id BIGSERIAL PRIMARY KEY,
  stream_id VARCHAR NOT NULL,
  event_type VARCHAR NOT NULL,
  payload JSONB NOT NULL,
  version INTEGER NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(stream_id, version)
);

CREATE INDEX idx_events_stream ON events(stream_id, version);
CREATE INDEX idx_events_type ON events(event_type);
CREATE INDEX idx_events_timestamp ON events(timestamp);
```

### Migration Commands
```bash
# Create migration
mix ecto.gen.migration create_market_bars

# Run migrations
mix ecto.migrate

# Rollback
mix ecto.rollback

# Reset database
mix ecto.reset
```

## Development Workflows

### Creating a New Feature

#### 1. LiveView Page
```bash
# Generate LiveView
mix phx.gen.live Market Symbol symbols name:string exchange:string

# Add route to router.ex
live "/symbols", SymbolLive.Index, :index
```

#### 2. Context Module
```elixir
# lib/signal/market_data.ex
defmodule Signal.MarketData do
  @moduledoc """
  Market data context for bars, quotes, and symbols.
  """

  alias Signal.Repo
  alias Signal.MarketData.Bar

  def list_bars(symbol, start_date, end_date) do
    # Query implementation
  end
end
```

#### 3. Schema
```elixir
# lib/signal/market_data/bar.ex
defmodule Signal.MarketData.Bar do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
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

  def changeset(bar, attrs) do
    bar
    |> cast(attrs, [:symbol, :bar_time, :open, :high, :low, :close, :volume, :vwap, :trade_count])
    |> validate_required([:symbol, :bar_time, :open, :high, :low, :close, :volume])
    |> validate_ohlc_relationships()
  end

  defp validate_ohlc_relationships(changeset) do
    # Validation logic
    changeset
  end
end
```

### Adding Dependencies
```elixir
# mix.exs
defp deps do
  [
    {:new_dependency, "~> 1.0"}
  ]
end
```

Then run:
```bash
mix deps.get
mix deps.compile
```

### Working with PubSub

#### Publishing
```elixir
Phoenix.PubSub.broadcast(
  Signal.PubSub,
  "quotes:#{symbol}",
  {:quote, symbol, quote_data}
)
```

#### Subscribing (in LiveView)
```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(Signal.PubSub, "quotes:AAPL")
  end

  {:ok, assign(socket, :quote, nil)}
end

def handle_info({:quote, _symbol, quote}, socket) do
  {:noreply, assign(socket, :quote, quote)}
end
```

### GenServer Pattern
```elixir
defmodule Signal.BarCache do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(symbol) do
    GenServer.call(__MODULE__, {:get, symbol})
  end

  @impl true
  def init(_opts) do
    table = :ets.new(:bar_cache, [:named_table, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:get, symbol}, _from, state) do
    result = :ets.lookup(:bar_cache, symbol)
    {:reply, result, state}
  end
end
```

## Testing Guidelines

### Test Structure
```elixir
defmodule Signal.MarketDataTest do
  use Signal.DataCase

  alias Signal.MarketData

  describe "list_bars/3" do
    test "returns bars within date range" do
      # Setup
      bar1 = insert_bar(symbol: "AAPL", bar_time: ~U[2024-01-01 09:30:00Z])
      bar2 = insert_bar(symbol: "AAPL", bar_time: ~U[2024-01-02 09:30:00Z])

      # Execute
      result = MarketData.list_bars("AAPL", ~D[2024-01-01], ~D[2024-01-01])

      # Assert
      assert length(result) == 1
      assert hd(result).id == bar1.id
    end
  end
end
```

### LiveView Testing
```elixir
defmodule SignalWeb.MarketLiveTest do
  use SignalWeb.ConnCase

  import Phoenix.LiveViewTest

  test "displays market data", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/market")

    assert html =~ "Market Data"
    assert has_element?(view, "#market-table")
  end

  test "updates when quote received", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/market")

    # Simulate quote broadcast
    quote = %{symbol: "AAPL", bid_price: 185.50, ask_price: 185.52}
    Phoenix.PubSub.broadcast(Signal.PubSub, "quotes:AAPL", {:quote, "AAPL", quote})

    # Wait for LiveView update
    assert render(view) =~ "185.50"
  end
end
```

## Important Files Reference

### Configuration
- **config/config.exs** - Base application config
- **config/dev.exs** - Development environment (DB port 5433!)
- **config/runtime.exs** - Runtime config for production
- **.formatter.exs** - Code formatting rules

### Core Application
- **lib/signal/application.ex** - Supervision tree
- **lib/signal/repo.ex** - Database repository
- **mix.exs** - Dependencies and project config

### Web Layer
- **lib/signal_web/router.ex** - Route definitions
- **lib/signal_web/endpoint.ex** - Phoenix endpoint
- **lib/signal_web/components/core_components.ex** - Reusable UI components

### Assets
- **assets/css/app.css** - Main stylesheet (Tailwind v4)
- **assets/js/app.js** - Main JavaScript entry

### Documentation
- **PROJECT_PLAN.md** - Detailed implementation roadmap (Phase 0-5)
- **AGENTS.md** - Agent architecture documentation
- **README.md** - Setup instructions

## AI Assistant Guidelines

### When Working on This Project

#### DO:
1. **Always run `mix precommit`** before finalizing changes
2. **Check PROJECT_PLAN.md** to understand the implementation roadmap
3. **Use pattern matching** and functional programming idioms
4. **Add comprehensive documentation** (@moduledoc, @doc, @spec)
5. **Write tests** for new functionality
6. **Use Phoenix generators** when appropriate
7. **Follow the vertical slice architecture** - organize by feature
8. **Subscribe to PubSub topics** in LiveViews when connected
9. **Use ETS for caching** when high-performance reads needed
10. **Validate database migrations** after creating them

#### DON'T:
1. **Don't use deprecated Phoenix functions** (live_redirect, live_patch)
2. **Don't access changesets in templates** (use to_form/1)
3. **Don't use @apply in CSS**
4. **Don't nest modules** in the same file
5. **Don't use String.to_atom/1** on user input
6. **Don't write inline `<script>` tags** in templates
7. **Don't skip preloading** associations used in templates
8. **Don't assume default PostgreSQL port** (it's 5433!)
9. **Don't create new dependencies** without justification
10. **Don't use index syntax on lists** (mylist[0])

### Common Patterns to Follow

#### Error Handling
```elixir
case AlpacaEx.Client.get_bars("AAPL", start: start_date, end: end_date) do
  {:ok, bars} ->
    process_bars(bars)
    {:ok, bars}
  {:error, :network_error} ->
    Logger.error("Network error fetching bars")
    {:error, :network_error}
  {:error, reason} ->
    Logger.error("Unexpected error: #{inspect(reason)}")
    {:error, reason}
end
```

#### Concurrent Operations
```elixir
symbols = ["AAPL", "TSLA", "NVDA"]

results =
  symbols
  |> Task.async_stream(
    fn symbol -> fetch_data(symbol) end,
    timeout: :infinity,
    max_concurrency: 5
  )
  |> Enum.to_list()
```

#### LiveView Real-time Updates
```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    symbols = [:AAPL, :TSLA, :NVDA]
    Enum.each(symbols, fn symbol ->
      Phoenix.PubSub.subscribe(Signal.PubSub, "quotes:#{symbol}")
    end)
  end

  {:ok, assign(socket, :symbols, load_initial_data())}
end

def handle_info({:quote, symbol, quote}, socket) do
  {:noreply, update_symbol_quote(socket, symbol, quote)}
end
```

### Project-Specific Notes

1. **AlpacaEx Library**: Will be created as a separate project at `~/alpaca_ex`, added as path dependency
2. **Symbol Format**: Use atoms internally (`:AAPL`), strings for external APIs (`"AAPL"`)
3. **Timestamps**: Always use UTC (`utc_datetime_usec` for precision)
4. **Market Hours**: 9:30 AM - 4:00 PM Eastern Time
5. **Data Feed**: IEX feed from Alpaca (free tier)
6. **Paper Trading**: Always use paper trading endpoints during development

### Performance Considerations

1. **ETS for Hot Data**: Latest quotes/bars cached in ETS
2. **TimescaleDB Compression**: Enabled after 7 days
3. **LiveView Streams**: Use for collections to avoid memory issues
4. **Concurrent Downloads**: Max 5 concurrent API calls
5. **Batch Inserts**: Insert historical data in batches of 1000

### Security Checklist

- [ ] Never commit API keys (use environment variables)
- [ ] Validate all user inputs
- [ ] Use parameterized queries (Ecto does this by default)
- [ ] Sanitize HTML output (Phoenix does this by default)
- [ ] Protect against CSRF (enabled by default)
- [ ] Use HTTPS in production
- [ ] Rate limit API endpoints

---

## Quick Reference Commands

```bash
# Development
mix phx.server              # Start server
iex -S mix phx.server       # Start with IEx console
mix precommit               # Run quality checks

# Database
mix ecto.create             # Create database
mix ecto.migrate            # Run migrations
mix ecto.rollback           # Rollback last migration
mix ecto.reset              # Drop, create, migrate, seed

# Testing
mix test                    # Run all tests
mix test --failed           # Run failed tests
mix test path/to/test.exs   # Run specific test

# Dependencies
mix deps.get                # Install dependencies
mix deps.update --all       # Update all dependencies
mix deps.unlock --unused    # Remove unused deps

# Code Quality
mix format                  # Format code
mix compile --warnings-as-errors  # Strict compilation

# Docker
docker-compose up -d        # Start TimescaleDB
docker-compose down         # Stop TimescaleDB
docker-compose logs -f      # View logs
```

---

**Last Updated**: 2024-11-15
**Project Version**: 0.1.0 (Early Development)
**Phoenix Version**: 1.8.1
**Elixir Version**: 1.15+
