defmodule Modal.Contract.Support do
  @moduledoc """
  Shared setup for contract tests.

  Contract tests verify that the real Modal API returns responses in the exact
  shape that our Mox mocks simulate. They are the bridge between fast unit tests
  and slow integration tests — cheap to run (single RPC each), but they catch
  mock drift before it reaches production.

  Run with:

      mix test --include contract

  Requires MODAL_TOKEN_ID and MODAL_TOKEN_SECRET environment variables.

  ## Strict field assertions

  Use `assert_struct_shape/2` rather than `Map.has_key?(resp, :field)`:

      assert_struct_shape(resp, %{
        sandbox_id: {:string_prefix, "sb-"},
        # … every field the mock relies on …
      })

  The helper enforces:

    * The response value is the exact struct type passed (catches a server
      response renamed to a different message type).
    * Every key in the expectation map is present AND matches the typed
      check (catches a renamed field — `Map.has_key?` would have to be
      rewritten if `sandbox_id` ever became `sb_id`; the strict check
      fails immediately).
    * No key in the expectation is a typo not in the struct's defined
      fields (catches a typo in the test, not in the mock).

  See `assert_struct_shape/2` and the supported check shapes below.
  """

  import ExUnit.Assertions

  def client! do
    token_id = System.get_env("MODAL_TOKEN_ID")
    token_secret = System.get_env("MODAL_TOKEN_SECRET")

    unless token_id && token_secret do
      raise "Contract tests require MODAL_TOKEN_ID and MODAL_TOKEN_SECRET"
    end

    Application.put_env(:modal, :client_impl, Modal.Client)
    {:ok, client} = Modal.Client.start_link(token_id: token_id, token_secret: token_secret)
    client
  end

  @doc """
  The Modal app name contract tests deploy into, namespaced per run.

  Every contract file used to share the single fixed name
  `"elixir-contract-test"`. Because `Modal.App.lookup/3` is
  get-or-create, two CI runs hitting the account at the same time
  (e.g. a `main` push overlapping a PR push) deployed into the *same*
  app and raced each other's `AppPublish` — whichever run published
  second re-pointed the shared `{tag => function_id}` routing table,
  so the other run's just-deployed function 404'd
  (`No Function with ID …`) or its container came back
  `GENERIC_STATUS_TERMINATED`. Namespacing the app by run removes the
  shared mutable state, so concurrent runs can't collide.

  `GITHUB_RUN_ID` is unique per CI run (and stable across a re-run, so
  a re-run reuses its own app rather than spawning a new one). Locally
  it falls back to a per-user-stable name so repeated `mix modal.contract`
  runs reuse one app instead of accumulating.

  > Note: there's no teardown — `Modal.App` has no stop/delete RPC yet,
  > so these apps linger. That's a known follow-up (add `App.stop/2`),
  > tracked separately; correctness (no cross-run collisions) comes first.
  """
  @spec app_name() :: String.t()
  def app_name do
    "elixir-contract-test-" <> run_slug()
  end

  defp run_slug do
    System.get_env("GITHUB_RUN_ID") || "local-#{System.get_env("USER") || "dev"}"
  end

  @doc """
  Strict field-and-shape assertion for protobuf response structs.

  Each entry in `checks` maps a field name to a typed check. Supported
  check shapes:

    * `:string` — the value is a binary
    * `{:string_prefix, prefix}` — the value is a binary starting with `prefix`
    * `:integer` — the value is an integer
    * `:non_neg_integer` — integer ≥ 0
    * `:float` — the value is a float
    * `:list` — the value is a list (length unconstrained)
    * `{:list_of, check}` — list whose every element passes `check`
    * `:nil_or` — special form `{:nil_or, check}` allows nil or `check`
    * `nil` — the value is exactly nil
    * `{:enum, allowed}` — the value is in `allowed` (list of atoms)
    * `{:struct, module}` — the value is a struct of that module
    * `{:fun, fun}` — `fun.(value)` returns truthy
    * literal — strict equality (`==`)

  Catches three categories of drift in one assertion:

    * Field rename (server returns `sb_id`, our struct still defines
      `sandbox_id` — protobuf decode places it under `__unknown_fields__`,
      so this assertion fails).
    * Unit change (`timeout_secs` → `timeout_ms` flips the value range).
    * Enum rename (`:GENERIC_STATUS_SUCCESS` → `:STATUS_OK`).
  """
  @spec assert_struct_shape(struct(), map()) :: :ok
  def assert_struct_shape(%mod{} = value, checks) when is_map(checks) do
    struct_fields = mod.__struct__() |> Map.from_struct() |> Map.keys() |> MapSet.new()

    for key <- Map.keys(checks) do
      assert MapSet.member?(struct_fields, key),
             "field #{inspect(key)} is not defined on #{inspect(mod)} — " <>
               "this is either a typo in the test, or the struct was regenerated " <>
               "without #{inspect(key)} (a server-side field rename)"
    end

    for {key, check} <- checks do
      actual = Map.fetch!(value, key)

      assert match_check(actual, check),
             "field #{inspect(mod)}.#{key} = #{inspect(actual)} did not match " <>
               "expected shape #{inspect(check)}"
    end

    :ok
  end

  defp match_check(v, :string), do: is_binary(v)
  defp match_check(v, :integer), do: is_integer(v)
  defp match_check(v, :non_neg_integer), do: is_integer(v) and v >= 0
  defp match_check(v, :float), do: is_float(v)
  defp match_check(v, :list), do: is_list(v)
  defp match_check(nil, nil), do: true

  defp match_check(v, {:string_prefix, p}) when is_binary(p),
    do: is_binary(v) and String.starts_with?(v, p)

  defp match_check(v, {:list_of, inner}),
    do: is_list(v) and Enum.all?(v, &match_check(&1, inner))

  defp match_check(nil, {:nil_or, _}), do: true
  defp match_check(v, {:nil_or, inner}), do: match_check(v, inner)
  defp match_check(v, {:enum, allowed}) when is_list(allowed), do: v in allowed
  defp match_check(%mod{}, {:struct, mod}), do: true
  defp match_check(_v, {:struct, _mod}), do: false
  defp match_check(v, {:fun, f}) when is_function(f, 1), do: !!f.(v)
  defp match_check(v, literal), do: v == literal
end
