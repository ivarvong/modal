defmodule Modal.CredentialsTest do
  use ExUnit.Case, async: false

  # async: false because we mutate process-level environment variables
  # (MODAL_TOKEN_ID, MODAL_TOKEN_SECRET, MODAL_PROFILE, MODAL_CONFIG_PATH)
  # via System.put_env / System.delete_env. Letting two test cases
  # set them concurrently would produce flaky results.

  @env_keys ~w(MODAL_TOKEN_ID MODAL_TOKEN_SECRET MODAL_PROFILE MODAL_CONFIG_PATH)

  setup do
    # Snapshot and restore env, so the suite stays hermetic and the
    # developer's real Modal credentials never leak in or out.
    previous = Map.new(@env_keys, fn k -> {k, System.get_env(k)} end)
    Enum.each(@env_keys, &System.delete_env/1)

    on_exit(fn ->
      for {k, v} <- previous do
        if v, do: System.put_env(k, v), else: System.delete_env(k)
      end
    end)

    :ok
  end

  describe "env path" do
    test "loads from MODAL_TOKEN_ID + MODAL_TOKEN_SECRET" do
      System.put_env("MODAL_TOKEN_ID", "ak-env-id")
      System.put_env("MODAL_TOKEN_SECRET", "as-env-secret")

      assert {:ok, [token_id: "ak-env-id", token_secret: "as-env-secret"]} =
               Modal.Credentials.load()
    end

    test "ignores the toml file when env is set" do
      System.put_env("MODAL_TOKEN_ID", "ak-env")
      System.put_env("MODAL_TOKEN_SECRET", "as-env")

      System.put_env(
        "MODAL_CONFIG_PATH",
        write_toml(~s([toml]\ntoken_id = "ak-toml"\ntoken_secret = "as-toml"\n))
      )

      # env should win
      assert {:ok, [token_id: "ak-env", token_secret: "as-env"]} = Modal.Credentials.load()
    end
  end

  describe "toml path" do
    test "loads the only profile when there's one" do
      path =
        write_toml("""
        [ivar]
        token_id = "ak-onlyone"
        token_secret = "as-onlyone"
        active = true
        """)

      System.put_env("MODAL_CONFIG_PATH", path)

      assert {:ok, [token_id: "ak-onlyone", token_secret: "as-onlyone"]} =
               Modal.Credentials.load()
    end

    test "honors :profile opt over active=true" do
      path =
        write_toml("""
        [default]
        token_id = "ak-default"
        token_secret = "as-default"
        active = true

        [staging]
        token_id = "ak-staging"
        token_secret = "as-staging"
        """)

      System.put_env("MODAL_CONFIG_PATH", path)

      assert {:ok, [token_id: "ak-staging", token_secret: "as-staging"]} =
               Modal.Credentials.load(profile: "staging")
    end

    test "honors MODAL_PROFILE when :profile not given" do
      path =
        write_toml("""
        [default]
        token_id = "ak-default"
        token_secret = "as-default"
        active = true

        [staging]
        token_id = "ak-staging"
        token_secret = "as-staging"
        """)

      System.put_env("MODAL_CONFIG_PATH", path)
      System.put_env("MODAL_PROFILE", "staging")

      assert {:ok, [token_id: "ak-staging", token_secret: "as-staging"]} =
               Modal.Credentials.load()
    end

    test ":profile opt beats MODAL_PROFILE" do
      path =
        write_toml("""
        [a]
        token_id = "ak-a"
        token_secret = "as-a"

        [b]
        token_id = "ak-b"
        token_secret = "as-b"
        """)

      System.put_env("MODAL_CONFIG_PATH", path)
      System.put_env("MODAL_PROFILE", "a")

      assert {:ok, [token_id: "ak-b", token_secret: "as-b"]} =
               Modal.Credentials.load(profile: "b")
    end

    test "falls back to active=true when neither :profile nor MODAL_PROFILE given" do
      path =
        write_toml("""
        [first]
        token_id = "ak-first"
        token_secret = "as-first"

        [middle]
        token_id = "ak-middle"
        token_secret = "as-middle"
        active = true

        [last]
        token_id = "ak-last"
        token_secret = "as-last"
        """)

      System.put_env("MODAL_CONFIG_PATH", path)

      assert {:ok, [token_id: "ak-middle", token_secret: "as-middle"]} =
               Modal.Credentials.load()
    end

    test "falls back to first profile when no active=true marker" do
      path =
        write_toml("""
        [first]
        token_id = "ak-first"
        token_secret = "as-first"

        [last]
        token_id = "ak-last"
        token_secret = "as-last"
        """)

      System.put_env("MODAL_CONFIG_PATH", path)

      assert {:ok, [token_id: "ak-first", token_secret: "as-first"]} =
               Modal.Credentials.load()
    end

    test "tolerates blank lines and comments" do
      path =
        write_toml("""
        # This is the production profile

        [prod]
        token_id = "ak-prod"
        # secret rotated 2026-01-01
        token_secret = "as-prod"
        active = true
        """)

      System.put_env("MODAL_CONFIG_PATH", path)

      assert {:ok, [token_id: "ak-prod", token_secret: "as-prod"]} =
               Modal.Credentials.load()
    end

    test "tolerates extra fields per profile (forward-compat)" do
      path =
        write_toml("""
        [prod]
        token_id = "ak-prod"
        token_secret = "as-prod"
        environment = "main"
        future_field = "unknown"
        """)

      System.put_env("MODAL_CONFIG_PATH", path)
      assert {:ok, _} = Modal.Credentials.load()
    end
  end

  describe "errors" do
    test "returns :credentials_missing when no env and no file" do
      System.put_env(
        "MODAL_CONFIG_PATH",
        Path.join(System.tmp_dir!(), "definitely-does-not-exist.toml")
      )

      assert {:error, %Modal.Error{kind: :credentials_missing, message: msg}} =
               Modal.Credentials.load()

      assert msg =~ "MODAL_TOKEN_ID"
      assert msg =~ "modal token set"
    end

    test "returns :credentials_missing when profile not found in file" do
      path =
        write_toml("""
        [prod]
        token_id = "ak-prod"
        token_secret = "as-prod"
        """)

      System.put_env("MODAL_CONFIG_PATH", path)

      assert {:error, %Modal.Error{kind: :credentials_missing, message: msg}} =
               Modal.Credentials.load(profile: "nonexistent")

      assert msg =~ "nonexistent"
    end

    test "load!/1 raises with the same message" do
      System.put_env("MODAL_CONFIG_PATH", "/definitely/not/a/file")

      assert_raise Modal.Error, ~r/credentials not found/i, fn ->
        Modal.Credentials.load!()
      end
    end
  end

  describe "splat-into-start_link shape" do
    test "load!/1 returns a keyword list with :token_id and :token_secret" do
      System.put_env("MODAL_TOKEN_ID", "ak-x")
      System.put_env("MODAL_TOKEN_SECRET", "as-x")

      creds = Modal.Credentials.load!()
      assert Keyword.keyword?(creds)
      assert Keyword.fetch!(creds, :token_id) == "ak-x"
      assert Keyword.fetch!(creds, :token_secret) == "as-x"
    end
  end

  # ── helpers ─────────────────────────────────────────────────────

  defp write_toml(content) do
    path =
      Path.join(
        System.tmp_dir!(),
        "modal-credentials-test-#{System.unique_integer([:positive])}.toml"
      )

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
