defmodule ExKonsument.Producer do
  @moduledoc false
  use GenServer

  require Logger

  defstruct exchange: nil,
            connection: nil

  def start_link(%ExKonsument.Producer{} = producer, opts \\ []) do
    GenServer.start_link(__MODULE__, producer, opts)
  end

  def init(producer) do
    send self(), :connect
    {:ok, %{producer: producer}}
  end

  def publish(pid, routing_key, payload) do
    GenServer.call(pid, {:publish, routing_key, payload})
  end

  def handle_call({:publish, routing_key, payload}, _, state) do
    result = ExKonsument.publish(
      state.channel,
      state.producer.exchange.name,
      routing_key,
      Poison.encode!(payload))

    {:reply, result, state}
  end

  def handle_info(:connect, %{producer: producer} = state) do
    log_info producer, "Trying to get channel..."
    case ExKonsument.Connection.open_channel(producer.connection) do
      {:ok, channel} ->
        log_info producer, "Got channel!"
        :ok = declare_exchange(channel, producer.exchange)
        {:noreply, Map.put(state, :channel, channel)}

      _ ->
        log_error producer, "Error getting channel"
        :timer.send_after(2000, :connect)
        {:noreply, state}
    end
  end

  def handle_info({:channel_closed, _channel}, state) do
    log_info state.producer, "Channel was closed"
    send self(), :connect
    {:noreply, state}
  end

  defp declare_exchange(channel, exchange) do
    ExKonsument.declare_exchange(
      channel,
      exchange.name,
      exchange.type,
      exchange.options)
  end

  defp log_info(producer, message) do
    Logger.info "Producer '#{producer.exchange.name}': #{message}"
  end

  defp log_error(producer, message) do
    Logger.error "Producer '#{producer.exchange.name}': #{message}"
  end
end
