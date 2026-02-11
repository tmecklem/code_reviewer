defmodule CodeReviewer.MixProject do
  use Mix.Project

  def project do
    [
      app: :code_reviewer,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {CodeReviewer.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: ["test"],
      quality: ["format --check-formatted", "credo --strict", "sobelow --config"],
      precommit: ["format", "quality", "test"]
    ]
  end
end
