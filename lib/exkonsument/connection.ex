defmodule ExKonsument.Connection do
  require Logger
  use Connection

  def start_link(opts \\ []) do
    Connection.start_link(__MODULE__, [], opts)
  end

  def open_channel(pid) do
    Connection.call(pid, :open_channel)
  end

  def init([]) do
    {:connect, :init, %{channels: %{}}}
  end

  def connect(_, state) do
    case ExKonsument.open_connection(connection_string()) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        state =
          state |> Map.put(:connection, conn)
        {:ok, state}
      {:error, reason} ->
        Logger.error("Connection failed", error: reason)
        {:backoff, 1_000, state}
    end
  end

  def disconnect(info, state) do
    {:connect, info, state}
  end

  def handle_call(:open_channel, {from, _ref}, state) do
    case ExKonsument.open_channel(state[:connection]) do
      {:ok, channel} ->
        mon_ref = Process.monitor(from)
        channels = Map.put(state.channels, mon_ref, channel)
        {:reply, {:ok, channel}, %{state | channels: channels}}
      other ->
        {:reply, other, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, conn, reason},
                  %{connection: %{pid: conn}} = state) do
    {:disconnect, {:error, reason}, Map.delete(state, :connection)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case state.channels[ref] do
      nil -> {:noreply, state}
      channel ->
        ExKonsument.close_channel(channel)
        channels = Map.delete(state.channels, ref)
        {:noreply, %{state | channels: channels}}
    end
  end

  def terminate(_, state) do
    if state[:connection] do
      ExKonsument.close_connection(state[:connection])
    end
  end

  defp connection_string do
    Application.get_env(
      :exkonsument, :connection_string, "amqp://localhost:5672")
  end
end
