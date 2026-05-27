# Manhattanhenge as an agent build pipeline

`scripts/manhattanhenge.exs` is a small live demo of a larger pattern: treat an
AI coding agent as one remote build worker inside a controlled system, then make
the surrounding system responsible for isolation, artifact movement,
verification, and cleanup.

The problem is intentionally concrete. Claude Code writes a FastAPI app that
computes the 2026 Manhattanhenge dates using Skyfield and JPL DE440. Modal runs
both the build and the serve. Elixir coordinates the lifecycle and decides
whether the generated artifact is acceptable.

## Shape

The useful part is not that Claude can write a Python file. The useful part is
where that file is allowed to go next.

Generated code starts in a sandbox, crosses a Volume boundary only after an
orchestrator-owned smoke test, and is then served from the same Volume mounted
read-only into an ASGI Function. The live endpoint is checked from outside the
container before the run is considered green.

```text
Elixir orchestrator
  -> Modal.Image.get_or_create
       base image: Claude CLI + Skyfield + FastAPI + DE440

  -> Modal.Secret.create(if_exists: :ephemeral)
       ANTHROPIC_API_KEY visible only to the build sandbox

  -> Modal.Sandbox.create
       mounts fresh Modal.Volume read-write at /work
       writes SPEC.md
       runs Claude Code headless
       saves transcript locally at /tmp/henge_transcript.jsonl
       smoke-tests: from app import serve; serve()
       sandbox exits; worker commits Volume

  -> Modal.Function.deploy_asgi
       mounts the same Volume read-only
       serves module app, callable serve

  -> live verifier
       curls /, /manhattanhenge, /crossing/2026-05-29, /source
       checks dates, crossing times, apparent altitude, refraction lift
```

## Boundaries

The agent controls the implementation of `/work/app.py` and the choices it makes
inside the build sandbox. It does not control deployment, cleanup, which secrets
are attached to the serving Function, or the final acceptance checks.

The orchestrator controls the prompt contract, image, sandbox, Secret, Volume,
deployed Function, and verification gates. The Anthropic key is injected only
into the build sandbox. The serving Function mounts the generated source
read-only and does not receive that Secret.

`/source` is public so the generated app can be inspected. The Claude transcript
is intentionally not published; it stays local for cost/debugging because agent
sessions are easy places to leak paths, env dumps, or future tool output.

## Why Manhattanhenge works well here

The task is constrained enough to fit in one file but sharp enough to catch lazy
solutions. The spec gives Claude the grid bearing, observer location, ephemeris,
and May 2026 search window. It does not give the two final dates.

The verifier catches common mistakes:

- Hard-coding dates without doing the crossing calculation.
- Reporting sunset instead of the instant the Sun crosses Manhattan's grid
  bearing.
- Using geometric altitude instead of apparent refraction-corrected altitude.
- Mishandling New York local time / DST.
- Producing code that imports in the build sandbox but fails once served from
  the Volume.

The altitude check is the subtle one. Near the horizon, refraction is about 0.5
degrees, larger than the Sun's apparent radius. On May 28, the geometric center
is slightly below the true horizon while the apparent disk is visibly up. The
gate asserts the apparent altitude and refraction lift, not just the date
strings.

## Latest run

```sh
set -a; source .env; set +a
elixir scripts/manhattanhenge.exs
```

Observed output from `demo/manhattanhenge`:

```text
── SETUP — base image (Claude CLI + uv + Skyfield + DE440) ──
  ✓ image im-HK5Qodd7Lp4xrMBw0uT7Sy [cached]

── STAGE 1 — BUILD: Claude derives + writes app.py (live) ──
  $ claude -p <spec> --model claude-sonnet-4-6  (deriving + writing, ~5 min)…
  ✓ Claude finished (327.5s)  —  $0.4732, 8 turns
  ✓ orchestrator smoke-test passed
  ✓ Volume committed (app.py 4895B)

── STAGE 2 — DEPLOY: deploy_asgi off the Volume ──
  ✓ deployed https://ivarvong--manhattanhenge.modal.run

── STAGE 3 — VERIFY: live endpoint ──
  ✓ 2026-05-28: 299.1° at 2026-05-28T20:13:16-04:00  apparent 0.440° (refraction +0.480°)
  ✓ 2026-05-29: 299.1° at 2026-05-29T20:12:44-04:00  apparent 0.630° (refraction +0.460°)
  ✓ /source 4895B  (off the Volume; transcript kept local)
  ✓ pruned 1 stale volume(s)
```

Live checks:

```sh
curl https://ivarvong--manhattanhenge.modal.run/manhattanhenge
curl https://ivarvong--manhattanhenge.modal.run/crossing/2026-05-29
curl https://ivarvong--manhattanhenge.modal.run/source
```

## Operational notes

- The demo expects `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET`, and
  `ANTHROPIC_API_KEY` in the local environment.
- Each run uses a fresh Volume name with timestamp plus random suffix, so a new
  build does not patch stale `app.py` from a prior run.
- The build Secret is ephemeral and also deleted in an `after` block.
- The build sandbox is terminated in an `after` block.
- The latest serving Volume is kept because the deployed Function depends on it.
  Older prefix-matched Volumes are pruned best-effort after a successful deploy,
  but only once they are older than 10 minutes.
- The endpoint uses `min_containers: 0`, so the first request can pay a cold
  start. The verifier uses a 90s receive timeout to out-wait that boot path.
- The base image installs the current Claude Code CLI and lower-bound Python
  dependencies. That keeps the demo current, not bit-for-bit reproducible.

## Limits

This is still a demo environment, not a hardened multi-tenant agent runner.
Claude has broad Bash access inside the build sandbox. A production service
would likely add a narrower tool policy, egress controls, artifact manifests,
per-task golden tests, and an explicit teardown path for the deployed app and
serving Volume.

The generated source is not committed to this repo. The checked-in artifact is
the orchestration pattern; the sampled app body is available from `/source` on
the live endpoint.
