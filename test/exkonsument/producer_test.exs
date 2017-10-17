defmodule ExKonsument.ProducerTest do
  use ExUnit.Case, async: false

  import Mock

  @exchange %ExKonsument.Exchange{name: "exchange", type: :topic}

  test "it can be started" do
    with_mocks message_queue_mocks() do
      with_mocks exkonsument_connection_mocks() do
        {:ok, pid} = ExKonsument.Producer.start_link(producer())

        assert_receive {:open_channel, _}
        assert Process.alive?(pid)
      end
    end
  end

  test "it can be named", %{test: test} do
    name = Module.concat(__MODULE__, test)

    with_mocks message_queue_mocks() do
      with_mocks exkonsument_connection_mocks() do
        {:ok, pid} = ExKonsument.Producer.start_link(producer(), name: name)

        assert Process.alive?(Process.whereis(name))
        GenServer.stop(pid)
      end
    end
  end

  test "it starts up and gets a channel" do
    with_mocks message_queue_mocks() do
      with_mocks exkonsument_connection_mocks() do
        {:ok, pid} = ExKonsument.Producer.start_link(producer())

        assert_receive {:open_channel, _}
        assert Process.alive?(pid)
      end
    end
  end

  test "it retries to get a channel when it failed" do
    with_mocks message_queue_mocks() do
      with_mock ExKonsument.Connection,
                [open_channel: error_channel_mock(self()),
                 start_link: fn -> {:ok, :connection} end] do

        {:ok, _pid} = ExKonsument.Producer.start_link(producer())
        assert_receive {:open_channel, :connection}
        assert_receive {:open_channel, :connection}, 3000
      end
    end
  end

  test "it startsup, gets a channel and declares an exchange" do
    with_mocks message_queue_mocks() do
      with_mocks exkonsument_connection_mocks() do
        {:ok, pid} = ExKonsument.Producer.start_link(producer())

        assert_receive {:declare_exchange, %{pid: _}, "exchange", :topic, []}
        assert Process.alive?(pid)
      end
    end
  end

  test "it publishes a payload to the exchange" do
    with_mocks message_queue_mocks() do
      with_mocks exkonsument_connection_mocks() do
        {:ok, pid} = ExKonsument.Producer.start_link(producer())

        payload = %{test: :payload}
        ExKonsument.Producer.publish(pid, "routing_key", payload)

        expected_payload = Poison.encode!(payload)
        assert_receive {
          :publish, _, "exchange", "routing_key", ^expected_payload}
      end
    end
  end

  test "it tries to reconnect when the channel dies" do
    {:ok, channel} = Agent.start(fn -> [] end)
    with_mock ExKonsument, [declare_exchange: fn _, _, _, _ -> :ok end,
                            open_connection: &open_connection_mock/1] do
      with_mock ExKonsument.Connection,
        [open_channel: open_channel_mock(self(), %{pid: channel}),
         start_link: start_link_mock()] do

        {:ok, pid} = ExKonsument.Producer.start_link(producer())
        assert_receive {:open_channel, _}

        send pid, {:channel_closed, %{pid: channel}}

        assert_receive {:open_channel, _}
        GenServer.stop(pid)
      end
    end
  end

  defp producer do
    {:ok, pid} = ExKonsument.Connection.start_link
    %ExKonsument.Producer{
      exchange: @exchange,
      connection: pid
    }
  end

  defp message_queue_mocks do
    [
      {ExKonsument, [], [declare_exchange: declare_exchange_mock(self())]},
      {ExKonsument, [], [publish: publish_mock(self())]},
      {ExKonsument, [], [open_connection: &open_connection_mock/1]},
      {ExKonsument, [], [close_connection: fn _ -> :ok end]}
    ]
  end

  defp publish_mock(pid) do
    fn channel, exchange, routing_key, payload ->
      send pid, {:publish, channel, exchange, routing_key, payload}
      :ok
    end
  end

  defp open_connection_mock(_) do
    {:ok, pid} = Agent.start(fn -> %{} end)
    {:ok, %{pid: pid}}
  end

  defp declare_exchange_mock(pid) do
    fn channel, exchange, type, opts ->
      send pid, {:declare_exchange, channel, exchange, type, opts}
      :ok
    end
  end

  defp exkonsument_connection_mocks do
    [
      {ExKonsument.Connection, [], [open_channel: open_channel_mock(self())]},
      {ExKonsument.Connection, [], [start_link: start_link_mock()]}
    ]
  end

  defp start_link_mock do
    fn -> {:ok, default_connection()} end
  end

  defp default_connection do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    agent
  end

  defp open_channel_mock(pid, channel \\ default_channel()) do
    fn connection ->
      send pid, {:open_channel, connection}
      {:ok, channel}
    end
  end

  defp default_channel do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    %{pid: agent}
  end

  defp error_channel_mock(pid) do
    fn connection ->
      send pid, {:open_channel, connection}
      {:error, :reason}
    end
  end
end
