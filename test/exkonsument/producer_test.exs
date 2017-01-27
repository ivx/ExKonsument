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
    with_mock ExKonsument, message_queue_mocks() do
      {:ok, pid} = ExKonsument.Producer.start_link(producer())

      assert called ExKonsument.open_connection(producer().connection_string)
      assert called ExKonsument.open_channel(%{pid: self()})
      assert Process.alive?(pid)
    end
  end

  test "it tries to connect when receiving a :connect message" do
    with_mock ExKonsument, message_queue_mocks() do
      {:noreply, new_state} = ExKonsument.Producer.handle_info(
        :connect, %{producer: producer(), channel: nil})

      assert %{producer: producer(), channel: :channel} == new_state
      assert called ExKonsument.open_connection(producer().connection_string)
      assert called ExKonsument.open_channel(%{pid: self()})
    end
  end

  test "it retries to connect when it failed" do
    open_connection_error_mock = fn _ -> {:error, :failed} end
    with_mock ExKonsument, [open_connection: open_connection_error_mock] do
      {:ok, _state} = ExKonsument.Producer.init(producer())

      assert_receive :connect, 2000
      assert called ExKonsument.open_connection(producer().connection_string)
    end
  end

  test "it shuts down when the connection dies" do
    with_mock ExKonsument, message_queue_mocks() do
      {:ok, pid} = ExKonsument.Producer.start_link(producer())
      send pid, {:DOWN, nil, :process, nil, nil}
      Process.flag(:trap_exit, true)

      assert_receive {:EXIT, _, :shutdown}
    end
  end

  test "it publishes a payload to the exchange" do
    with_mock ExKonsument, message_queue_mocks() do
      {:ok, pid} = ExKonsument.Producer.start_link(producer())

      payload = %{test: :payload}
      ExKonsument.Producer.publish(pid, payload, :routing_key)

      assert called ExKonsument.declare_exchange(
        :channel, "exchange", :topic, [])
      assert called ExKonsument.publish(
        :channel, "exchange", :routing_key, Poison.encode!(payload))
    end
  end

  test "exiting the producer process closes the connection" do
    {:ok, fake_connection} = Agent.start(fn -> nil end)
    connection = %{pid: fake_connection}
    with_mock ExKonsument, message_queue_mocks(connection) do
      {:ok, producer_pid} = ExKonsument.Producer.start_link(producer())

      Process.unlink(producer_pid)
      assert Process.alive?(connection.pid)
      true = Process.exit(producer_pid, :kill)
      :timer.sleep(100)
      refute Process.alive?(connection.pid)
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
      open_connection: open_connection_mock(connection),
      open_channel: &open_channel_mock/1,
      declare_exchange: &declare_exchange_mock/4,
      publish: &publish_mock/4,
    ]
  end

  defp open_connection_mock(connection), do: fn _ -> {:ok, connection} end
  defp open_channel_mock(_), do: {:ok, :channel}
  defp declare_exchange_mock(_, _, _, _), do: :ok
  defp publish_mock(_, _, _, _), do: :ok
end
