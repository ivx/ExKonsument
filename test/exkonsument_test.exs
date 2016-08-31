defmodule ExKonsumentTest do
  use ExUnit.Case, async: false

  import Mock

  test "setting up consumer fails gracefully" do
    with_mock AMQP.Connection, [open: fn _ -> {:error, nil} end] do
      assert {:error, nil} ==
        ExKonsument.setup_consumer(%{connection_string: ""})
    end
  end

  test "setting up consumer fails for every return value" do
    with_mock AMQP.Connection, [open: fn _ -> :error end] do
      assert {:error, :unknown} ==
        ExKonsument.setup_consumer(%{connection_string: ""})
    end
  end

  test "closes a connection" do
    with_mock AMQP.Connection, [close: fn _ -> nil end] do
      ExKonsument.close_connection(:connection)
      assert called AMQP.Connection.close(:connection)
    end
  end
end
