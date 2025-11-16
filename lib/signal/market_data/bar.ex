defmodule Signal.MarketData.Bar do
  @moduledoc """
  Ecto schema for 1-minute market bar (OHLCV) data.

  Stores historical bar data in TimescaleDB hypertable with composite
  primary key of (symbol, bar_time).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          symbol: String.t(),
          bar_time: DateTime.t(),
          open: Decimal.t(),
          high: Decimal.t(),
          low: Decimal.t(),
          close: Decimal.t(),
          volume: non_neg_integer(),
          vwap: Decimal.t() | nil,
          trade_count: non_neg_integer() | nil
        }

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

  @required_fields [:symbol, :bar_time, :open, :high, :low, :close, :volume]
  @optional_fields [:vwap, :trade_count]
  @all_fields @required_fields ++ @optional_fields

  @doc """
  Changeset for creating or updating a bar.

  Validates:
  - All required fields present
  - OHLC relationships (high >= open/close/low, low <= open/close/high)
  - Volume >= 0
  - Trade count >= 0 if present

  ## Examples

      iex> changeset(%Bar{}, %{symbol: "AAPL", ...})
      %Ecto.Changeset{}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(bar, attrs) do
    bar
    |> cast(attrs, @all_fields)
    |> validate_required(@required_fields)
    |> validate_number(:volume, greater_than_or_equal_to: 0)
    |> validate_number(:trade_count, greater_than_or_equal_to: 0)
    |> validate_ohlc_relationships()
    |> validate_prices_positive()
  end

  @doc """
  Converts an AlpacaEx bar map to a Bar struct.

  ## Parameters
    - alpaca_bar: Map from AlpacaEx.Client.get_bars containing:
      - :timestamp - DateTime
      - :open - Decimal
      - :high - Decimal
      - :low - Decimal
      - :close - Decimal
      - :volume - Integer
      - :vwap - Decimal (optional)
      - :trade_count - Integer (optional)
    - symbol: String symbol (e.g., "AAPL")

  ## Returns
    - Map suitable for insert or changeset

  ## Examples

      iex> from_alpaca(%{timestamp: ~U[...], open: Decimal.new("185.20"), ...}, "AAPL")
      %{symbol: "AAPL", bar_time: ~U[...], open: Decimal.new("185.20"), ...}
  """
  @spec from_alpaca(map(), String.t()) :: map()
  def from_alpaca(alpaca_bar, symbol) do
    %{
      symbol: symbol,
      bar_time: alpaca_bar.timestamp,
      open: to_decimal(alpaca_bar.open),
      high: to_decimal(alpaca_bar.high),
      low: to_decimal(alpaca_bar.low),
      close: to_decimal(alpaca_bar.close),
      volume: alpaca_bar.volume,
      vwap: alpaca_bar[:vwap] && to_decimal(alpaca_bar.vwap),
      trade_count: alpaca_bar[:trade_count]
    }
  end

  @doc """
  Converts a Bar struct to a plain map.

  ## Parameters
    - bar: Bar struct

  ## Returns
    - Map with all bar fields

  ## Examples

      iex> to_map(%Bar{symbol: "AAPL", ...})
      %{symbol: "AAPL", bar_time: ~U[...], ...}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = bar) do
    Map.from_struct(bar)
  end

  # Private helper functions

  defp validate_ohlc_relationships(changeset) do
    with open when not is_nil(open) <- get_field(changeset, :open),
         high when not is_nil(high) <- get_field(changeset, :high),
         low when not is_nil(low) <- get_field(changeset, :low),
         close when not is_nil(close) <- get_field(changeset, :close) do
      changeset
      |> validate_high_ge_open(high, open)
      |> validate_high_ge_close(high, close)
      |> validate_high_ge_low(high, low)
      |> validate_low_le_open(low, open)
      |> validate_low_le_close(low, close)
      |> validate_low_le_high(low, high)
    else
      _ -> changeset
    end
  end

  defp validate_high_ge_open(changeset, high, open) do
    if Decimal.compare(high, open) == :lt do
      add_error(changeset, :high, "must be greater than or equal to open")
    else
      changeset
    end
  end

  defp validate_high_ge_close(changeset, high, close) do
    if Decimal.compare(high, close) == :lt do
      add_error(changeset, :high, "must be greater than or equal to close")
    else
      changeset
    end
  end

  defp validate_high_ge_low(changeset, high, low) do
    if Decimal.compare(high, low) == :lt do
      add_error(changeset, :high, "must be greater than or equal to low")
    else
      changeset
    end
  end

  defp validate_low_le_open(changeset, low, open) do
    if Decimal.compare(low, open) == :gt do
      add_error(changeset, :low, "must be less than or equal to open")
    else
      changeset
    end
  end

  defp validate_low_le_close(changeset, low, close) do
    if Decimal.compare(low, close) == :gt do
      add_error(changeset, :low, "must be less than or equal to close")
    else
      changeset
    end
  end

  defp validate_low_le_high(changeset, low, high) do
    if Decimal.compare(low, high) == :gt do
      add_error(changeset, :low, "must be less than or equal to high")
    else
      changeset
    end
  end

  defp validate_prices_positive(changeset) do
    changeset
    |> validate_price_positive(:open)
    |> validate_price_positive(:high)
    |> validate_price_positive(:low)
    |> validate_price_positive(:close)
    |> validate_price_positive(:vwap)
  end

  defp validate_price_positive(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      price ->
        if Decimal.compare(price, Decimal.new(0)) != :gt do
          add_error(changeset, field, "must be greater than 0")
        else
          changeset
        end
    end
  end

  defp to_decimal(value) when is_struct(value, Decimal), do: value
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
end
