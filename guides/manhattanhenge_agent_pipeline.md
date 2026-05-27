# Manhattanhenge as an agent build pipeline

`scripts/manhattanhenge.exs` is a research demo, but it is intentionally
packaged as an engineering artifact: an AI coding agent is treated as an
untrusted remote build worker, not as a local copilot whose output is assumed
correct.

The domain is deliberately small and checkable. Claude Code writes a FastAPI app
that computes the 2026 Manhattanhenge dates from Skyfield / JPL DE440. Modal
runs both the build and the serve. Elixir owns orchestration, resource
lifecycle, and acceptance.

## What a staff+ / EM reviewer should see

This is not primarily an astronomy demo. The important claim is the system
shape:

> Generated code does not become trusted because an agent wrote it. It becomes
> deployable only after an external orchestrator verifies it and moves it across
> a controlled artifact boundary.

The demo exercises the same seams a production agent platform needs:

- Isolation: Claude runs in a Modal sandbox, not on the developer machine.
- Artifact boundary: generated `app.py` is committed to a fresh `Modal.Volume`.
- Separation of duties: the build sandbox writes; the deployed function mounts
  the same Volume read-only.
- Independent acceptance: Elixir runs its own import smoke test and curls the
  live URL for domain checks.
- Credential hygiene: the Anthropic key is injected as an ephemeral Modal
  Secret, then deleted in an `after` block.
- Cleanup hygiene: the sandbox is terminated in an `after` block and stale
  demo Volumes are pruned best-effort after a green deploy.
- Provenance without oversharing: `/source` serves the generated app code, but
  the Claude transcript stays local and is not deployed.
- Cost visibility: the local Claude transcript is parsed for `total_cost_usd`
  and turn count.

## Architecture

```text
Elixir orchestrator
  -> Modal.Image.get_or_create
       base image: Claude CLI + Skyfield + FastAPI + DE440

  -> Modal.Secret.create(if_exists: :ephemeral)
       ANTHROPIC_API_KEY only visible inside the build sandbox

  -> Modal.Sandbox.create
       mounts fresh Modal.Volume read-write at /work
       writes SPEC.md
       runs Claude Code headless
       saves transcript locally at /tmp/henge_transcript.jsonl
       orchestrator smoke-tests: from app import serve; serve()
       sandbox exits; worker commits Volume

  -> Modal.Function.deploy_asgi
       mounts the same Volume read-only
       serves module app, callable serve

  -> live verifier
       curls /, /manhattanhenge, /crossing/2026-05-29, /source
       asserts dates, crossing times, apparent altitude, refraction lift
```

## Trust boundaries

The agent controls:

- The contents of `/work/app.py`.
- Its own implementation strategy inside the sandbox.
- The local transcript produced by `claude --output-format stream-json`.

The orchestrator controls:

- The prompt contract and route/schema requirements.
- The image, sandbox, secret, Volume, and deployed Function lifecycles.
- The acceptance gate before deploy.
- The live endpoint verification after deploy.
- What is published. Generated source is public; the transcript is not.

The deployed service controls:

- Only the generated FastAPI app mounted from the read-only Volume.
- No Anthropic key. The serving Function does not receive the build Secret.

## Why Manhattanhenge is a useful test case

The input is constrained, but not trivial. The spec tells Claude the Manhattan
grid bearing (299.1 degrees), the observer location, the ephemeris, and the May
2026 search window. It does not tell Claude the two final dates.

The verification catches several plausible agent mistakes:

- Hard-coding the published dates without doing the crossing calculation.
- Using geometric altitude instead of apparent refraction-corrected altitude.
- Reporting sunset rather than the instant the Sun crosses the grid bearing.
- Ignoring DST / local time formatting.
- Producing an app that imports in the sandbox but fails when served from the
  Volume.

The careful scientific detail is altitude. Near the horizon, refraction is about
0.5 degrees, larger than the Sun's apparent radius. On May 28, the geometric
center is slightly below the true horizon while the apparent disk is visibly up.
The verifier asserts the apparent altitude and the refraction lift, not just the
date strings.

## Latest live run

Run command:

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

## Demo-environment caveats

These are intentional tradeoffs for a live research artifact, not production
defaults:

- The demo depends on local `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET`, and
  `ANTHROPIC_API_KEY` from `.env`.
- The base image installs the current Claude Code CLI and lower-bound Python
  dependencies. That keeps the demo live, but it is not bit-for-bit
  reproducible across time.
- Claude is allowed to use Bash inside the build sandbox. That is appropriate
  for a one-off coding-agent demo; a multi-tenant product should add a narrower
  tool policy, network egress policy, and artifact allowlist.
- `/source` is public by design so reviewers can inspect the generated app. The
  agent transcript is not public by design.
- The deployed endpoint uses `min_containers: 0`, so the first request pays a
  cold-start tax. The script uses a 90s HTTP receive timeout to out-wait that.
- The demo leaves the latest serving Volume in place because the live Function
  depends on it. Older prefix-matched Volumes are pruned only after a successful
  deploy and only when they are older than 10 minutes.

## Failure modes the demo now handles

- Claude exceeds five minutes: `exec_streaming!(..., timeout: :infinity)` waits
  for the build while the sandbox timeout remains the outer bound.
- Claude claims success but writes an unimportable app: the orchestrator runs an
  independent import smoke test before deploy.
- The sandbox would leak on failure: `Modal.Sandbox.terminate/1` runs in an
  `after` block.
- Per-run secrets would accumulate: the secret is ephemeral and also deleted in
  an `after` block.
- Concurrent runs would collide on names: the run id includes a millisecond
  timestamp and random bytes.
- A stale app would be patched instead of rebuilt: every run uses a fresh Volume.
- Agent session details would be exposed publicly: transcript publication was
  removed; only generated source is served.

## Remaining gaps by design

These are useful discussion points in a staff+ / EM interview:

- This is not a hardened multi-tenant runner. The agent still has broad Bash in
  its sandbox.
- The astronomy verifier is strong for this demo but not a general proof of
  correctness. A production system would add golden tests and typed artifact
  manifests per task class.
- The generated source is not committed to the repo. Reviewers can fetch it
  from `/source`; the checked-in artifact is the reproducible orchestration
  pattern, not one sampled app body.
- The live endpoint can drift if Modal, Claude, or package indexes change. The
  latest observed run is recorded above so reviewers have an immutable result to
  compare against.
- The cleanup policy intentionally preserves the current serving Volume. A
  production demo environment would also expose an explicit teardown command.

## Evaluation lens

The artifact is meant to show judgment more than novelty:

- Can I turn an LLM into one worker inside a larger controlled system?
- Do I know where trust starts and stops?
- Do I verify the artifact externally instead of trusting the agent transcript?
- Do I handle resource lifecycle, cleanup, and credential exposure?
- Do I make the demo observable enough that another engineer can debug it?
- Do I state what is not production-ready instead of implying a toy is a
  platform?

That is the staff-level claim: the agent is interesting, but the surrounding
system is the product.
