# DevOps Internship Assignment

Distributed deployment of the [`quickstart`](./quickstart) project on AWS:
three EC2 VMs in a VPC, workers in a private subnet, a JSON HTTP API
exposed only via the engine VM in the public subnet. Everything is
Terraform — `terraform destroy` and `terraform apply` rebuilds the stack
from scratch.

See [NOTES.md](./NOTES.md) for the full working log (what I tried, what
broke, why I made the calls I did).

## Architecture

```
                    Internet
                       │
                  (port 3111)
                       │
              ┌────────▼────────┐
              │   Engine VM     │    public subnet  10.10.1.0/24
              │  (public IP)    │    (route: IGW → internet)
              │  iii engine     │    hosts API :3111 + worker socket :49134
              └────┬────────────┘
                   │
              VPC 10.10.0.0/16
                   │
        ┌──────────┴───────────┐
        │                      │     private subnet  10.10.2.0/24
        ▼                      ▼     (no public IPs, egress via NAT only)
  ┌───────────┐         ┌────────────────┐
  │ caller-   │         │ inference-     │
  │ worker VM │         │ worker VM      │
  │ (TS)      │         │ (Python+model) │
  └─────┬─────┘         └────────┬───────┘
        │ WebSocket → engine:49134│
        └──────────┬──────────────┘
                   │
              RPC routed through the engine
              (hub-and-spoke, iii's model)
```

Request flow for one inference:

```
client  --POST :3111-->  engine VM
                          │
                          │  routes to http::run_inference_over_http
                          ▼
                       caller-worker  (via :49134 WebSocket)
                          │
                          │  RPC: inference::run_inference
                          ▼
                       inference-worker  (loads gemma-3-270m, generates)
                          │
                          ▼
                       caller-worker  (wraps result in JSON)
                          │
                          ▼
client  <--HTTP 200 JSON-- engine VM
```

Why hub-and-spoke: `iii` workers register inbound to the engine over a
WebSocket. Worker-to-worker RPC is routed through the engine, not
peer-to-peer. The traffic still crosses the network between the private
and public subnets, so the assignment requirement ("workers communicate
via RPC across the subnet, not co-located") is satisfied.

## Security posture

- Workers have **no public IPs** and live in a subnet whose route table
  has no IGW route.
- Worker security group accepts **only intra-VPC TCP**. Nothing reaches
  them from the internet.
- Engine SG opens **only port 3111** to the world (the JSON API); the
  RPC port 49134 is open inside the VPC only.
- VMs are administered via **AWS SSM** (`aws ssm start-session`). No
  port 22, no SSH key material, no bastion.
- Private subnet has a **NAT Gateway** for egress only — enough to pull
  base images and the model at boot; nothing inbound.

## API

Single endpoint:

```
POST http://<engine-public-ip>:3111/v1/chat/completions
Content-Type: application/json

{"messages":[{"role":"user","content":"Say hello in one short sentence."}]}
```

Response:

```json
{
  "result": {
    "response": "<the model's text>",
    "success": "<onboarding string left over from the quickstart template>"
  }
}
```

Example curl against the deployed stack:

```
$ curl -X POST http://18.206.93.228:3111/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"Say hello in one short sentence."}]}'

{"result":{"response":"Say hlelo in oone short sentence.\nThe word \"hallel\"...","success":"You've connected two workers and they're interoperating seamlessly..."}}
```

Round-trip on a cold call: ~28 seconds (CPU inference, `t3.small` + `m7i-flex.large`, model `gemma-3-270m`).

The response text itself is low-quality and rambly — that's the 270M-parameter model, not the infrastructure. The assignment is graded on the network/deployment, not on response quality.

## Redeploy from scratch

Prerequisites:

- An AWS account with credentials configured (`aws configure`).
- Terraform ≥ 1.5.
- A public Git repo containing this code (the VMs `git clone` it at boot).

Steps:

```
cd quickstart/deploy/terraform
cp terraform.tfvars.example terraform.tfvars     # then edit
terraform init
terraform apply                                  # ~5 min for VMs to be fully ready
terraform output api_url
```

The `terraform apply` brings up the VPC, subnets, NAT, IGW, security
groups, IAM role, and three EC2 instances. Each VM's `user_data` is a
shell script that installs Docker, clones the repo, builds the relevant
container, and runs it under `--restart unless-stopped`. First-boot total
time is ~5 minutes (apt + docker build + model download on the inference
VM dominate).

Test it:

```
curl -X POST "$(terraform output -raw api_url)" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hello"}]}'
```

Tear it down:

```
terraform destroy
```

Debugging a VM (no SSH — use SSM):

```
eval "$(terraform output -raw ssm_caller)"
# inside the session:
docker ps
docker logs caller-worker
```

## What I would harden before production

- **TLS + ALB in front of the engine.** Right now the API is plaintext
  HTTP. Put an ACM cert behind an Application Load Balancer, terminate
  TLS there, and only let the ALB security group reach the engine on
  3111. Drop public ingress from the engine SG entirely.
- **Auth on the API.** Currently anyone with the URL can spend compute.
  At minimum an API key in a header, validated by the ALB or by a small
  middleware in the caller-worker. Better: short-lived tokens from a
  real IdP.
- **Don't build images on the VM at boot.** That's fine for a demo but
  it makes cold start slow and ties uptime to GitHub being reachable.
  Build images in CI, push to ECR, and have `user_data` just `docker
  pull` + `docker run`. Pin by digest.
- **Real secrets handling.** Nothing sensitive today, but the moment
  there's an API key, model license, or DB creds, they go in Secrets
  Manager or SSM Parameter Store, not env vars baked into images.
- **Logging + metrics off-box.** The `iii` engine logs to stdout inside
  a container; today you `docker logs` over SSM. Ship logs to
  CloudWatch (or a managed Loki/Grafana), and at least track p95
  latency + error rate on the API endpoint.
- **Multi-AZ.** Both subnets are in `us-east-1a`. For real uptime,
  spread the workers across two AZs and put the ALB across both.
- **State backend + locking.** `terraform.tfstate` is local; move it to
  S3 with a DynamoDB lock table so multiple people can apply safely.
- **Network egress lockdown.** Workers currently have egress all/0 (so
  the boot script can apt + clone + pull). After bake-time you'd
  restrict egress to ECR + your model registry only.
- **Restart policy on the engine.** Engine container has
  `--restart unless-stopped`, but the model state in the inference
  worker is in-memory — a restart costs another model load. For prod
  you'd warm-pool that or use a persistent volume for model weights.

## What I would do differently if the model were 100x larger

A 27B-parameter model (100× `gemma-3-270m`) doesn't fit on CPU and
doesn't fit on a single small VM:

- **GPU instances for the inference tier.** `g5.xlarge` or `g6.xlarge`
  per replica. Inference SG no longer trusts the whole VPC — only the
  caller-worker SG.
- **A real model server, not raw transformers.** Swap the Python worker
  for **vLLM** or **TGI** behind the same RPC contract. They handle
  paged attention, continuous batching, and tensor parallelism — you get
  10×+ throughput before you even add a second GPU.
- **Decouple model weights from the image.** Push them to S3 (or a
  mounted EFS volume) and download on first boot to a local NVMe cache.
  A 50 GB model in a container image makes deploys impossibly slow.
- **Autoscaling on the inference tier, not the others.** The caller-worker
  is cheap (it's just routing JSON). The expensive thing is the GPU
  pool — scale it on queue depth or p95 latency, not on the front door.
- **Async + queue between caller and inference.** At 270M, a request
  finishes in seconds and a synchronous HTTP-to-RPC chain is fine. At
  27B, individual requests take longer and you need backpressure. Put
  SQS (or `iii`'s built-in queue) between the caller and the GPU pool,
  and either return `202 Accepted` + polling, or stream tokens back over
  SSE so the user sees output as it generates.
- **Caching.** Prompt-prefix KV cache reuse on the model server, plus
  a CDN/edge cache for identical prompts. Even a small hit rate saves
  serious GPU time.
- **Budget guardrails.** GPU costs run away fast. Per-API-key rate
  limits and a daily spend alarm, day one.

## Repo layout

```
.
├── README.md                          this file (the deliverable)
├── NOTES.md                           full working log of phases 1-3
├── devops-internship-assignment.md    the assignment brief
└── quickstart/
    ├── README.md                      original project README
    ├── config.yaml                    iii engine config (local dev)
    ├── workers/
    │   ├── caller-worker/             TypeScript: HTTP → RPC
    │   │   ├── Dockerfile
    │   │   └── src/worker.ts
    │   └── inference-worker/          Python: hosts the model
    │       ├── Dockerfile
    │       └── inference_worker.py
    └── deploy/
        ├── docker-compose.yml         3-container local stack
        ├── engine/                    engine image + standalone config
        └── terraform/                 the AWS stack
            ├── network.tf
            ├── security.tf
            ├── iam.tf
            ├── compute.tf
            ├── outputs.tf
            ├── variables.tf
            ├── versions.tf
            ├── startup-engine.sh
            ├── startup-caller.sh
            ├── startup-inference.sh
            └── terraform.tfvars.example
```
