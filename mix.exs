defmodule ExKonsument.Mixfile do
  use Mix.Project

  def project do
    [
      app: :exkonsument,
      version: "3.2.0",
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
    [applications: [:logger]]
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
      {:poison, "~> 2.2 or ~> 3.0"},
      {:connection, "~> 1.0"},
      {:credo, "~> 0.9", only: :dev},
      {:mock, "~> 0.2", only: :test}
    ]
  end
end
