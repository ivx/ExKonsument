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
    Logger.info("Trying to connect...")
    case ExKonsument.open_connection(connection_string()) do
      {:ok, conn} ->
        Logger.info("Connected successfully")
        Process.monitor(conn.pid)
        state = state |> Map.put(:connection, conn)
        {:ok, state}
      {:error, reason} ->
        Logger.error("Connection failed", error: reason)
        {:backoff, 1_000, state}
    end
  end

  def disconnect(info, state) do
    Logger.info("Disconnecting")
    close_channels(state[:channels])
    new_state = state
    |> Map.put(:connection, nil)
    |> Map.put(:channels, %{})
    {:connect, info, new_state}
  end

  defp close_channels(nil), do: nil
  defp close_channels(channels) do
    Enum.each(channels, fn {mon_ref, {channel, from}} ->
      Process.demonitor(mon_ref)
      send from, {:channel_closed, channel}
    end)
  end

  def handle_call(:open_channel, {from, _ref}, state) do
    if state[:connection] do
      case ExKonsument.open_channel(state[:connection]) do
        {:ok, channel} ->
          Logger.info("Opened channel for #{inspect from}")
          mon_ref = Process.monitor(from)
          channels = Map.put(state.channels, mon_ref, {channel, from})
          {:reply, {:ok, channel}, %{state | channels: channels}}
        other ->
          Logger.error("Failed to open channel for #{inspect from}")
          {:reply, other, state}
      end
    else
      {:reply, :error, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, conn, reason},
                  %{connection: %{pid: conn}} = state) do
    {:disconnect, {:error, reason}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    Logger.info("Client died, closing channel...")
    case state.channels[ref] do
      nil ->
        Logger.info("No channel found")
        {:noreply, state}
      {channel, from} ->
        Logger.info("Closed channel of #{inspect from}")
        ExKonsument.close_channel(channel)
        channels = Map.delete(state.channels, ref)
        {:noreply, %{state | channels: channels}}
    end
  end

  def terminate(_, state) do
    if state[:connection] && Process.alive?(state.connection.pid) do
      ExKonsument.close_connection(state[:connection])
    end
  end

  defp connection_string do
    Application.get_env(
      :exkonsument, :connection_string, "amqp://localhost:5672")
  end
end
