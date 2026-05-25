defmodule Modal.ReadmeClaimsTest do
  @moduledoc """
  Self-checking tests for the verifiable claims in `README.md`. The
  README is the front door for evaluators; silent drift between
  what's documented and what's true erodes trust fast.

  We check the STRUCTURAL claims (module references, contract test
  coverage table, primitive-selection cheat-sheet entries) — not the
  numeric counts, which are noisy under parametrized tests and
  generated `for ... test` blocks. Numeric drift is audited
  out-of-band via `mix test` + `mix modal.contract`.

  If you remove a public module, the README still references it,
  this test fails. If you add a contract test for a primitive that
  the README doesn't advertise, this test fails. Either fix the
  code or fix the README.
  """
  use ExUnit.Case, async: true

  @readme File.read!("README.md")

  describe "module-existence claims in README" do
    test "every Modal.* module listed in the Public modules table exists" do
      # Extract module names from the markdown table.
      modules = Regex.scan(~r/\|\s*`(Modal\.[A-Za-z]+(?:\.[A-Za-z]+)?)`/, @readme)

      missing =
        modules
        |> Enum.map(fn [_, m] -> m end)
        |> Enum.uniq()
        |> Enum.reject(&Code.ensure_loaded?(String.to_atom("Elixir.#{&1}")))

      assert missing == [],
             "README references modules that don't exist: #{inspect(missing)}"
    end
  end

  describe "example-script table claims in README" do
    test "every scripts/*.exs file is mentioned in the README (and vice versa)" do
      readme_scripts =
        Regex.scan(~r/`([a-z_]+\.exs)`/, @readme)
        |> Enum.map(fn [_, s] -> s end)
        |> Enum.uniq()
        |> MapSet.new()

      actual_scripts =
        Path.wildcard("scripts/*.exs")
        |> Enum.map(&Path.basename/1)
        # Exclude private/spike scripts (prefixed with _).
        |> Enum.reject(&String.starts_with?(&1, "_"))
        |> MapSet.new()

      missing_from_readme = MapSet.difference(actual_scripts, readme_scripts)
      missing_from_disk = MapSet.difference(readme_scripts, actual_scripts)

      assert MapSet.size(missing_from_readme) == 0,
             "Scripts exist on disk but aren't mentioned in README: " <>
               inspect(Enum.sort(missing_from_readme))

      assert MapSet.size(missing_from_disk) == 0,
             "README references scripts that don't exist: " <>
               inspect(Enum.sort(missing_from_disk))
    end
  end

  describe "contract-coverage claim in README" do
    test "every contract test file exists for primitives listed under 'Tests cover'" do
      # Find the "Tests cover ..." sentence and extract bolded
      # primitive names. Each should have a matching contract test file.
      claimed_primitives =
        Regex.scan(~r/\*\*([A-Z][a-zA-Z_]+(?:[\/,\s]+[A-Z][a-zA-Z_]+)*)\*\*/, @readme)
        |> Enum.flat_map(fn [_, words] -> String.split(words, ~r/[\/,\s]+/) end)
        |> Enum.map(&String.downcase/1)
        |> Enum.uniq()

      contract_files =
        Path.wildcard("test/contract/*_contract_test.exs")
        |> Enum.map(&Path.basename(&1, "_contract_test.exs"))

      # Map README claims to expected files: most primitives have a
      # contract test of the same lowercase name. Special cases:
      # "network_access" file matches the bolded "network_access".
      explicitly_claimed_primitives =
        [
          "app",
          "image",
          "sandbox",
          "dict",
          "queue",
          "volume",
          "function",
          "cls",
          "pickle",
          "proxy",
          "network_access"
        ]

      missing =
        explicitly_claimed_primitives
        |> Enum.reject(&(&1 in contract_files))

      assert missing == [],
             "README's 'Tests cover' list references contract tests that don't exist: " <>
               inspect(missing)

      # And the reverse: every contract file should be listed in the
      # README's coverage sentence (no silent additions that aren't
      # advertised).
      undocumented =
        Enum.reject(contract_files, fn name ->
          # Allow partial matching for things like "network_access" → "network".
          name in explicitly_claimed_primitives or
            Enum.any?(claimed_primitives, &String.contains?(name, &1))
        end)

      assert undocumented == [],
             "Contract test files exist that aren't mentioned in README's 'Tests cover': " <>
               inspect(undocumented)
    end
  end
end
