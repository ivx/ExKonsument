# ExKonsument

A library for RabbitMQ producers and consumers.

## Installation

Just put it in your `mix.exs` and `mix deps.get`.

```elixir
def deps do
  [{:exkonsument, "~> 3.2"}]
end
```

If you have trouble compiling your app make sure to override the lager and
ranch_proxy_protocol dependencies in your application's mix.exs file:

```elixir
def deps do
  [
    {:exkonsument, "~> 3.2"},
    {:lager, "~> 3.6.7", override: true},
    {:ranch_proxy_protocol, "~> 2.0", override: true}
  ]
end
```

## Usage

### RabbitMQ connection

To open a connection to RabbitMQ, start an `ExKonsument.Connection` process. You
can put this in your supervisor. The connection settings can be configured in
your config files like this:

```elixir
config :exkonsument,
  :connection_string,
  "amqp://user:password@yourhost:1234"
```

If you don't configure `ExKonsument`, it uses `amqp://localhost:5672` as the
default. The connection must be passed to producers/consumers later.

#### Connection sharing

You can share a connection between multiple consumers or producers, but never
share a connection between producers and consumers. Due to the producers being
async, this could lead to weird behaviour in case of errors.

### Consumer

Basically you just have to call `ExKonsument.Consumer.start_link` and supply an
`%ExKonsument.Consumer{}` struct. It is recommended to wrap all necessary
information in a dedicated module like this:

```elixir
defmodule YourConsumer do
  @queue %ExKonsument.Queue{name: "yourapp.queue",
                            options: [durable: true]}
  @exchange %ExKonsument.Exchange{name: "yourexchange",
                                  type: topic,
                                  options: [durable: true]}
  @routing_keys ["your.routing.key"]

  def start_link(opts) do
    ExKonsument.Consumer.start_link(consumer_config(), opts)
  end

  defp process_message(payload, _opts, state) do
    # ... do stuff
    :ok
    # :ok will ack the message
    # :requeue will requeue the message
    # any other return value rejects it, only requeueing it if it wasn't
    # redelivered already
  end

  defp consumer_config do
    %ExKonsument.Consumer{
      queue: @queue,
      exchange: @exchange,
      routing_keys: @routing_keys,
      handling_fn: &process_message/3,
      connection: YourApp.Connection,
      state: %{}
    }
  end
end
```

### Producer

This is similar to the consumer, just that you call
`ExKonsument.Producer.start_link` instead. Below is an example:

```elixir
defmodule YourProducer do
  @exchange %ExKonsument.Exchange{name: "yourexchange",
                                  type: topic,
                                  options: [durable: true]}

  def start_link(opts) do
    ExKonsument.Producer.start_link(producer_config(), opts)
  end

  def publish_message(pid) do
    ExKonsument.Producer.publish(pid, "routing.key", %{payload: "as map"})
  end

  defp producer_config do
    %ExKonsument.Producer{
      exchange: @exchange,
      connection: YourApp.Connection
    }
  end
end
```
