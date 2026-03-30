defmodule Modal.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ivarvong/modal"

  def project do
    [
      app: :modal,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      name: "Modal",
      description: "Elixir client for the Modal.com API",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:grpc, "~> 0.11.5"},
      {:castore, "~> 1.0"},
      {:protobuf, "~> 0.16.0"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE NOTICE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "Modal",
      extras: ["README.md"]
    ]
  end
end
