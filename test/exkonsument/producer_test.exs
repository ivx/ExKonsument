defmodule ExKonsument.ProducerTest do
  use ExUnit.Case, async: false

  import Mock

  test "it can be started" do
    {:ok, pid} = ExKonsument.Producer.start_link(producer())

    assert Process.alive?(pid)
  end

  test "it can be named", %{test: test} do
    name = Module.concat(__MODULE__, test)

    {:ok, _} = ExKonsument.Producer.start_link(producer(), name: name)

    assert Process.alive?(Process.whereis(name))
  end

  test "it opens a connection on startup" do
    with_mocks message_queue_mocks() do
      {:ok, pid} = ExKonsument.Producer.start_link(producer())

      assert called ExKonsument.open_connection(producer().connection_string)
      assert called ExKonsument.open_channel(%{pid: self()})
      assert Process.alive?(pid)
    end
  end

  test "it tries to connect when receiving a :connect message" do
    with_mocks message_queue_mocks() do
      {:noreply, new_state} = ExKonsument.Producer.handle_info(
        :connect, %{producer: producer(), channel: nil})

      connection = %{pid: self()}
      assert %{producer: producer(), channel: %{conn: connection}} == new_state
      assert called ExKonsument.open_connection(producer().connection_string)
      assert called ExKonsument.open_channel(connection)
    end
  end

  test "it retries to connect when it failed" do
    with_mocks message_queue_error_mocks() do
      {:ok, _state} = ExKonsument.Producer.init(producer())

      assert_receive :connect, 2000
      assert called ExKonsument.open_connection(producer().connection_string)
    end
  end

  test "it shuts down when the connection dies" do
    with_mocks message_queue_mocks() do
      {:ok, pid} = ExKonsument.Producer.start_link(producer())
      Process.unlink(pid)

      send pid, {:DOWN, nil, :process, nil, nil}

      :timer.sleep(100)
      refute Process.alive?(pid)
    end
  end

  test "it publishes a payload to the exchange" do
    connection = %{pid: self()}
    with_mocks message_queue_mocks(connection) do
      {:ok, pid} = ExKonsument.Producer.start_link(producer())

      payload = %{test: :payload}
      ExKonsument.Producer.publish(pid, payload, :routing_key)

      channel = %{conn: connection}
      assert called ExKonsument.declare_exchange(
        channel, "exchange", :topic, [])
      assert called ExKonsument.publish(
        channel, "exchange", :routing_key, Poison.encode!(payload))
    end
  end

  test "it closes connection when the producer is stopped" do
    connection = %{pid: self()}
    with_mocks message_queue_mocks(connection) do
      {:ok, producer_pid} = ExKonsument.Producer.start_link(producer())
      GenServer.stop(producer_pid)
      assert called ExKonsument.close_connection(connection)
    end
  end

  defp exchange do
    %ExKonsument.Exchange{name: "exchange", type: :topic}
  end

  defp producer do
    %ExKonsument.Producer{
      exchange: exchange(),
      connection_string: "amqp://guest:guest@localhost"
    }
  end

  defp message_queue_mocks, do: message_queue_mocks(%{pid: self()})
  defp message_queue_mocks(connection) do
    [
      {ExKonsument, [], [open_connection: fn _ -> {:ok, connection} end]},
      {ExKonsument, [], [open_channel: fn _ -> {:ok, %{conn: connection}} end]},
      {ExKonsument, [], [declare_exchange: fn _, _, _, _ -> :ok end]},
      {ExKonsument, [], [declare_queue: fn _, _, _ -> {:ok, :queue} end,
                         bind_queue: fn _, _, _, _ -> :ok end]},
      {ExKonsument, [], [consume: fn _, _, _, _ -> {:ok, :result} end]},
      {ExKonsument, [], [publish: fn _, _, _, _ -> :ok end]},
      {ExKonsument, [], [close_connection: fn _ -> :ok end]},
      {ExKonsument, [], [connection_open?: fn _ -> true end]}
    ]
  end

  defp message_queue_error_mocks() do
    [
      {ExKonsument, [], [open_connection: fn _ -> {:error, :reason} end]}
    ]
  end
end
