defmodule ExKonsument.ConsumerTest do
  use ExUnit.Case, async: false

  import Mock

  test "it can be started" do
    with_mocks amqp_mocks(%{pid: self()}) do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())

      assert Process.alive?(pid)
    end
  end

  test "it can be named", %{test: test} do
    name = Module.concat(__MODULE__, test)

    with_mocks amqp_mocks(%{pid: self()}) do
      {:ok, _} = ExKonsument.Consumer.start_link(consumer(), name: name)

      assert Process.alive?(Process.whereis(name))
    end
  end

  test "it forwards message payloads and state to the handle function" do
    with_mocks amqp_mocks(%{pid: self()}) do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
      send pid, {:basic_consume_ok, nil}
      send pid, {:basic_deliver, Poison.encode!(%{test: "test"}), :opts}

      assert_receive {%{"test" => "test"}, :opts, :state}
    end
  end

  test "it opens a connection with state" do
    with_mocks amqp_mocks(%{pid: self()}) do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
      send pid, {:basic_consume_ok, nil}
      send pid, {:basic_deliver, Poison.encode!(%{test: "test"}), :opts}

      assert_receive {%{"test" => "test"}, :opts, :state}

      assert called ExKonsument.open_connection(:connection_string)
      assert called ExKonsument.open_channel(%{pid: self()})
      assert called ExKonsument.declare_exchange(:channel,
                                                 :exchange_name,
                                                 :exchange_type,
                                                 :exchange_options)
      assert called ExKonsument.declare_queue(:channel,
                                              :queue_name,
                                              :queue_options)
      assert called ExKonsument.bind_queue(:channel,
                                           :queue_name,
                                           :exchange_name,
                                           ["testing"])
      assert called ExKonsument.consume(:channel,
                                        :queue_name,
                                        nil,
                                        no_ack: true)
    end
  end

  test "it tries to connect when receiving a :connect message" do
    with_mocks amqp_mocks(%{pid: self()}) do
      ExKonsument.Consumer.handle_info(:connect, %{consumer: consumer()})

      assert called ExKonsument.open_connection(:connection_string)
    end
  end

  test "it retries to connect when it failed" do
    with_mocks amqp_error_mocks() do
      {:ok, _state} = ExKonsument.Consumer.init(%{consumer: consumer()})

      assert_receive :connect, 2000
      assert called ExKonsument.open_connection(:connection_string)
    end
  end

  test "it shuts down when the connection dies" do
    {:ok, fake_connection} = Agent.start(fn -> nil end)
    connection = %{pid: fake_connection}
    with_mocks(amqp_mocks(connection)) do

      {:ok, consumer_pid} = ExKonsument.Consumer.start_link(consumer())

      Process.unlink(consumer_pid)

      assert Process.alive?(connection.pid)
      true = Process.exit(consumer_pid, :kill)
      :timer.sleep(100)
      refute Process.alive?(connection.pid)
    end
  end

  test "it shuts down when the queue is deleted" do
    with_mocks amqp_mocks(%{pid: self()}) do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
      Process.unlink(pid)

      send pid, {:basic_cancel, nil}

      :timer.sleep(100)
      refute Process.alive?(pid)
    end
  end

  test "it closes connection when the consumer is stopped" do
    connection = %{pid: self()}
    with_mocks amqp_mocks(connection) do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
      Process.unlink(pid)

      Process.exit(pid, :normal)

      :timer.sleep(100)
      refute Process.alive?(pid)
      assert called ExKonsument.close_connection(connection)
    end
  end

  defp queue do
    %ExKonsument.Queue{
      name: :queue_name,
      options: :queue_options
    }
  end

  defp exchange do
    %ExKonsument.Exchange{
      name: :exchange_name,
      type: :exchange_type,
      options: :exchange_options
    }
  end

  defp handling_fn(test_pid) do
    fn payload, opts, state ->
      send test_pid, {payload, opts, state}
    end
  end

  defp consumer do
    %ExKonsument.Consumer{
      queue: queue(),
      exchange: exchange(),
      routing_keys: ["testing"],
      handling_fn: handling_fn(self()),
      state: :state,
      connection_string: :connection_string
    }
  end

  defp amqp_mocks(connection) do
    [
      {ExKonsument, [], [open_connection: fn _ -> {:ok, connection} end]},
      {ExKonsument, [], [open_channel: fn _ -> {:ok, :channel} end]},
      {ExKonsument, [], [declare_exchange: fn _, _, _, _ -> :ok end]},
      {ExKonsument, [], [declare_queue: fn _, _, _ -> {:ok, :queue} end,
                         bind_queue: fn _, _, _, _ -> :ok end]},
      {ExKonsument, [], [consume: fn _, _, _, _ -> {:ok, :result} end]},
      {ExKonsument, [], [close_connection: fn _ -> :ok end]}
    ]
  end

  defp amqp_error_mocks() do
    [
      {ExKonsument, [], [open_connection: fn _ -> {:error, :reason} end]}
    ]
  end
end
