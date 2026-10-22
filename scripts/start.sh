#!/usr/bin/env bash
# Starts an official ravendb/ravendb Docker container configured for unattended,
# unsecured use in CI, waits for it to report ready, and optionally provisions
# a database (with RavenDB's built-in Northwind sample data).
set -euo pipefail

: "${VERSION:?VERSION is required}"
: "${PORT:?PORT is required}"
: "${CONTAINER_NAME:?CONTAINER_NAME is required}"
: "${STARTUP_TIMEOUT:?STARTUP_TIMEOUT is required}"
DATABASE_NAME="${DATABASE_NAME:-}"
LOAD_SAMPLE_DATA="${LOAD_SAMPLE_DATA:-false}"

# Reject values that would break the JSON body / docker arguments below.
# RavenDB database names allow letters, digits, '_', '-' and '.'.
if [ -n "${DATABASE_NAME}" ] && ! [[ "${DATABASE_NAME}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "::error::database-name '${DATABASE_NAME}' may only contain letters, digits, '_', '-' and '.'"
  exit 1
fi
if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then
  echo "::error::port '${PORT}' must be an integer between 1 and 65535"
  exit 1
fi
if ! [[ "${STARTUP_TIMEOUT}" =~ ^[0-9]+$ ]] || [ "${STARTUP_TIMEOUT}" -lt 1 ]; then
  echo "::error::startup-timeout-seconds '${STARTUP_TIMEOUT}' must be a positive integer"
  exit 1
fi
if ! [[ "${CONTAINER_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
  echo "::error::container-name '${CONTAINER_NAME}' is not a valid Docker container name"
  exit 1
fi

IMAGE="ravendb/ravendb:${VERSION}"
URL="http://localhost:${PORT}"

if docker inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  echo "::error::a Docker container named '${CONTAINER_NAME}' already exists; choose another container-name or remove it"
  exit 1
fi

echo "::group::Pulling ${IMAGE}"
if ! docker pull "${IMAGE}"; then
  echo "::endgroup::"
  echo "::error::could not pull ${IMAGE}; check that the version tag exists at https://hub.docker.com/r/ravendb/ravendb/tags"
  exit 1
fi
echo "::endgroup::"

# From here on, never leave a half-started container behind on failure.
cleanup_on_failure() {
  status=$?
  if [ "${status}" -ne 0 ]; then
    docker rm --force "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi
}
trap cleanup_on_failure EXIT

echo "::group::Starting RavenDB (container: ${CONTAINER_NAME}, port: ${PORT})"
# RAVEN_Setup_Mode=None skips the interactive setup wizard; combined with
# RAVEN_Security_UnsecuredAccessAllowed=PrivateNetwork this starts an unsecured
# (no HTTPS/client certificate) server, which is fine for an ephemeral CI
# runner but must never be used for anything reachable from outside the job.
# See: https://docs.ravendb.net/start/containers/dockerfile/dockerfile-overview
if ! docker run --detach \
  --name "${CONTAINER_NAME}" \
  --publish "${PORT}:8080" \
  --env RAVEN_Setup_Mode=None \
  --env RAVEN_Security_UnsecuredAccessAllowed=PrivateNetwork \
  --env RAVEN_License_Eula_Accepted=true \
  --env RAVEN_ARGS="--log-to-console" \
  "${IMAGE}"; then
  echo "::endgroup::"
  echo "::error::docker run failed (is host port ${PORT} already in use?)"
  exit 1
fi
echo "::endgroup::"

echo "Waiting up to ${STARTUP_TIMEOUT}s for RavenDB to answer at ${URL}/setup/alive ..."
deadline=$((SECONDS + STARTUP_TIMEOUT))
until curl --fail --silent --max-time 2 --output /dev/null "${URL}/setup/alive" 2>/dev/null; do
  if [ "$(docker inspect --format '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)" != "true" ]; then
    echo "::error::RavenDB container exited before becoming ready"
    docker logs "${CONTAINER_NAME}" || true
    exit 1
  fi
  if [ "${SECONDS}" -ge "${deadline}" ]; then
    echo "::error::RavenDB did not become ready within ${STARTUP_TIMEOUT}s"
    echo "::group::docker logs ${CONTAINER_NAME}"
    docker logs "${CONTAINER_NAME}" || true
    echo "::endgroup::"
    exit 1
  fi
  sleep 1
done
echo "RavenDB is up at ${URL}"

if [ -n "${DATABASE_NAME}" ]; then
  echo "Creating database '${DATABASE_NAME}'..."
  curl --fail --silent --show-error --max-time 60 -X PUT "${URL}/admin/databases" \
    --header "Content-Type: application/json" \
    --data "{\"DatabaseName\": \"${DATABASE_NAME}\"}" \
    --output /dev/null

  if [ "${LOAD_SAMPLE_DATA}" = "true" ]; then
    echo "Loading the Northwind sample dataset into '${DATABASE_NAME}'..."
    curl --fail --silent --show-error --max-time 120 -X POST \
      "${URL}/databases/${DATABASE_NAME}/studio/sample-data" \
      --output /dev/null
  fi
fi

{
  echo "url=${URL}"
  echo "container-id=$(docker inspect --format '{{.Id}}' "${CONTAINER_NAME}")"
} >> "${GITHUB_OUTPUT}"
