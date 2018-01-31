defmodule ExKonsument.ConsumerTest do
  use ExUnit.Case, async: false

  import Mock

  test "it can be started" do
    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        {:ok, pid} = ExKonsument.Consumer.start_link(consumer())

        assert Process.alive?(pid)
      end
    end
  end

  test "it can be named", %{test: test} do
    name = Module.concat(__MODULE__, test)

    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        {:ok, _} = ExKonsument.Consumer.start_link(consumer(), name: name)

        assert Process.alive?(Process.whereis(name))
      end
    end
  end

  test "it forwards message payloads and state to the handle function" do
    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        {:ok, _} = start_and_trigger_consumer(consumer(), %{delivery_tag: :tag})

        assert_receive {%{"test" => "test"}, %{delivery_tag: :tag}, :state}
        assert_receive :ack
        assert called(ExKonsument.ack(%AMQP.Channel{}, :tag))
      end
    end
  end

  test "it requeues messages when processing function does not return :ok" do
    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        consumer = consumer(handling_fn: handling_fn(self(), :not_ok))
        Process.flag(:trap_exit, true)

        {:ok, pid} =
          start_and_trigger_consumer(consumer, %{
            delivery_tag: :tag,
            redelivered: false
          })

        assert_receive {
          %{"test" => "test"},
          %{delivery_tag: :tag, redelivered: false},
          :state
        }

        assert_receive :reject
        assert called(ExKonsument.reject(%AMQP.Channel{}, :tag, requeue: true))

        assert_receive {
          :EXIT,
          ^pid,
          {%ExKonsument.HandlingError{return: :not_ok}, _}
        }
      end
    end
  end

  test "it rejects redelivered messages when processing function does not" <>
         "return :ok" do
    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        consumer = consumer(handling_fn: handling_fn(self(), :not_ok))
        Process.flag(:trap_exit, true)

        {:ok, pid} =
          start_and_trigger_consumer(consumer, %{
            delivery_tag: :tag,
            redelivered: true
          })

        assert_receive {
          %{"test" => "test"},
          %{delivery_tag: :tag, redelivered: true},
          :state
        }

        assert_receive :reject
        assert called(ExKonsument.reject(%AMQP.Channel{}, :tag, requeue: false))

        assert_receive {
          :EXIT,
          ^pid,
          {%ExKonsument.HandlingError{return: :not_ok}, _}
        }
      end
    end
  end

  test "it requeues messages when an exception occurs" do
    error_fn = fn _, _, _ -> raise "exception" end

    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        consumer = consumer(handling_fn: error_fn)
        Process.flag(:trap_exit, true)

        {:ok, pid} =
          start_and_trigger_consumer(consumer, %{
            delivery_tag: :tag,
            redelivered: false
          })

        assert_receive :reject
        assert called(ExKonsument.reject(%AMQP.Channel{}, :tag, requeue: true))
        assert_receive {:EXIT, ^pid, {%RuntimeError{message: "exception"}, _}}
      end
    end
  end

  test "it rejects redelivered messages when an exception occurs" do
    error_fn = fn _, _, _ -> raise "exception" end

    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        consumer = consumer(handling_fn: error_fn)
        Process.flag(:trap_exit, true)

        {:ok, pid} =
          start_and_trigger_consumer(consumer, %{
            delivery_tag: :tag,
            redelivered: true
          })

        assert_receive :reject
        assert called(ExKonsument.reject(%AMQP.Channel{}, :tag, requeue: false))
        assert_receive {:EXIT, ^pid, {%RuntimeError{message: "exception"}, _}}
      end
    end
  end

  test "it declares an exchange and binds a queue" do
    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
        send(pid, {:basic_consume_ok, nil})

        send(
          pid,
          {:basic_deliver, Poison.encode!(%{test: "test"}),
           %{
             delivery_tag: :tag
           }}
        )

        assert_receive {%{"test" => "test"}, %{delivery_tag: :tag}, :state}

        assert called(
                 ExKonsument.declare_exchange(
                   %AMQP.Channel{},
                   :exchange_name,
                   :exchange_type,
                   :exchange_options
                 )
               )

        assert called(
                 ExKonsument.declare_queue(
                   %AMQP.Channel{},
                   :queue_name,
                   :queue_options
                 )
               )

        assert called(
                 ExKonsument.bind_queue(
                   %AMQP.Channel{},
                   :queue_name,
                   :exchange_name,
                   ["testing"]
                 )
               )

        assert called(ExKonsument.consume(%AMQP.Channel{}, :queue_name))
      end
    end
  end

  test "it shuts down when the queue is deleted" do
    Process.flag(:trap_exit, true)

    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        {:ok, pid} = ExKonsument.Consumer.start_link(consumer())

        send(pid, {:basic_cancel, nil})

        assert_receive {:EXIT, ^pid, :shutdown}
      end
    end
  end

  test "it can handle :channel_closed messages" do
    with_mocks connection_mocks() do
      with_mocks amqp_mocks() do
        {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
        assert_receive {:open_channel, _}
        assert_receive :bind_queue
        send(pid, {:channel_closed, %AMQP.Channel{}})
        assert_receive {:open_channel, _}
        assert_receive :bind_queue
      end
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
      send(test_pid, {payload, opts, state})
      return_value
    end
  end

  defp consumer(opts \\ []) do
    default_consumer()
    |> Map.merge(Enum.into(opts, %{}))
  end

  defp default_consumer do
    {:ok, connection} = Agent.start_link(fn -> [] end)

    %ExKonsument.Consumer{
      queue: queue(),
      exchange: exchange(),
      routing_keys: ["testing"],
      handling_fn: handling_fn(self()),
      state: :state,
      connection: connection
    }
  end

  defp amqp_mocks do
    test_pid = self()

    [
      {ExKonsument, [],
       [
         declare_exchange: fn _, _, _, _ -> :ok end,
         declare_queue: fn _, _, _ -> {:ok, :queue} end,
         bind_queue: fn _, _, _, _ ->
           send(test_pid, :bind_queue)
           :ok
         end,
         consume: fn _, _ -> {:ok, :result} end,
         ack: fn _, _ ->
           send(test_pid, :ack)
           :ok
         end,
         reject: fn _, _, _ ->
           send(test_pid, :reject)
           :reject
         end
       ]}
    ]
  end

  defp connection_mocks do
    test_pid = self()

    [
      {ExKonsument.Connection, [],
       [
         open_channel: fn connection ->
           send(test_pid, {:open_channel, connection})
           {:ok, %AMQP.Channel{}}
         end
       ]}
    ]
  end

  defp start_and_trigger_consumer(consumer, message_options) do
    {:ok, pid} = ExKonsument.Consumer.start_link(consumer)
    send(pid, {:basic_consume_ok, nil})

    send(
      pid,
      {:basic_deliver, Poison.encode!(%{test: "test"}), message_options}
    )

    {:ok, pid}
  end
end
