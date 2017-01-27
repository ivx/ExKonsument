defmodule ExKonsument.Consumer do
  @moduledoc false
  use GenServer

  require Logger

  defstruct queue: nil,
            exchange: nil,
            routing_keys: nil,
            handling_fn: nil,
            connection_string: nil,
            state: nil

  def start_link(consumer, opts \\ []) do
    GenServer.start_link(
      __MODULE__, %{consumer: consumer}, opts)
  end

  def init(state) do
    Process.flag(:trap_exit, true)
    new_state = connect(state)
    {:ok, new_state}
  end

  def handle_info({:basic_consume_ok, _}, state) do
    log_info state.consumer, "Registration successful!"
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, opts}, state) do
    consumer = state.consumer
    log_info consumer, "Message received!"

    case Poison.decode(payload) do
      {:ok, parsed_payload} ->
        consumer.handling_fn.(parsed_payload, opts, consumer.state)
        log_info consumer, "Message handled!"

      {:error, _} ->
        log_error consumer, "Message could not be processed!"
    end

    {:noreply, state}
  end

  def handle_info(:connect, state) do
    new_state = connect(state)
    {:noreply, new_state}
  end

  def handle_info({:basic_cancel, _}, state) do
    log_info state.consumer, "Consuming canceled, committing suicide."
    {:stop, :shutdown, state}
  end

  def handle_info({:basic_cancel_ok, _}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _, _}, state) do
    log_info state.consumer, "Connection died, committing suicide."
    {:stop, :shutdown, state}
  end

  defp connect(state) do
    result = state
    |> Map.get(:consumer)
    |> setup_amqp_consumer

    case result do
      {:ok, channel} -> Map.put(state, :channel, channel)
      {:error, _reason} -> Map.put(state, :channel, nil)
    end
  end

  defp setup_amqp_consumer(consumer) do
    log_info consumer, "Trying to connect to RabbitMQ..."
    case setup_consumer(consumer) do
      {:ok, connection} ->
        log_info consumer, "Connected successfully!"
        {:ok, connection}

      {:error, msg} ->
        log_error(consumer, msg)
        :timer.send_after(1000, :connect)
    end
  end

  defp log_info(consumer, message) do
    Logger.info "#{consumer.queue.name}: #{message}"
  end

  defp log_error(consumer, message) do
    Logger.error "#{consumer.queue.name}: #{message}"
  end

  defp setup_consumer(consumer) do
    with {:ok, connection} <- ExKonsument.open_connection(consumer.connection_string),
         {:ok, channel} <- ExKonsument.open_channel(connection),
         true <- Process.link(connection.pid),
         :ok <- declare_consumer(channel, consumer),
         {:ok, _} <- ExKonsument.consume(channel, consumer.queue.name, nil, no_ack: true) do
      {:ok, channel}
    else
      {:error, error} ->
        {:error, error}
      :error ->
        {:error, :unknown}
    end
  end

  defp declare_consumer(channel, consumer) do
    with :ok <- ExKonsument.declare_exchange(channel,
                                 consumer.exchange.name,
                                 consumer.exchange.type,
                                 consumer.exchange.options),
         {:ok, _} <- ExKonsument.declare_queue(channel,
                                   consumer.queue.name,
                                   consumer.queue.options),
         :ok <- ExKonsument.bind_queue(channel,
                                       consumer.queue.name,
                                       consumer.exchange.name,
                                       consumer.routing_keys) do
      :ok
    else
      _ -> :error
    end
  end

  def terminate(_reason, state) do
    if ExKonsument.connection_open?(state.channel.conn) do
      ExKonsument.close_connection(state.channel.conn)
    end
  end
end
