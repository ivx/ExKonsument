defmodule ExKonsumentTest do
  use ExUnit.Case, async: false

  import Mock

  test "binds to a queue with multiple routing keys" do
    routing_keys = [:first_routing_key, :second_routing_key]

    with_mock AMQP.Queue, bind: fn _, _, _, _ -> :ok end do
      ExKonsument.bind_queue(:channel, :queue, :exchange, routing_keys)

      assert_called(
        AMQP.Queue.bind(
          :channel,
          :queue,
          :exchange,
          routing_key: :first_routing_key
        )
      )

      assert_called(
        AMQP.Queue.bind(
          :channel,
          :queue,
          :exchange,
          routing_key: :second_routing_key
        )
      )
    end
  end

  test "opens channel with prefetch_count set to 1" do
    with_mock AMQP.Connection, open: fn _ -> {:ok, :conn} end do
      with_mock AMQP.Channel, open: fn _ -> {:ok, :chan} end do
        with_mock AMQP.Basic, qos: fn _, _ -> :ok end do
          {:ok, connection} = ExKonsument.open_connection("")
          {:ok, channel} = ExKonsument.open_channel(connection)

          assert_called(AMQP.Basic.qos(channel, prefetch_count: 1))
        end
      end
    end
  end

  test "closes a connection" do
    with_mock AMQP.Connection, close: fn _ -> nil end do
      ExKonsument.close_connection(:connection)
      assert_called(AMQP.Connection.close(:connection))
    end
  end

  test "it knows when a connection is open or closed" do
    {:ok, pid} = Agent.start_link(fn -> nil end)

    connection = %{pid: pid}
    assert ExKonsument.connection_open?(connection)

    Agent.stop(pid)
    refute ExKonsument.connection_open?(connection)
  end

  test "publish calls AMQP.Basic.publish when channel is alive" do
    with_mock AMQP.Basic, publish: fn _, _, _, _, _ -> :ok end do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      assert :ok ==
               ExKonsument.publish(
                 %{pid: agent},
                 :exchange,
                 :routing_key,
                 :payload
               )
    end
  end

  test "publish calls AMQP.Basic.publish with options when channel is alive" do
    with_mock AMQP.Basic, publish: fn _, _, _, _, _ -> :ok end do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      assert :ok ==
               ExKonsument.publish(
                 %{pid: agent},
                 :exchange,
                 :routing_key,
                 :payload,
                 []
               )
    end
  end

  test "publish returns :error if channel is dead" do
    with_mock AMQP.Basic, publish: fn _, _, _, _, _ -> :ok end do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      Agent.stop(agent)

      assert :error ==
               ExKonsument.publish(
                 %{pid: agent},
                 :exchange,
                 :routing_key,
                 :payload
               )
    end
  end
end
