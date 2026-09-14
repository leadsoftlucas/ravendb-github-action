<div align="center">

# Setup RavenDB — GitHub Action

**🇺🇸 English** · [🇧🇷 Português (Brasil)](README.pt-BR.md)

A free, open-source GitHub Action that spins up a real **RavenDB** server in your CI
pipeline — via the official Docker image, ready in seconds, zero manual setup.

[![Self-test](https://img.shields.io/github/actions/workflow/status/leadsoftlucas/ravendb-github-action/test.yml?branch=main&label=self-test)](.github/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![RavenDB](https://img.shields.io/badge/RavenDB-CI-b3131e)](https://ravendb.net)
[![Docker: ravendb/ravendb](https://img.shields.io/badge/Docker-ravendb%2Fravendb-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/r/ravendb/ravendb)

</div>

It exists so a workflow can run integration tests against an actual
[RavenDB](https://ravendb.net) instance — not a mock, not an embedded stub — with no
manual installation and no external service to provision. The server is ready in
seconds and is torn down automatically when the job's runner is discarded.

> **Independent project, not an official RavenDB release.** This action is built
> and maintained by [Lucas R. Tavares](https://github.com/leadsoftlucas), a RavenDB
> employee, on his own initiative and in his own personal GitHub account. It is
> **not published by RavenDB the company, not covered by RavenDB's official support,
> and not listed on the GitHub Marketplace.** Use it, fork it, or copy from it —
> just don't assume it carries RavenDB's institutional backing. See
> [Status and scope](#status-and-scope) below.

## What it does

- Pulls the official `ravendb/ravendb` Docker image and starts a container configured
  for unattended, unsecured startup (no HTTPS, no client certificates) — the correct
  and documented setup for a short-lived CI database, never for anything reachable
  from outside the runner.
- Polls RavenDB's own `/setup/alive` endpoint until the server responds, so later
  workflow steps never race a server that isn't ready yet.
- Optionally creates a named database and, optionally, loads RavenDB's built-in
  **Northwind** sample dataset into it — useful for a self-contained example or a
  smoke test that needs real data without shipping fixtures.
- Exposes the server's `url` and the container's `container-id` as step outputs for
  later steps to use.

## What it deliberately does not do

This is the free, self-contained version of a "RavenDB in CI" action. It does not
provision anything against RavenDB Cloud, does not handle billing, and does not set
up client certificates or mTLS for a secured cluster — that is a materially different,
heavier project. If you need a production-grade, secured, multi-node RavenDB reachable
from outside a CI runner, this is not that.

## Quick start

```yaml
- name: Start RavenDB
  id: ravendb
  uses: leadsoftlucas/ravendb-github-action@main # pin to a commit SHA in real use — see "Versioning"
  with:
    database-name: MyTestDb

- name: Run integration tests
  run: dotnet test
  env:
    RAVENDB_URL: ${{ steps.ravendb.outputs.url }}
```

## Full example: querying the Northwind sample data

This is the same workflow this repository runs on every push to verify the action
still works — see [`.github/workflows/test.yml`](.github/workflows/test.yml).

<details>
<summary>Full workflow YAML</summary>

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Start RavenDB
        id: ravendb
        uses: leadsoftlucas/ravendb-github-action@main
        with:
          database-name: Northwind
          load-sample-data: "true"

      - name: Query Northwind data
        run: |
          curl --fail -X POST \
            "${{ steps.ravendb.outputs.url }}/databases/Northwind/queries" \
            --header "Content-Type: application/json" \
            --data '{"Query": "from Orders"}'
```

</details>

## Inputs

| Name                       | Description                                                                                                                                   | Default          |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| `version`                  | Tag of the official `ravendb/ravendb` image to run — e.g. `ubuntu-latest`, `ubuntu-latest-lts`, or a pinned version. [All tags](https://hub.docker.com/r/ravendb/ravendb/tags). | `ubuntu-latest`   |
| `port`                     | Host port to publish RavenDB's HTTP API on.                                                                                                    | `8080`            |
| `container-name`           | Name given to the RavenDB Docker container.                                                                                                    | `ravendb-ci`      |
| `database-name`            | Name of a database to create once the server is ready. Leave empty to start a bare server.                                                     | *(empty)*         |
| `load-sample-data`         | When `true` (and `database-name` is set), loads RavenDB's built-in Northwind sample dataset.                                                   | `false`           |
| `startup-timeout-seconds`  | How long to wait for RavenDB to report ready before failing the step.                                                                          | `60`              |

## Outputs

| Name           | Description                                              |
| --------------- | ----------------------------------------------------------- |
| `url`          | Base URL of the running RavenDB server, e.g. `http://localhost:8080`. |
| `container-id` | Docker container ID of the running RavenDB server.        |

## Requirements

- A Linux runner with Docker available (`ubuntu-latest` on GitHub-hosted runners).
  Docker is preinstalled there; this action does not run Docker-in-Docker or need
  any privileged setup.
- No RavenDB license is required. The Docker image runs unsecured and unlicensed,
  which RavenDB permits for development and evaluation use — exactly what a CI run is.

## How it works

This is implemented as a **composite action** (plain YAML + a shell script, no
compiled JavaScript, no separate Docker container action) that shells out to
`docker run` directly on the runner's own, already-present Docker daemon. That
choice, over GitHub's native ["service containers"](https://docs.github.com/en/actions/using-containerized-services/about-service-containers)
or a Docker-container action, follows the same pattern used by comparable
`setup-<database>` actions in the ecosystem: it keeps the workflow's `docker run`
options fully driven by this action's own well-documented inputs instead of
duplicating RavenDB-specific `--health-cmd` flags in every consumer's workflow file,
and it avoids Docker-in-Docker entirely, since GitHub's Linux runners already have a
Docker daemon.

Startup follows RavenDB's own documented unattended-configuration pattern:
`RAVEN_Setup_Mode=None` skips the interactive setup wizard, and
`RAVEN_Security_UnsecuredAccessAllowed=PrivateNetwork` allows the resulting
unsecured server to accept connections — both are the environment variables
[RavenDB's own Docker documentation](https://docs.ravendb.net/start/containers/dockerfile/dockerfile-overview)
defines for this exact use case, not a workaround invented for this action.
Readiness is confirmed by polling the server's own `/setup/alive` endpoint, and
optional database/sample-data provisioning uses RavenDB's documented REST API
(`PUT /admin/databases`, `POST /databases/<name>/studio/sample-data`) — the
same calls the RavenDB Studio itself makes.

## Security notes

- The server started by this action is **unsecured by design** — no HTTPS, no
  client certificate authentication — because that is the correct, documented way
  to run RavenDB for local development and short-lived CI, where the instance never
  outlives the job and is never reachable from outside the runner.
- Never publish the port this action binds beyond the runner, and never point it at
  data you cannot afford to expose. This action is for ephemeral CI databases only.

## Versioning

This repository has not yet cut a tagged release. Once it does, releases will follow
semantic versioning (`v1`, `v1.2.0`, …) and a rolling major-version tag (`v1`) will
track the latest compatible release, matching the convention most GitHub Actions use.
Until the first tag exists, pin to a commit SHA rather than `@main` if you need
a build that won't change under you.

## Status and scope

This repository is item **D1** of an independent effort to close a specific,
observable gap: at the time this was written, searching the
[GitHub Marketplace](https://github.com/marketplace) for "ravendb" returned zero
results, while comparable databases (MongoDB, DynamoDB, InfluxDB, Couchbase) are
represented by multiple listed actions. This is the free, low-effort fix — a
`setup-<database>`-style action for CI, with no billing and no cloud provisioning.
A separate, materially larger project (a paid GitHub App with RavenDB Cloud
provisioning and billing) is a different, unrelated body of work and is out of
scope for this repository.

If RavenDB (the company) decides to adopt, fork, or officially take over this
project, that is a decision for RavenDB to make — this repository does not presume
it in advance.

## Contributing

Issues and pull requests are welcome. This is a small, focused action — please keep
changes aligned with what's described above rather than expanding scope.

## License

[MIT](LICENSE) © 2026 Lucas R. Tavares

## Related links

- [RavenDB documentation](https://docs.ravendb.net)
- [RavenDB Docker image on Docker Hub](https://hub.docker.com/r/ravendb/ravendb)
- [RavenDB Docker/container documentation](https://docs.ravendb.net/start/containers/general-guide)
- [GitHub Actions metadata syntax reference](https://docs.github.com/en/actions/creating-actions/metadata-syntax-for-github-actions)
