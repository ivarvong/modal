# Examples

These are demo Mix tasks that showcase the Modal Elixir client. They are
**not** compiled or published as part of the library.

## Running the examples

Copy the tasks into your own project's `lib/mix/tasks/` directory, or
temporarily add `"examples"` to `elixirc_paths` in your `mix.exs`:

```elixir
defp elixirc_paths(:dev), do: ["lib", "examples"]
```

Then:

```bash
source .env  # MODAL_TOKEN_ID and MODAL_TOKEN_SECRET

mix modal.smoketest          # basic sandbox + Python exec
mix modal.calc               # 10 random math expressions against a warm sandbox
mix modal.demo               # clone, compile, snapshot, restore, test
mix modal.screenshot URL     # headless Chromium screenshot
mix modal.clip URL --end 30  # ffmpeg clip + resize to 720p
```

## Files

| Task | Description |
|------|-------------|
| `modal.smoketest.ex` | Create a sandbox, run Python, print the result |
| `modal.calc.ex` | 10 random math ops against a warm Python sandbox |
| `modal.demo.ex` | Full workflow: clone, install, snapshot, restore, test |
| `modal.screenshot.ex` | Screenshot a URL with headless Chromium on Modal |
| `modal.clip.ex` | Clip + resize a video to 720p via ffmpeg on Modal |
| `mix_helpers.ex` | Shared helpers (credentials, timing, formatting) |
