defmodule ExKonsument.Consumer do
  @moduledoc false
  use GenServer

  require Logger

  defstruct queue: nil,
            exchange: nil,
            routing_key: nil,
            handling_fn: nil,
            connection_string: nil,
            state: nil

  def start_link(consumer, opts \\ []) do
    GenServer.start_link(
      __MODULE__, %{consumer: consumer}, opts)
  end

  def init(state) do
    setup_amqp_consumer(state[:consumer])
    {:ok, state}
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

  defp setup_amqp_consumer(consumer) do
    log_info consumer, "Trying to connect to RabbitMQ..."
    case ExKonsument.setup_consumer(consumer) do
      {:ok, connection} ->
        Process.monitor(connection.pid)

      {:error, msg} ->
        log_error(consumer, msg)
        :timer.sleep(1000)
        setup_amqp_consumer(consumer)
    end
    log_info consumer, "Connected successfully!"
  end

  defp log_info(consumer, message) do
    Logger.info "#{consumer.queue.name}: #{message}"
  end

  defp log_error(consumer, message) do
    Logger.error "#{consumer.queue.name}: #{message}"
  end
end
