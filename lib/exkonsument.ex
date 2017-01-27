defmodule ExKonsument do
  @moduledoc false
  def open_connection(connection_string) do
    AMQP.Connection.open(connection_string)
  end

  def close_connection(connection) do
    AMQP.Connection.close(connection)
  end

  def open_channel(connection) do
    AMQP.Channel.open(connection)
  end

  def declare_exchange(channel, exchange, type, opts \\ []) do
    AMQP.Exchange.declare(channel, exchange, type, opts)
  end

  def declare_queue(channel, queue \\ "", opts \\ []) do
    AMQP.Queue.declare(channel, queue, opts)
  end

  def publish(channel, exchange, routing_key, payload) do
    AMQP.Basic.publish(channel, exchange, routing_key, payload)
  end

  def bind_queue(channel, queue, exchange, routing_keys) do
    Enum.map(routing_keys, fn key ->
      :ok = AMQP.Queue.bind(channel, queue, exchange, routing_key: key)
    end)
    :ok
  end

  def consume(channel, queue, consumer_pid \\ nil, opts \\ []) do
    AMQP.Basic.consume(channel, queue, consumer_pid, opts)
  end

  def setup_consumer(consumer) do
    with {:ok, connection} <- open_connection(consumer.connection_string),
         true <- Process.link(connection.pid),
         {:ok, channel} <- open_channel(connection),
         :ok <- declare_consumer(channel, consumer),
         {:ok, _} <- consume(channel, consumer.queue.name, nil, no_ack: true) do
      {:ok, connection}
    else
      {:error, error} ->
        {:error, error}
      :error ->
        {:error, :unknown}
    end
  end

  defp declare_consumer(channel, consumer) do
    with :ok <- declare_exchange(channel,
                                 consumer.exchange.name,
                                 consumer.exchange.type,
                                 consumer.exchange.options),
         {:ok, _} <- declare_queue(channel,
                                   consumer.queue.name,
                                   consumer.queue.options),
         :ok <- bind_queue(channel,
                           consumer.queue.name,
                           consumer.exchange.name,
                           consumer.routing_keys) do
      :ok
    else
      _ -> :error
    end
  end
end
