use Mix.Config

config :logger,
  backends: []

config :ex_unit,
  :assert_receive_timeout, 1000
