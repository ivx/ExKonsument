defmodule ExKonsument.Mixfile do
  use Mix.Project

  def project do
    [
      app: :exkonsument,
      version: "3.1.3",
      elixir: "~> 1.4",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:amqp, "~> 0.2"},
      {:poison, "~> 2.2 or ~> 3.0"},
      {:connection, "~> 1.0"},
      {:credo, "~> 0.7", only: :dev},
      {:mock, "~> 0.2", only: :test}
    ]
  end
end
