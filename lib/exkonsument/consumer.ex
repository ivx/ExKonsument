defmodule ExKonsument.Consumer do
  @moduledoc false
  use GenServer

  require Logger

  defstruct queue: nil,
            exchange: nil,
            routing_keys: nil,
            handling_fn: nil,
            connection: nil,
            state: nil

  def start_link(consumer, opts \\ []) do
    GenServer.start_link(__MODULE__, %{consumer: consumer}, opts)
  end

  def init(state) do
    new_state = connect(state)
    {:ok, new_state}
  end

  def handle_info({:basic_consume_ok, _}, state) do
    log_info state.consumer, "Registration successful!"
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, opts}, state) do
    log_info state.consumer, "Message received!"

    case Poison.decode(payload) do
      {:ok, parsed_payload} ->
        consume_message(parsed_payload, opts, state)
        log_info state.consumer, "Message handled!"

      {:error, _} ->
        ExKonsument.reject(
          state.channel, Map.get(opts, :delivery_tag), requeue: false)
        log_error state.consumer, "Message could not be processed!"
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

  def handle_info({:channel_closed, _channel}, state) do
    log_info state.consumer, "Channel was closed"
    send self(), :connect
    {:noreply, state}
  end

  defp handle_message(consumer, payload, opts) do
    case consumer.handling_fn.(payload, opts, consumer.state) do
      :ok -> :ok
      _ -> raise ExKonsument.HandlingError
    end
  end

  defp consume_message(message, opts, state) do
    try do
      :ok = handle_message(state.consumer, message, opts)
      ExKonsument.ack(state.channel, Map.get(opts, :delivery_tag))
    rescue
      exception ->
        ExKonsument.reject(
          state.channel,
          Map.get(opts, :delivery_tag),
          requeue: not Map.get(opts, :redelivered))
        log_info state.consumer,
          "Message rejected! requeued: #{not Map.get(opts, :redelivered)}"
        raise exception
    end
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
    log_info consumer, "Trying to setup consumer..."
    case setup_consumer(consumer) do
      {:ok, channel} ->
        log_info consumer, "Setup successful!"
        {:ok, channel}

      {:error, msg} = error ->
        log_error(consumer, "Setup failed! reason: #{msg}")
        :erlang.send_after(1000, self(), :connect)
        error
    end
  end

  defp setup_consumer(%{connection: connection} = consumer) do
    with {:ok, channel} <- ExKonsument.Connection.open_channel(connection),
         :ok <- declare_exchange(channel, consumer.exchange),
         {:ok, _} <- declare_queue(channel, consumer.queue),
         :ok <- bind_queue(channel, consumer),
         {:ok, _} <- ExKonsument.consume(channel, consumer.queue.name) do
      {:ok, channel}
    else
      {:error, error} -> {:error, error}
      _ -> {:error, :unknown}
    end
  end

  defp declare_exchange(channel, exchange) do
    ExKonsument.declare_exchange(channel,
                                 exchange.name,
                                 exchange.type,
                                 exchange.options)
  end

  defp declare_queue(channel, queue) do
    ExKonsument.declare_queue(channel, queue.name, queue.options)
  end

  defp bind_queue(channel, consumer) do
    ExKonsument.bind_queue(channel,
                           consumer.queue.name,
                           consumer.exchange.name,
                           consumer.routing_keys)
  end

  defp log_info(consumer, message) do
    Logger.info "Consumer '#{consumer.queue.name}': #{message}"
  end

  defp log_error(consumer, message) do
    Logger.error "Consumer '#{consumer.queue.name}': #{message}"
  end
end
