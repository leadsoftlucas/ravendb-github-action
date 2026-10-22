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

IMAGE="ravendb/ravendb:${VERSION}"
URL="http://localhost:${PORT}"

echo "::group::Pulling ${IMAGE}"
docker pull "${IMAGE}"
echo "::endgroup::"

echo "::group::Starting RavenDB (container: ${CONTAINER_NAME}, port: ${PORT})"
# RAVEN_Setup_Mode=None skips the interactive setup wizard; combined with
# RAVEN_Security_UnsecuredAccessAllowed=PrivateNetwork this starts an unsecured
# (no HTTPS/client certificate) server, which is fine for an ephemeral CI
# runner but must never be used for anything reachable from outside the job.
# See: https://docs.ravendb.net/start/containers/dockerfile/dockerfile-overview
docker run --detach \
  --name "${CONTAINER_NAME}" \
  --publish "${PORT}:8080" \
  --env RAVEN_Setup_Mode=None \
  --env RAVEN_Security_UnsecuredAccessAllowed=PrivateNetwork \
  --env RAVEN_License_Eula_Accepted=true \
  --env RAVEN_ARGS="--log-to-console" \
  "${IMAGE}"
echo "::endgroup::"

echo "Waiting up to ${STARTUP_TIMEOUT}s for RavenDB to answer at ${URL}/setup/alive ..."
deadline=$((SECONDS + STARTUP_TIMEOUT))
until curl --fail --silent --show-error --output /dev/null "${URL}/setup/alive" 2>/dev/null; do
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
  curl --fail --silent --show-error -X PUT "${URL}/admin/databases" \
    --header "Content-Type: application/json" \
    --data "{\"DatabaseName\": \"${DATABASE_NAME}\"}" \
    --output /dev/null

  if [ "${LOAD_SAMPLE_DATA}" = "true" ]; then
    echo "Loading the Northwind sample dataset into '${DATABASE_NAME}'..."
    curl --fail --silent --show-error -X POST \
      "${URL}/databases/${DATABASE_NAME}/studio/sample-data" \
      --output /dev/null
  fi
fi

{
  echo "url=${URL}"
  echo "container-id=$(docker ps -q --filter "name=^${CONTAINER_NAME}$")"
} >> "${GITHUB_OUTPUT}"
