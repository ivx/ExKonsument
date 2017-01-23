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
    exchange = %ExKonsument.Exchange{
      name: :exchange_name,
      type: :exchange_type,
      options: :exchange_options
    }
    queue = %ExKonsument.Queue{
      name: :queue_name,
      options: :queue_options
    }
    consumer = %ExKonsument.Consumer{
      connection_string: :connection_string,
      exchange: exchange,
      queue: queue,
      routing_key: :routing_key
    }

    with_mocks([
      {AMQP.Connection, [], [open: fn _ -> {:ok, :connection} end]},
      {AMQP.Channel, [], [open: fn _ -> {:ok, :channel} end]},
      {AMQP.Exchange, [], [declare: fn _, _, _, _ -> :ok end]},
      {AMQP.Queue, [], [declare: fn _, _, _ -> {:ok, :queue} end,
                        bind: fn _, _, _, _ -> :ok end]},
      {AMQP.Basic, [], [consume: fn _, _, _, _ -> {:ok, :result} end]}
    ]) do
      ExKonsument.setup_consumer(consumer)

      assert called AMQP.Connection.open(:connection_string)
      assert called AMQP.Channel.open(:connection)
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
    exchange = %ExKonsument.Exchange{
      name: :exchange_name,
      type: :exchange_type,
      options: :exchange_options
    }
    queue = %ExKonsument.Queue{
      name: :queue_name,
      options: :queue_options
    }
    consumer = %ExKonsument.Consumer{
      connection_string: :connection_string,
      exchange: exchange,
      queue: queue,
      routing_key: [:first_routing_key, :second_routing_key]
    }

    with_mocks([
      {AMQP.Connection, [], [open: fn _ -> {:ok, :connection} end]},
      {AMQP.Channel, [], [open: fn _ -> {:ok, :channel} end]},
      {AMQP.Exchange, [], [declare: fn _, _, _, _ -> :ok end]},
      {AMQP.Queue, [], [declare: fn _, _, _ -> {:ok, :queue} end,
                        bind: fn _, _, _, _ -> :ok end]},
      {AMQP.Basic, [], [consume: fn _, _, _, _ -> {:ok, :result} end]}
    ]) do
      ExKonsument.setup_consumer(consumer)

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

  test "closes a connection" do
    with_mock AMQP.Connection, [close: fn _ -> nil end] do
      ExKonsument.close_connection(:connection)
      assert called AMQP.Connection.close(:connection)
    end
  end
end
