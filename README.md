# trade-tariff-flagsmith

Deployment for self-hosted [Flagsmith](https://www.flagsmith.com/) — the feature-flag
service for the Online Trade Tariff (OTT) platform.

Flagsmith is treated as "just another Django app": it runs as ECS Fargate
services on the shared `trade-tariff-cluster-<env>` and is deployed via the same
`aws/ecs-service` module as frontend/backend/admin/devhub.

## What lives where

This repo only deploys the **running services**. The supporting infrastructure
lives in the platform terraform repo
(`trade-tariff-platform-aws-terraform`), in each environment's `common` stack
(`environments/<env>/common/flagsmith.tf` + the `http_services` block in
`alb.tf`):

| Resource | Where |
|---|---|
| Dedicated Postgres RDS instance | terraform repo › `common/flagsmith.tf` |
| `flagsmith-connection-string` secret (DATABASE_URL) | created by the rds module |
| `flagsmith-configuration` / `flagsmith-edge-configuration` secrets | terraform repo › `common/flagsmith.tf` |
| ECS + RDS security groups | terraform repo › `common/flagsmith.tf` |
| ALB HTTP target groups (`flagsmith-http`, `flagsmith-edge-http`) | terraform repo › `common/alb.tf` (`http_services`) |
| CloudFront distributions (`flags.`, `flags-edge.`) | terraform repo › `common/flagsmith.tf` |
| **The two ECS services** | **this repo** › `terraform/main.tf` |

The services here read those shared resources via data sources (target groups,
security group, secrets), exactly like `devhub`.

## Services

- **`flagsmith`** — the API + dashboard (`flagsmith/flagsmith`), served at
  `https://flags.<env>.trade-tariff.service.gov.uk`.
- **`flagsmith-edge`** — the edge proxy (`flagsmith/edge-proxy`) for low-latency
  client-side SDK evaluation, served at
  `https://flags-edge.<env>.trade-tariff.service.gov.uk`.

Both serve plain HTTP on port 8000; the shared ALB terminates TLS and forwards
to HTTP target groups (Flagsmith's upstream images don't do the in-container
TLS-on-8443 that our own images do).

## Images & CI

We pull the upstream images **straight from Docker Hub** (`flagsmith/flagsmith`,
`flagsmith/edge-proxy`); we do not build or mirror an image into ECR.

Because of that, the CI does **not** use the shared
`trade-tariff-tools/.github/workflows/deploy-ecs.yml` reusable workflow — that
one is build-and-push oriented (it runs `cat .ruby-version`, builds a Dockerfile
and pushes a `tariff-*` image to ECR, none of which apply here).

Instead the deploy workflows reuse the lower-level composite actions directly,
skipping the build entirely:

- `terraform-plan@main` on pull requests
- `terraform-apply@main` on deploy (dev behind the `needs-deployment` label,
  staging on merge to main, production after staging succeeds)

Both run `terraform init -backend-config=backends/<env>.tfbackend` then
plan/apply with `config_<env>.tfvars`. The image tags come from those tfvars
(`flagsmith_tag` / `edge_proxy_tag`) — **pin them to a specific upstream version
for production** rather than `latest`. (The actions also set a `TF_VAR_docker_tag`
from the git SHA; this config doesn't declare that variable, so Terraform
ignores it.)

The workflows assume the per-account `GithubActions-ECS-Deployments-Role` already
exists (it's the same role our other services deploy with).

## Post-deploy operator steps

The config secrets start empty; populate them after the first deploy:

1. Put a Django secret key into `flagsmith-configuration`:
   `{"SECRET_KEY": "<generate one>"}` and redeploy the `flagsmith` service.
2. Visit `https://flags.<env>.trade-tariff.service.gov.uk` and create the first
   admin user (registration is open until the first user exists; lock it down
   afterwards via `ALLOW_REGISTRATION_WITHOUT_INVITE=false` in the secret).
3. Create a project + environment in Flagsmith and copy the **server-side
   environment key**.
4. Put it into `flagsmith-edge-configuration`:
   `{"FLAGSMITH_API_SERVER_SIDE_ENVIRONMENT_KEY": "<key>"}` and redeploy the
   `flagsmith-edge` service.

## Local terraform

```sh
cd terraform
terraform init -backend-config=...   # backend config supplied by CI / tooling
terraform plan  -var-file=config_development.tfvars
```
