# Working notes

Just a running log of what I did, what broke, and why I made the calls I made.
This is my scratchpad — I'll clean the useful bits into the real README later.

---

## Phase 1 — getting the quickstart running on my laptop

Goal for this phase: forget the cloud, just prove the thing works locally. One curl
in, an AI reply out.

It worked in the end (HTTP 200, ~25s round trip), but it wasn't plug-and-play. Here's
everything I ran into.

### 1. The `iii` engine wasn't installed

The whole project runs on a framework called `iii` — there's an "engine" process that
runs the workers and lets them call each other. My machine didn't have it, so step one
was just installing it:

```
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
```

It dropped the binary in `~/.local/bin/`. Nothing clever here, just a missing tool.

### 2. config.yaml had someone else's file paths in it

This one actually blocked me. `config.yaml` told the engine where to find the two
workers, but the paths were `/Users/anuran/Alchemyst/hiring/...` — that's the person
who wrote the assignment, not me. Those folders don't exist on my Mac, so the engine
just errored out: "Worker path does not exist".

Fix was obvious: point `worker_path` at my own copy of the workers. Worth noting in
the final README because it's exactly the kind of thing that makes a project
non-reproducible — hardcoded absolute paths. (Ironic, given the assignment is about
reproducibility.)

### 3. The model wants to generate WAY too much text

First proper curl came back as a 504 timeout after exactly 30 seconds.

Dug into it. The Python worker had `max_new_tokens=32000` — that's how many words the
model is allowed to spit out before stopping. The catch: the model runs on CPU (no
GPU on my laptop), and CPU generation is slow, roughly 10 words a second. 32,000 words
at that rate is half an hour for ONE reply. And the model wasn't stopping early on its
own — I watched it loop and repeat itself in the logs.

Dropped it to `max_new_tokens=256`. That's a normal length for a chat reply, and it
brought the response time down to ~25s. This is the fix that actually mattered.

### 4. The request timeout was too tight

The engine has a setting — if a request takes longer than X, it gives up with a 504.
It was set to 30 seconds. My successful call took 25s, which technically fits... but
25 against a 30 limit is too close for comfort. A longer question, or a cold start,
and I'm back to 504s.

Bumped it to 5 minutes (`default_timeout: 300000`). Think of it as a safety buffer
rather than a hard requirement — but I'd rather not have flaky timeouts.

### 5. Editing config while the engine runs is flaky

The engine claims it watches `config.yaml` and reloads changes live. In practice,
after I edited config a couple of times, I started getting 404s — the API route just
vanished. Turned out the live-reload left a dead listener stuck on the port.

Lesson learned: **don't trust the hot-reload. After changing config, just restart the
engine.** A clean restart fixed it immediately. Keeping this in mind for the cloud
deployment — I'll want a proper restart step, not "edit and pray".

### Fixed: the response used to come back garbled

Originally the reply came back as `{"0":"S","1":"a","2":"y",...}` — the text split
character by character into a weird object. Turned out to be a bug in the supplied
TypeScript ([caller-worker/src/worker.ts](quickstart/workers/caller-worker/src/worker.ts)):
it did `{...result}` on a string, and JavaScript happily explodes a string spread into
`{0:'S',1:'a',...}`.

Fixed it by putting the string under a proper key — `response: result` instead of
`...result`. Clean JSON now. This is the request/response schema I'm going with:

```
POST /v1/chat/completions
Request:  {"messages":[{"role":"user","content":"..."}]}
Response: {"result":{"response":"<the AI's text>","success":"<onboarding message>"}}
```

(The `success` field is leftover template text from the quickstart. Harmless, might
strip it later, not important.)

Also: the actual reply quality is poor (it rambled and repeated itself). That's
expected — the model is
`gemma-3-270m`, a tiny 270M-parameter model. This assignment is graded on
infrastructure, not on how smart the AI is. Not worried about it.

### Files I changed in Phase 1

- `quickstart/config.yaml` — fixed worker paths, raised `default_timeout` to 300000
- `quickstart/workers/inference-worker/inference_worker.py` — `max_new_tokens` 32000 -> 256
- `quickstart/workers/caller-worker/src/worker.ts` — fixed string-spread bug so the
  API returns clean JSON (`response: result` instead of `...result`)

### How I run it locally (for my own reference)

```
cd quickstart
iii --config config.yaml          # start the engine, leave it running
```

Then in another terminal:

```
curl -X POST http://127.0.0.1:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello in one short sentence."}]}'
```

Useful commands while debugging:

```
iii worker list                   # see which workers are up
iii worker logs inference-worker  # tail a worker's logs
iii worker restart caller-worker  # restart one worker
```

Good to know for later: each worker runs in its own little VM/container (the logs
literally say "Booting VM..."). That's handy — the project is already
container-shaped, which should make Phase 2 (Docker) and the cloud deployment easier.

---

## Phase 2 — packaging into Docker, split across 3 containers

Goal: stop running everything via the local `iii` engine, and instead package the
project into containers that can each go on their own VM later.

### What I figured out about how `iii` containerizes

`iii project generate-docker` exists — but it generates ONE Dockerfile that bundles
the whole engine and runs all workers inside it as micro-VMs. That's the "everything
on one box" model, which the assignment explicitly forbids.

So I went a different route. `iii` has a distributed mode: the engine runs on its own,
and workers are plain processes that connect IN to it over a WebSocket (`III_URL`
env var). That's the model the assignment actually wants:

```
engine container          - the iii engine. Hosts the API (:3111) and the worker
                            socket (:49134). This is the public "gateway".
caller-worker container   - connects to the engine via III_URL
inference-worker container - connects to the engine via III_URL
```

RPC between the two workers still routes THROUGH the engine — that's just how `iii`
works, hub-and-spoke. But since each piece is a separate container (and later a
separate VM), the traffic genuinely crosses the network. Requirement satisfied.

Nice side effect: in this distributed mode nothing needs the micro-VM sandboxing,
so none of the 3 containers need privileged mode or nested virtualization. Clean.

### Files I created (all under quickstart/)

- `deploy/engine/config.yaml`   - the engine config, minus the worker entries
- `deploy/engine/Dockerfile`    - engine image (from the official `iiidev/iii` image)
- `deploy/docker-compose.yml`   - runs all 3 together locally for testing
- `workers/caller-worker/Dockerfile`
- `workers/inference-worker/Dockerfile`

For the inference image I install CPU-only PyTorch on purpose — the normal install
drags in ~1.5GB of NVIDIA GPU libraries that are useless here (no GPU). I also
pre-download the model during the image build so the container doesn't have to fetch
it on every startup.

### The bug I hit: a SECOND timeout

Got everything built and running, then the API call failed with
`Invocation timeout after 30000ms`. Different from the Phase 1 timeout.

Turns out there are TWO separate timeouts in this system:
1. the HTTP timeout (already raised to 5 min in Phase 1), and
2. an RPC/invocation timeout — how long one worker waits for another worker's reply.
   That one defaults to 30s, set via `invocationTimeoutMs` on `registerWorker`.

In Phase 1 the whole thing finished in ~25s so I never hit #2. In Docker it's a bit
slower (~80s) so it tripped. Fixed it by passing `invocationTimeoutMs: 300000` in
[caller-worker/src/worker.ts](quickstart/workers/caller-worker/src/worker.ts).

### Result

All 3 containers up via `docker compose up`, one curl to `localhost:3111`, HTTP 200,
clean JSON back. Took ~80s (CPU inference in a container is slow — fine for this).

Only port 3111 is published to the host in the compose file; the worker socket
(49134) stays on the internal Docker network. That already mirrors the security
model the cloud setup needs: only the API is reachable, workers are not.

### Files changed in Phase 2

- `quickstart/workers/caller-worker/src/worker.ts` — added `invocationTimeoutMs`
- (new Docker files listed above)

### How to run the 3-container setup locally

```
cd quickstart/deploy
docker compose up -d --build
curl -X POST http://127.0.0.1:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
docker compose down      # to stop
```

---

## Phase 3 — cloud deployment (AWS, Terraform)

Goal: take the 3-container setup from Phase 2 and put each container on its
own VM in AWS, with the workers in a private subnet and only the engine
exposed publicly.

### Why AWS, why Terraform

Picked AWS because I already had credentials set up; the assignment said
either cloud was fine. Terraform because the assignment specifically calls
out reproducibility and `terraform destroy` + `terraform apply` is the
cleanest way to prove that.

### Topology

```
                    Internet
                       │
                  (port 3111)
                       │
              ┌────────▼────────┐
              │   Engine VM     │  public subnet  10.10.1.0/24
              │  (public IP)    │
              │  - iii engine   │  hosts API :3111 + worker socket :49134
              └────┬────────────┘
                   │
              VPC 10.10.0.0/16
                   │
        ┌──────────┴───────────┐
        │                      │       private subnet  10.10.2.0/24
        ▼                      ▼       (no public IPs, egress via NAT)
  ┌───────────┐         ┌────────────────┐
  │ caller-   │         │ inference-     │
  │ worker VM │         │ worker VM      │
  └───────────┘         └────────────────┘
        │ WS to engine:49134     │ WS to engine:49134
        └──────────┬─────────────┘
                   │
                  RPC routed THROUGH the engine
                  (hub-and-spoke, that's how iii works)
```

- VPC `10.10.0.0/16`
- Public subnet `10.10.1.0/24` → IGW → internet (engine sits here)
- Private subnet `10.10.2.0/24` → NAT Gateway → internet egress only
  (workers sit here; nothing can dial in from outside the VPC)

### Security groups

- `engine-sg`: ingress 3111 from 0.0.0.0/0 (the JSON API), plus all TCP
  from inside the VPC (so workers can hit :49134). Egress all.
- `worker-sg`: ingress all TCP from inside the VPC only — no public
  ingress at all. Egress all (needed at boot to pull base images +
  download the model via NAT).

### SSH? No, SSM

I didn't open port 22 anywhere and didn't generate a keypair. Instead the
VMs get an IAM instance profile with `AmazonSSMManagedInstanceCore`, and
debugging is done via `aws ssm start-session`. One less attack surface,
and no keys to lose.

### Instance sizes

- engine: `t3.small` — barely doing anything, just routes JSON
- caller-worker: `t3.small` — a node.js process that forwards calls
- inference-worker: `t3.large` (8 GB RAM) — the model + transformers
  eats memory. I tried `t3.medium` first and it OOM-killed during
  model load.

### How the VMs build themselves

Each VM's `user_data` is a shell script that:
1. `apt-get install -y docker.io git`
2. clones this repo from `repo_url`
3. `docker build` the relevant image
4. `docker run` it with `--restart unless-stopped`

That's deliberately stupid — no Ansible, no AMI baking, no registry. The
VM has everything it needs to rebuild itself from a git URL. If a worker
crashes, docker restarts it; if the VM dies, terraform respins it.

Tradeoff: cold boot is ~5 minutes (image build + model download). For
production you'd push pre-built images to ECR and skip the build step.

### Bug I hit on the first apply

Caller-worker VM came up but the API still returned 404. Turned out
`apt-get update` ran before the NAT Gateway routing had propagated, so
the first `apt-get` couldn't reach the Ubuntu repos and the whole script
died with `docker.io: not available`. The inference VM happened to boot
slightly later and worked fine — pure timing luck.

Fix: wrap `apt-get update` in a retry loop with sleep, so the VM patiently
waits for NAT to be ready instead of giving up on first failure.

```
for i in 1 2 3 4 5 6; do apt-get update && break || sleep 15; done
```

After the fix, a from-scratch `terraform apply` brings the stack up
without any manual intervention.

### Files in `quickstart/deploy/terraform/`

- `network.tf`    — VPC, subnets, IGW, NAT, route tables
- `security.tf`   — security groups
- `iam.tf`        — instance role for SSM access (no SSH)
- `compute.tf`    — 3 EC2 instances + AMI lookup
- `outputs.tf`    — public IP, API URL, SSM session commands
- `variables.tf`  — region, CIDRs, instance types, repo URL/branch
- `versions.tf`   — provider pin
- `startup-engine.sh`, `startup-caller.sh`, `startup-inference.sh`
- `terraform.tfvars.example` — fill in and rename to `terraform.tfvars`

### Verified end-to-end

```
$ curl -X POST http://<engine-public-ip>:3111/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"Say hello in one short sentence."}]}'
{"result":{"response":"Say hlelo in oone short sentence...","success":"..."}}
HTTP 200, ~28s round trip
```

The response is rambly because the model is `gemma-3-270m` — quality is
not the point of this assignment, the network path is.

