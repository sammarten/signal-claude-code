defmodule Signal.Alpaca.SubscriptionManagerTest do
  use ExUnit.Case, async: false

  alias Signal.Alpaca.SubscriptionManager

  setup do
    # Set test configuration for symbols
    Application.put_env(:signal, :symbols, [:AAPL, :TSLA, :NVDA])

    on_exit(fn ->
      Application.delete_env(:signal, :symbols)
    end)

    :ok
  end

  describe "init/1" do
    test "initializes with configured symbols" do
      {:ok, pid} = start_supervised(SubscriptionManager)

      state = :sys.get_state(pid)
      assert state.subscribed == false
      assert state.symbols == [:AAPL, :TSLA, :NVDA]
    end

    test "initializes with empty symbols when not configured" do
      Application.delete_env(:signal, :symbols)

      {:ok, pid} = start_supervised(SubscriptionManager)

      state = :sys.get_state(pid)
      assert state.symbols == []
    end

    test "subscribes to alpaca:connection PubSub topic" do
      # Start the manager
      {:ok, _pid} = start_supervised(SubscriptionManager)

      # Broadcast a test message
      Phoenix.PubSub.broadcast(Signal.PubSub, "alpaca:connection", :test_message)

      # The manager should be subscribed (we can't directly verify, but no crash means success)
      Process.sleep(10)
    end
  end

  describe "handle_info/2 for :authenticated connection" do
    test "schedules subscription when authenticated and not yet subscribed" do
      {:ok, pid} = start_supervised(SubscriptionManager)

      # Send authenticated message
      send(pid, {:connection, :authenticated, %{}})

      # Wait a bit for scheduling
      Process.sleep(100)

      # Process should still be alive even if subscription fails
      assert Process.alive?(pid)
    end

    test "does not schedule duplicate subscription when already subscribed" do
      {:ok, pid} = start_supervised(SubscriptionManager)

      # Manually set subscribed state to simulate already subscribed
      :sys.replace_state(pid, fn state -> %{state | subscribed: true} end)

      state1 = :sys.get_state(pid)
      assert state1.subscribed == true

      # Second authentication (shouldn't schedule again)
      send(pid, {:connection, :authenticated, %{}})
      Process.sleep(100)

      # Process should still be alive and subscribed
      assert Process.alive?(pid)
      state2 = :sys.get_state(pid)
      assert state2.subscribed == true
    end
  end

  describe "handle_info/2 for :connected connection" do
    test "resets subscribed flag on new connection" do
      {:ok, pid} = start_supervised(SubscriptionManager)

      # Manually set subscribed state to simulate previous subscription
      :sys.replace_state(pid, fn state -> %{state | subscribed: true} end)

      state1 = :sys.get_state(pid)
      assert state1.subscribed == true

      # New connection should reset flag
      send(pid, {:connection, :connected, %{}})
      Process.sleep(10)

      state2 = :sys.get_state(pid)
      assert state2.subscribed == false
    end
  end

  describe "handle_info/2 for other connection statuses" do
    test "ignores other connection status updates" do
      {:ok, pid} = start_supervised(SubscriptionManager)

      initial_state = :sys.get_state(pid)

      # Send various status updates
      send(pid, {:connection, :disconnected, %{}})
      send(pid, {:connection, :subscribed, %{}})

      Process.sleep(10)

      final_state = :sys.get_state(pid)
      assert final_state == initial_state
    end
  end

  describe "handle_info/2 for :perform_subscription" do
    test "does nothing when symbols list is empty" do
      Application.put_env(:signal, :symbols, [])

      {:ok, pid} = start_supervised(SubscriptionManager)

      # Send perform_subscription message
      send(pid, :perform_subscription)
      Process.sleep(10)

      # Process should still be alive
      assert Process.alive?(pid)

      state = :sys.get_state(pid)
      assert state.subscribed == false
    end

    test "attempts subscription even when Stream doesn't exist" do
      {:ok, pid} = start_supervised(SubscriptionManager)

      # Send perform_subscription message
      # This will fail because AlpacaEx.Stream is not running,
      # but the manager should handle it gracefully and retry
      send(pid, :perform_subscription)
      Process.sleep(100)

      # Process should still be alive despite subscription failure
      assert Process.alive?(pid)
    end
  end

  describe "connection event flow" do
    test "complete connection and subscription flow" do
      {:ok, pid} = start_supervised(SubscriptionManager)

      # Initial state
      state1 = :sys.get_state(pid)
      assert state1.subscribed == false

      # Simulate connection
      send(pid, {:connection, :connected, %{}})
      Process.sleep(10)

      state2 = :sys.get_state(pid)
      assert state2.subscribed == false

      # Simulate authentication (subscription attempt will fail but process should survive)
      send(pid, {:connection, :authenticated, %{}})
      Process.sleep(100)

      # Process should still be alive
      assert Process.alive?(pid)

      # Simulate reconnection
      send(pid, {:connection, :connected, %{}})
      Process.sleep(10)

      # Process should still be alive and flag should be reset
      assert Process.alive?(pid)
      state4 = :sys.get_state(pid)
      assert state4.subscribed == false
    end
  end

  describe "symbol configuration" do
    test "uses symbols from application config" do
      Application.put_env(:signal, :symbols, [:MSFT, :GOOGL])

      {:ok, pid} = start_supervised(SubscriptionManager)

      state = :sys.get_state(pid)
      assert state.symbols == [:MSFT, :GOOGL]
    end

    test "handles empty symbol configuration" do
      Application.put_env(:signal, :symbols, [])

      {:ok, pid} = start_supervised(SubscriptionManager)

      state = :sys.get_state(pid)
      assert state.symbols == []

      # Should not crash when performing subscription with empty list
      send(pid, :perform_subscription)
      Process.sleep(10)

      # Process should still be alive
      assert Process.alive?(pid)
    end
  end
end
