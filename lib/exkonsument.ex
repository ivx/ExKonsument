defmodule ExKonsument do
  @moduledoc false
  def open_connection(connection_string) do
    AMQP.Connection.open(connection_string)
  end

  def close_connection(connection) do
    AMQP.Connection.close(connection)
  end

  def connection_open?(connection) do
    Process.alive?(connection.pid)
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
    Enum.each(routing_keys, fn key ->
      :ok = AMQP.Queue.bind(channel, queue, exchange, routing_key: key)
    end)
    :ok
  end

  def consume(channel, queue, consumer_pid \\ nil, opts \\ []) do
    AMQP.Basic.consume(channel, queue, consumer_pid, opts)
  end
end
