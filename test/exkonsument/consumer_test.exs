defmodule ExKonsument.ConsumerTest do
  use ExUnit.Case, async: false

  import Mock

  test "it can be started" do
    with_mock ExKonsument, message_queue_mocks() do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())

      assert Process.alive?(pid)
    end
  end

  test "it can be named", %{test: test} do
    name = Module.concat(__MODULE__, test)

    with_mock ExKonsument, message_queue_mocks() do
      {:ok, _} = ExKonsument.Consumer.start_link(consumer(), name: name)

      assert Process.alive?(Process.whereis(name))
    end
  end

  test "it forwards message payloads and state to the handle function" do
    with_mock ExKonsument, message_queue_mocks() do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
      send pid, {:basic_consume_ok, nil}
      send pid, {:basic_deliver, Poison.encode!(%{test: "test"}), :opts}

      assert_receive {%{"test" => "test"}, :opts, :state}
    end
  end

  test "it opens a connection with state" do
    with_mock ExKonsument, message_queue_mocks() do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
      send pid, {:basic_consume_ok, nil}
      send pid, {:basic_deliver, Poison.encode!(%{test: "test"}), :opts}

      assert_receive {%{"test" => "test"}, :opts, :state}
      assert called ExKonsument.setup_consumer(consumer())
    end
  end

  test "it tries to connect when receiving a :connect message" do
    with_mock ExKonsument, message_queue_mocks() do
      ExKonsument.Consumer.handle_info(:connect, %{consumer: consumer()})

      assert called ExKonsument.setup_consumer(consumer())
    end
  end

  test "it retries to connect when it failed" do
    setup_consumer_error_mock = [setup_consumer: fn _ -> {:error, :failed} end]
    with_mock ExKonsument, setup_consumer_error_mock do
      {:ok, _state} = ExKonsument.Consumer.init(%{consumer: consumer()})

      assert_receive :connect, 2000
      assert called ExKonsument.setup_consumer(consumer())
    end
  end

  test "it shuts down when the connection dies" do
    with_mock ExKonsument, message_queue_mocks() do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
      send pid, {:DOWN, nil, :process, nil, nil}
      Process.flag(:trap_exit, true)

      assert_receive {:EXIT, _, :shutdown}
    end
  end

  test "it shuts down when the queue is deleted" do
    with_mock ExKonsument, message_queue_mocks() do
      {:ok, pid} = ExKonsument.Consumer.start_link(consumer())
      send pid, {:basic_cancel, nil}
      Process.flag(:trap_exit, true)

      assert_receive {:EXIT, _, :shutdown}
    end
  end

  defp queue do
    %ExKonsument.Queue{name: "queue"}
  end

  defp exchange do
    %ExKonsument.Exchange{name: "exchange", type: :topic}
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
      state: :state
    }
  end

  defp message_queue_mocks do
    [
      setup_consumer: &setup_consumer_mock/1
    ]
  end

  defp setup_consumer_mock(_) do
    {:ok, %{pid: self()}}
  end
end
