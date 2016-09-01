defmodule ExKonsument.Producer do
  @moduledoc false
  use GenServer

  require Logger

  defstruct exchange: nil,
            connection_string: nil

  def start_link(producer, opts \\ []) do
    GenServer.start_link(__MODULE__, producer, opts)
  end

  def init(producer) do
    {:ok, channel} = setup_amqp_producer(producer)
    state = %{producer: producer, channel: channel}
    {:ok, state}
  end

  defp setup_amqp_producer(%ExKonsument.Producer{} = producer) do
    log_info producer, "Producer trying to connect to RabbitMQ..."
    connection_string = producer.connection_string
    with {:ok, connection} <- ExKonsument.open_connection(connection_string),
         {:ok, channel} = ExKonsument.open_channel(connection) do
      Process.monitor(connection.pid)
      log_info producer, "Connected successfully!"
      {:ok, channel}
    else
      {:error, msg} ->
        log_error(producer, msg)
        :timer.send_after(1000, :connect)
    end
  end

  def publish(pid, payload, routing_key) do
    GenServer.call(pid, {:publish, payload, routing_key})
  end

  def handle_call({:publish, payload, routing_key}, _, state) do
    result = send_event(
      state.channel,
      state.producer.exchange,
      routing_key,
      payload
    )

    {:reply, result, state}
  end

  defp send_event(channel, exchange, routing_key, payload) do
    :ok = ExKonsument.declare_exchange(
      channel,
      exchange.name,
      exchange.type,
      exchange.options
    )
    ExKonsument.publish(
      channel,
      exchange.name,
      routing_key,
      Poison.encode!(payload))
  end

  def handle_info(:connect, state) do
    {:ok, channel} = state
    |> Map.get(:producer)
    |> setup_amqp_producer

    new_state = Map.put(state, :channel, channel)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _, :process, _, _}, state) do
    log_info state.producer, "Connection died, committing suicide."
    {:stop, :shutdown, state}
  end

  defp log_info(producer, message) do
    Logger.info "#{producer.exchange.name}: #{message}"
  end

  defp log_error(producer, message) do
    Logger.error "#{producer.exchange.name}: #{message}"
  end
end
