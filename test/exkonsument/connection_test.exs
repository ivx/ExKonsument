defmodule ExKonsument.ConnectionTest do
  use ExUnit.Case, async: false

  import Mock

  test "it can be started" do
    {:ok, pid} = ExKonsument.Connection.start_link
    assert Process.alive?(pid)
  end

  test "it can get a name", %{test: test} do
    name = Module.concat(__MODULE__, test)
    {:ok, pid} = ExKonsument.Connection.start_link(name: name)
    assert Process.whereis(name) == pid
  end

  test "it connects on start-up" do
    with_mock ExKonsument, [open_connection: success_connection_mock(self())] do
      {:ok, _} = ExKonsument.Connection.start_link
      assert_receive {:open_connection, "amqp://localhost:5672"}
    end
  end

  test "it logs error on connection error" do
    with_mock Logger, [bare_log: log_mock(self())] do
      with_mock ExKonsument, [open_connection: error_connection_mock(self())] do
          {:ok, _} = ExKonsument.Connection.start_link
          assert_receive {:open_connection, "amqp://localhost:5672"}
          assert_receive {:bare_log, "Connection failed", log_meta}
          assert "reason" == log_meta[:error]
      end
    end
  end

  test "it disconnects on terminate" do
    {:ok, agent} = Agent.start_link(fn -> %{} end)
    with_mock ExKonsument, [open_connection:
                              success_connection_mock(self(), agent),
                            close_connection: close_connection_mock(self())] do
        {:ok, pid} = ExKonsument.Connection.start_link
        assert_receive {:open_connection, "amqp://localhost:5672"}
        GenServer.stop(pid)
        assert_receive {:close_connection, %{pid: ^agent}}
    end
  end

  test "it reconnects when the connection is killed" do
    {:ok, agent} = Agent.start(fn -> %{} end)
    with_mock ExKonsument, [open_connection:
                              success_connection_mock(self(), agent),
                            close_connection: close_connection_mock(self())] do
        {:ok, _} = ExKonsument.Connection.start_link
        assert_receive {:open_connection, "amqp://localhost:5672"}
        Process.exit(agent, :shutdown)
        assert_receive {:open_connection, "amqp://localhost:5672"}
    end
  end

  test "it returns a channel" do
    {:ok, agent} = Agent.start(fn -> %{} end)
    with_mock ExKonsument, [open_connection:
                              success_connection_mock(self(), agent),
                            close_connection: close_connection_mock(self()),
                            open_channel: open_channel_mock(self())] do
      {:ok, pid} = ExKonsument.Connection.start_link
      assert_receive {:open_connection, "amqp://localhost:5672"}
      {:ok, _} = ExKonsument.Connection.open_channel(pid)
      assert_receive {:open_channel, %{pid: ^agent}}
    end
  end

  test "it fails on creating a channel without connection" do
    with_mock ExKonsument, [open_connection:
                              error_connection_mock(self()),
                            close_connection: close_connection_mock(self()),
                            open_channel: open_channel_mock(self())] do
      {:ok, pid} = ExKonsument.Connection.start_link
      assert_receive {:open_connection, "amqp://localhost:5672"}
      :error = ExKonsument.Connection.open_channel(pid)
      refute_receive {:open_channel, nil}
    end
  end

  test "it closes channels when the connection dies" do
    {:ok, connection} = Agent.start(fn -> %{} end)
    {:ok, channel} = Agent.start(fn -> %{} end)
    with_mock ExKonsument, [open_connection:
                              success_connection_mock(self(), connection),
                            close_connection: close_connection_mock(self()),
                            open_channel: open_channel_mock(self(), channel),
                            close_channel: close_channel_mock(self())] do
      {:ok, pid} = ExKonsument.Connection.start_link
      assert_receive {:open_connection, "amqp://localhost:5672"}

      TestProducer.start_link(self(), pid)

      assert_receive {:open_channel, %{pid: ^connection}}
      assert_receive :done
      Process.exit(connection, :shutdown)
      assert_receive {:channel_closed, %{pid: ^channel}}
    end
  end

  test "it kills a channel if the client dies" do
    {:ok, agent} = Agent.start(fn -> %{} end)
    {:ok, chan_agent} = Agent.start(fn -> %{} end)
    with_mock ExKonsument, [open_connection:
                              success_connection_mock(self(), agent),
                            close_connection: close_connection_mock(self()),
                            open_channel: open_channel_mock(self(), chan_agent),
                            close_channel: close_channel_mock(self())] do
      {:ok, pid} = ExKonsument.Connection.start_link
      assert_receive {:open_connection, "amqp://localhost:5672"}

      test_pid = self()
      client_pid = spawn fn ->
        {:ok, _} = ExKonsument.Connection.open_channel(pid)
        send test_pid, :done
      end

      assert_receive {:open_channel, %{pid: ^agent}}
      assert_receive :done
      refute Process.alive?(client_pid)
      assert_receive {:close_channel, %{pid: ^chan_agent}}
      refute Process.alive?(chan_agent)
    end
  end

  defp log_mock(pid) do
    fn _, message, meta ->
      send pid, {:bare_log, message, meta}
      :ok
    end
  end

  defp success_connection_mock(pid, agent \\ default_agent()) do
    fn connection_string ->
      send pid, {:open_connection, connection_string}
      {:ok, %{pid: agent}}
    end
  end

  defp default_agent do
    {:ok, agent} = Agent.start_link(fn -> %{} end)
    agent
  end

  defp error_connection_mock(pid) do
    fn connection_string ->
      send pid, {:open_connection, connection_string}
      {:error, "reason"}
    end
  end

  defp close_connection_mock(pid) do
    fn connection ->
      send pid, {:close_connection, connection}
      :ok
    end
  end

  defp open_channel_mock(pid, agent \\ default_agent()) do
    fn connection ->
      send pid, {:open_channel, connection}
      case connection do
        %{pid: _} -> {:ok, %{connection: connection, pid: agent}}
        _ -> :error
      end
    end
  end

  defp close_channel_mock(pid) do
    fn channel ->
      Agent.stop(channel.pid)
      send pid, {:close_channel, channel}
      :ok
    end
  end
end

defmodule TestProducer do
  use GenServer

  def start_link(test_pid, connection) do
    GenServer.start_link(
      __MODULE__, %{test_pid: test_pid, connection: connection}, [])
  end

  def init(state) do
    {:ok, channel} = ExKonsument.Connection.open_channel(state.connection)
    send state.test_pid, :done
    {:ok, Map.put(state, :channel, channel)}
  end

  def handle_info(msg, state) do
    send state.test_pid, msg
    {:noreply, state}
  end
end
