defmodule Modal.Credentials do
  @moduledoc """
  Load Modal API credentials from the environment or from the
  user's `~/.modal.toml` profile file.

  Mirrors the precedence Modal's Python CLI uses:

    1. **Environment variables** — `MODAL_TOKEN_ID` + `MODAL_TOKEN_SECRET`
       take precedence if both are set. CI-friendly; no file touched.
    2. **`~/.modal.toml`** (or `$MODAL_CONFIG_PATH` if set) — written
       by `modal token set`. Multi-profile; the profile to use is
       chosen by, in order:
         * the `:profile` option to `load/1`
         * the `MODAL_PROFILE` environment variable
         * the profile marked `active = true` in the file
         * the first profile in the file

  Designed to splat directly into `Modal.Client.start_link/1`:

      {:ok, client} = Modal.Client.start_link(Modal.Credentials.load!())

  ## Error handling

  `load/1` returns `{:error, %Modal.Error{kind: :credentials_missing}}`
  when no credentials are reachable (env unset AND no readable config
  file AND no matching profile). The error message tells the caller
  exactly which paths and env vars were tried.

  `load!/1` raises the same error.
  """

  @env_token_id "MODAL_TOKEN_ID"
  @env_token_secret "MODAL_TOKEN_SECRET"
  @env_profile "MODAL_PROFILE"
  @env_config_path "MODAL_CONFIG_PATH"
  @default_config_path "~/.modal.toml"

  @typedoc """
  Keyword list ready to splat into `Modal.Client.start_link/1`.
  """
  @type creds :: [token_id: String.t(), token_secret: String.t()]

  @doc """
  Look up credentials. Returns `{:ok, [token_id: ..., token_secret: ...]}`
  on success, or `{:error, %Modal.Error{kind: :credentials_missing}}`.

  ## Options

    * `:profile` — explicit profile name to load from the config
      file. Overrides `$MODAL_PROFILE` and any `active = true`
      marker. Ignored if the env vars are set (env wins).
  """
  @spec load(keyword()) :: {:ok, creds()} | {:error, Modal.Error.t()}
  def load(opts \\ []) do
    case env_credentials() do
      {:ok, _} = ok -> ok
      :no_env -> toml_credentials(opts)
    end
  end

  @doc "Like `load/1` but raises on missing credentials."
  @spec load!(keyword()) :: creds()
  def load!(opts \\ []) do
    case load(opts) do
      {:ok, creds} -> creds
      {:error, %Modal.Error{} = err} -> raise err
    end
  end

  # ── env path ────────────────────────────────────────────────────

  defp env_credentials do
    case {System.get_env(@env_token_id), System.get_env(@env_token_secret)} do
      {id, secret} when is_binary(id) and is_binary(secret) ->
        {:ok, [token_id: id, token_secret: secret]}

      _ ->
        :no_env
    end
  end

  # ── ~/.modal.toml path ──────────────────────────────────────────

  defp toml_credentials(opts) do
    path = config_path()

    with {:ok, body} <- read_config(path),
         profile when not is_nil(profile) <- pick_profile(body, opts),
         {:ok, creds} <- extract_creds(profile) do
      {:ok, creds}
    else
      {:error, %Modal.Error{} = e} -> {:error, e}
      _ -> {:error, credentials_missing_error(path, opts)}
    end
  end

  defp config_path do
    case System.get_env(@env_config_path) do
      nil -> Path.expand(@default_config_path)
      "" -> Path.expand(@default_config_path)
      override -> Path.expand(override)
    end
  end

  defp read_config(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, _} -> :no_file
    end
  end

  # Parse `.modal.toml` into `[{profile_name, %{key => value}}]`. The
  # file format is minimal TOML — section headers, `key = "value"` and
  # `key = true|false` lines, blank lines, comments. We don't depend
  # on a full TOML parser because Modal's file is constrained to this
  # subset and we don't want a dep just for credentials.
  #
  # Field keys stay as strings (not atoms) so we never call
  # `String.to_atom` on user-supplied input — leaks unbounded atom
  # creation if a malformed file slipped in something weird.
  defp parse_profiles(body) do
    body
    |> String.split("\n")
    |> Enum.reduce({nil, %{}, []}, &absorb_line/2)
    |> finalize_profiles()
    |> Enum.reverse()
  end

  defp absorb_line(raw, {current, fields, acc}) do
    line = String.trim(raw)

    cond do
      line == "" or String.starts_with?(line, "#") ->
        {current, fields, acc}

      match = Regex.run(~r/^\[(.+?)\]$/, line) ->
        open_section(match, current, fields, acc)

      match = Regex.run(~r/^([A-Za-z0-9_]+)\s*=\s*"(.*)"$/, line) ->
        [_, key, value] = match
        {current, Map.put(fields, key, value), acc}

      match = Regex.run(~r/^([A-Za-z0-9_]+)\s*=\s*(true|false)$/, line) ->
        [_, key, value] = match
        {current, Map.put(fields, key, value == "true"), acc}

      true ->
        # Unknown line shape — ignore for forward-compat. A real
        # malformed file will surface as "no readable profiles."
        {current, fields, acc}
    end
  end

  defp open_section([_, name], nil, _fields, acc), do: {name, %{}, acc}
  defp open_section([_, name], current, fields, acc), do: {name, %{}, [{current, fields} | acc]}

  defp finalize_profiles({nil, _fields, acc}), do: acc

  defp finalize_profiles({current, fields, acc}),
    do: [{current, fields} | acc]

  # Pick the right profile from the parsed list, applying the
  # precedence documented in the moduledoc.
  defp pick_profile(body, opts) do
    profiles = parse_profiles(body)

    cond do
      profiles == [] ->
        nil

      explicit = Keyword.get(opts, :profile) ->
        find_profile_by_name(profiles, explicit)

      env_profile = System.get_env(@env_profile) ->
        find_profile_by_name(profiles, env_profile) || fallback(profiles)

      true ->
        fallback(profiles)
    end
  end

  defp find_profile_by_name(profiles, name) do
    Enum.find(profiles, fn {pname, _} -> pname == name end)
  end

  defp fallback(profiles) do
    Enum.find(profiles, fn {_, fields} -> Map.get(fields, "active") == true end) ||
      List.first(profiles)
  end

  defp extract_creds({_name, fields}) do
    case {Map.get(fields, "token_id"), Map.get(fields, "token_secret")} do
      {id, secret} when is_binary(id) and is_binary(secret) ->
        {:ok, [token_id: id, token_secret: secret]}

      _ ->
        :missing
    end
  end

  defp credentials_missing_error(path, opts) do
    detail =
      [
        "tried env: #{@env_token_id} + #{@env_token_secret} (unset)",
        "tried file: #{path}"
      ] ++ profile_hint(opts) ++ [hint_run_modal_token_set()]

    %Modal.Error{
      kind: :credentials_missing,
      message: "Modal credentials not found.\n  " <> Enum.join(detail, "\n  "),
      metadata: %{config_path: path}
    }
  end

  defp profile_hint(opts) do
    cond do
      profile = Keyword.get(opts, :profile) ->
        ["requested profile: #{inspect(profile)}"]

      env = System.get_env(@env_profile) ->
        ["#{@env_profile} env: #{inspect(env)}"]

      true ->
        []
    end
  end

  defp hint_run_modal_token_set,
    do: "run `modal token set` (or set the env vars) to provision."
end
