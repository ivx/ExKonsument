defmodule ExKonsument.Mixfile do
  use Mix.Project

  def project do
    [
      app: :exkonsument,
      version: "4.2.0",
      elixir: "~> 1.13",
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
    [extra_applications: [:logger]]
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
      {:amqp, "~> 3.0"},
      {:jason, "~> 1.0"},
      {:connection, "~> 1.0"},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:mock, "~> 0.2", only: :test}
    ]
  end
end
