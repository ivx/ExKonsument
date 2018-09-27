defmodule ExKonsument.Mixfile do
  use Mix.Project

  def project do
    [
      app: :exkonsument,
      version: "3.2.3",
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :connection]]
  end

  defp description do
    """
    A library for writing RabbitMQ pubishers and consumers.
    """
  end

  defp package do
    [
      name: :exkonsument,
      files: ["lib", "mix.exs", "README*", "LICENSE"],
      maintainers: ["Mario Mainz, Alexander Marold"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/ivx/exkonsument"}
    ]
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
      {:amqp, "~> 1.0"},
      {:poison, "~> 3.0 or ~> 4.0"},
      {:connection, "~> 1.0"},
      {:credo, "~> 0.9", only: [:dev, :test]},
      {:mock, "~> 0.2", only: :test},
      # delete me when everything is OTP 21 compatible
      {:meck, "0.8.10", only: :test},
      {:ranch_proxy_protocol, "~> 2.0", override: true}
    ]
  end
end
