defmodule Modal.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ivarvong/modal"
  @description "Elixir client for Modal sandboxes: gRPC-native, streaming exec, snapshot/restore, filesystem I/O."

  def project do
    [
      app: :modal,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      config_path: "config/config.exs",
      deps: deps(),
      dialyzer: dialyzer(),
      name: "Modal",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: ["modal.contract": :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Modal.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:grpc, "~> 0.11.5"},
      {:castore, "~> 1.0"},
      {:protobuf, "~> 0.16.0"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:req, "~> 0.5"},
      {:telemetry, "~> 1.0"},
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.3", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      # `:ex_unit` is here because `test/support/contract_support.ex`
      # imports `ExUnit.Assertions`, and dialyzer runs under MIX_ENV=test
      # to include test/support — without it, the `assert/2` macro
      # expansion fails the `:unknown` warning check.
      plt_add_apps: [:mix, :ex_unit],
      plt_local_path: "priv/plts/local.plt",
      plt_core_path: "priv/plts/core.plt"
    ]
  end

  defp package do
    [
      maintainers: ["Ivar Vong"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib guides mix.exs README.md CONTRIBUTING.md LICENSE NOTICE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/ship_checklist.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "NOTICE"
      ],
      groups_for_extras: [
        Guides: ["guides/ship_checklist.md"],
        Reference: ["LICENSE", "NOTICE"]
      ],
      groups_for_modules: [
        "Public API": [
          Modal,
          Modal.Client,
          Modal.App,
          Modal.Image,
          Modal.Sandbox,
          Modal.ContainerProcess,
          Modal.Filesystem,
          Modal.Function,
          Modal.FunctionCall,
          Modal.Cls,
          Modal.Period,
          Modal.Cron,
          Modal.Dict,
          Modal.Queue,
          Modal.Pickle,
          Modal.Secret,
          Modal.Volume,
          Modal.Proxy,
          Modal.CloudBucket,
          Modal.Tunnel,
          Modal.Credentials,
          Modal.Error,
          Modal.Telemetry,
          Modal.RPC
        ],
        "Testing seams": [
          Modal.Client.Behaviour,
          Modal.ModalStub.Behaviour,
          Modal.TaskCommandRouter.Behaviour
        ]
        # Internal modules (Modal.Application, Modal.Backoff, Modal.JWT)
        # are @moduledoc false and intentionally invisible to ExDoc;
        # listing them in a group would warn about hidden references.
      ]
    ]
  end
end
