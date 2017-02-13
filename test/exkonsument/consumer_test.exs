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
      send pid, {:basic_deliver,
                 Poison.encode!(%{test: "test"}),
                 %{delivery_tag: :tag}}

      assert_receive {%{"test" => "test"}, %{delivery_tag: :tag}, :state}
      assert_receive :ack
      assert called ExKonsument.ack(%{conn: %{pid: self()}}, :tag)
    end
  end

  test "it rejects messages when processing function does not return :ok" do
    with_mocks amqp_mocks(%{pid: self()}) do
      consumer = consumer(handling_fn: handling_fn(self(), :not_ok))
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer)
      send pid, {:basic_consume_ok, nil}
      send pid, {:basic_deliver,
                 Poison.encode!(%{test: "test"}),
                 %{delivery_tag: :tag}}

      assert_receive {%{"test" => "test"}, %{delivery_tag: :tag}, :state}
      assert_receive :reject
      assert called ExKonsument.reject(%{conn: %{pid: self()}}, :tag)
    end
  end

  test "it opens a connection with state" do
    connection = %{pid: self()}
    channel = %{conn: connection}
    with_mocks amqp_mocks(connection) do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
      send pid, {:basic_consume_ok, nil}
      send pid, {:basic_deliver, Poison.encode!(%{test: "test"}), %{delivery_tag: :tag}}

      assert_receive {%{"test" => "test"}, %{delivery_tag: :tag}, :state}

      assert called ExKonsument.open_connection(:connection_string)
      assert called ExKonsument.open_channel(%{pid: self()})
      assert called ExKonsument.declare_exchange(channel,
                                                 :exchange_name,
                                                 :exchange_type,
                                                 :exchange_options)
      assert called ExKonsument.declare_queue(channel,
                                              :queue_name,
                                              :queue_options)
      assert called ExKonsument.bind_queue(channel,
                                           :queue_name,
                                           :exchange_name,
                                           ["testing"])
      assert called ExKonsument.consume(channel, :queue_name)
    end
  end

  test "it tries to connect when receiving a :connect message" do
    connection = %{pid: self()}
    with_mocks amqp_mocks(connection) do
      result = ExKonsument.Consumer.handle_info(:connect, %{consumer: consumer()})

      expected_state = %{consumer: consumer(), channel: %{conn: connection}}

      assert called ExKonsument.open_connection(:connection_string)
      assert {:noreply, expected_state} == result
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

      Agent.stop(fake_connection)
      :timer.sleep(100)
      refute Process.alive?(consumer_pid)
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
      GenServer.stop(pid)
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

  defp handling_fn(test_pid, return_value \\ :ok) do
    fn payload, opts, state ->
      send test_pid, {payload, opts, state}
      return_value
    end
  end

  defp consumer(opts \\ []) do
    default_consumer()
    |> Map.merge(Enum.into(opts, %{}))
  end

  defp default_consumer do
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
    test_pid = self()
    [
      {ExKonsument, [], [open_connection: fn _ -> {:ok, connection} end,
                         open_channel: fn _ -> {:ok, %{conn: connection}} end,
                         declare_exchange: fn _, _, _, _ -> :ok end,
                         declare_queue: fn _, _, _ -> {:ok, :queue} end,
                         bind_queue: fn _, _, _, _ -> :ok end,
                         consume: fn _, _ -> {:ok, :result} end,
                         close_connection: fn _ -> :ok end,
                         connection_open?: fn _ -> true end,
                         ack: fn _, _ ->
                           send test_pid, :ack
                           :ok
                         end,
                         reject: fn _, _ ->
                           send test_pid, :reject
                           :reject
                         end]}
    ]
  end

  defp amqp_error_mocks() do
    [
      {ExKonsument, [], [open_connection: fn _ -> {:error, :reason} end,
                         connection_open?: fn _ -> false end]}
    ]
  end
end
