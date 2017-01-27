defmodule ExKonsumentTest do
  use ExUnit.Case, async: false

  import Mock

  test "setting up consumer fails gracefully" do
    with_mock AMQP.Connection, [open: fn _ -> {:error, nil} end] do
      assert {:error, nil} ==
        ExKonsument.setup_consumer(%{connection_string: ""})
    end
  end

  test "setting up consumer fails for every return value" do
    with_mock AMQP.Connection, [open: fn _ -> :error end] do
      assert {:error, :unknown} ==
        ExKonsument.setup_consumer(%{connection_string: ""})
    end
  end

  test "setting up consumer with a single routing key" do
    connection = %{pid: self()}
    with_mocks(amqp_mocks(connection)) do
      ExKonsument.setup_consumer(consumer())

      assert called AMQP.Connection.open(:connection_string)
      assert called AMQP.Channel.open(connection)
      assert called AMQP.Exchange.declare(:channel,
                                          :exchange_name,
                                          :exchange_type,
                                          :exchange_options)
      assert called AMQP.Queue.declare(:channel,
                                       :queue_name,
                                       :queue_options)
      assert called AMQP.Queue.bind(:channel,
                                    :queue_name,
                                    :exchange_name,
                                    routing_key: :routing_key)
      assert called AMQP.Basic.consume(:channel,
                                       :queue_name,
                                       nil,
                                       no_ack: true)
    end
  end

  test "setting up consumer with multiple routing keys" do
    consumer_with_multiple_routing_keys =
      Map.put(consumer(),
              :routing_keys,
              [:first_routing_key, :second_routing_key])

    connection = %{pid: self()}
    with_mocks(amqp_mocks(connection)) do
      ExKonsument.setup_consumer(consumer_with_multiple_routing_keys)

      assert called AMQP.Queue.bind(:channel,
                                    :queue_name,
                                    :exchange_name,
                                    routing_key: :first_routing_key)
      assert called AMQP.Queue.bind(:channel,
                                    :queue_name,
                                    :exchange_name,
                                    routing_key: :second_routing_key)
    end
  end

  test "exiting the parent process closes the connection" do
    {:ok, fake_connection} = Agent.start(fn -> nil end)
    connection = %{pid: fake_connection}
    with_mocks(amqp_mocks(connection)) do
      {:ok, agent_pid} = Agent.start(
        fn -> ExKonsument.setup_consumer(consumer()) end)

      assert Process.alive?(connection.pid)
      true = Process.exit(agent_pid, :kill)
      :timer.sleep(100)
      refute Process.alive?(connection.pid)
    end
  end

  test "closes a connection" do
    with_mock AMQP.Connection, [close: fn _ -> nil end] do
      ExKonsument.close_connection(:connection)
      assert called AMQP.Connection.close(:connection)
    end
  end

  defp exchange do
    %ExKonsument.Exchange{
      name: :exchange_name,
      type: :exchange_type,
      options: :exchange_options
    }
  end

  defp queue do
    %ExKonsument.Queue{
      name: :queue_name,
      options: :queue_options
    }
  end

  defp consumer do
    %ExKonsument.Consumer{
      connection_string: :connection_string,
      exchange: exchange(),
      queue: queue(),
      routing_keys: [:routing_key]
    }
  end

  defp amqp_mocks(connection) do
    [
      {AMQP.Connection, [], [open: fn _ -> {:ok, connection} end]},
      {AMQP.Channel, [], [open: fn _ -> {:ok, :channel} end]},
      {AMQP.Exchange, [], [declare: fn _, _, _, _ -> :ok end]},
      {AMQP.Queue, [], [declare: fn _, _, _ -> {:ok, :queue} end,
                        bind: fn _, _, _, _ -> :ok end]},
      {AMQP.Basic, [], [consume: fn _, _, _, _ -> {:ok, :result} end]}
    ]
  end
end
