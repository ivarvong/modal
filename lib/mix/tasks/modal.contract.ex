defmodule Mix.Tasks.Modal.Contract do
  @moduledoc """
  Run the contract test suite — tests that hit real Modal to verify
  the library's mocks match the live API.

      mix modal.contract            # run all
      mix modal.contract --only dict    # forward to ExUnit (--only dict)

  ## What contract tests are

  Unit tests in `test/modal/` use Mox to simulate Modal's responses
  — fast, deterministic, but their guarantees only hold as long as
  the mocks describe what Modal actually returns. Contract tests in
  `test/contract/` are the bridge: they hit live Modal endpoints
  and assert the response shapes our mocks promise. If Modal renames
  a field, drops an opcode, or changes a wire convention, the
  contract suite fails *before* a user notices.

  Each test is cheap (single RPC for shape checks; full
  deploy+invoke for lifecycle tests). The suite runs in ~30s on a
  warm Modal account.

  ## Requirements

    * `MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET` env vars (modal.com)
    * Some tests need `PYTHON_BIN` pointing at a Python with the
      `modal` package installed — those skip cleanly without it.

  Refusing to run without credentials is intentional: contract
  tests are not safe to silently no-op (a clean run would be
  indistinguishable from "tests didn't actually verify anything").
  """
  use Mix.Task

  @shortdoc "Run contract tests against live Modal"

  @impl Mix.Task
  def run(args) do
    check_credentials!()

    Mix.Task.run("test", ["--only", "contract" | args])
  end

  defp check_credentials! do
    missing =
      ["MODAL_TOKEN_ID", "MODAL_TOKEN_SECRET"]
      |> Enum.filter(&(System.get_env(&1) in [nil, ""]))

    if missing != [] do
      Mix.shell().error("""

      Contract tests require Modal credentials:

        #{Enum.join(missing, ", ")}

      Set them in your environment (or load a .env file before running):

        export MODAL_TOKEN_ID=...
        export MODAL_TOKEN_SECRET=...

      Then re-run:

        mix modal.contract
      """)

      System.halt(1)
    end
  end
end
