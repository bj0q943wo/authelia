#!/usr/bin/env bash
set -euo pipefail

# Build and optionally push Docker images for Authelia.
# Usage: build-docker.sh [--push]

DOCKER_IMAGE="${DOCKER_IMAGE:-authelia/authelia}"
DOCKER_PLATFORMS="${DOCKER_PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v7}"
BUILDKITE_BRANCH="${BUILDKITE_BRANCH:-main}"
BUILDKITE_COMMIT="${BUILDKITE_COMMIT:-dev}"
PUSH=false

for arg in "$@"; do
  case $arg in
    --push)
      PUSH=true
      shift
      ;;
  esac
done

# Determine Docker tags based on branch/tag
TAGS=()
if [[ "${BUILDKITE_TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  VERSION="${BUILDKITE_TAG#v}"
  MAJOR=$(echo "${VERSION}" | cut -d. -f1)
  MINOR=$(echo "${VERSION}" | cut -d. -f2)
  TAGS+=(
    "${DOCKER_IMAGE}:${VERSION}"
    "${DOCKER_IMAGE}:${MAJOR}.${MINOR}"
    "${DOCKER_IMAGE}:${MAJOR}"
    "${DOCKER_IMAGE}:latest"
  )
elif [[ "${BUILDKITE_BRANCH}" == "main" ]]; then
  TAGS+=(
    "${DOCKER_IMAGE}:master"
    "${DOCKER_IMAGE}:${BUILDKITE_COMMIT:0:8}"
  )
else
  SAFE_BRANCH=$(echo "${BUILDKITE_BRANCH}" | sed 's/[^a-zA-Z0-9._-]/-/g')
  TAGS+=("${DOCKER_IMAGE}:${SAFE_BRANCH}")
fi

echo "--- :docker: Building Docker image"
echo "Platforms: ${DOCKER_PLATFORMS}"
echo "Tags:"
for tag in "${TAGS[@]}"; do
  echo "  - ${tag}"
done

# Build tag arguments
TAG_ARGS=()
for tag in "${TAGS[@]}"; do
  TAG_ARGS+=("--tag" "${tag}")
done

# Set up buildx builder if not already present
if ! docker buildx inspect authelia-builder &>/dev/null; then
  echo "--- :docker: Creating buildx builder"
  docker buildx create --name authelia-builder --use --bootstrap
else
  docker buildx use authelia-builder
fi

BUILD_ARGS=(
  "--platform" "${DOCKER_PLATFORMS}"
  "--build-arg" "LDFLAGS_EXTRA=-X 'github.com/authelia/authelia/v4/internal/utils.BuildTag=${BUILDKITE_TAG:-}'"
  "--build-arg" "COMMIT_ID=${BUILDKITE_COMMIT}"
  "${TAG_ARGS[@]}"
)

if [[ "${PUSH}" == "true" ]]; then
  echo "--- :docker: Building and pushing"
  docker buildx build "${BUILD_ARGS[@]}" --push .
else
  echo "--- :docker: Building (no push)"
  docker buildx build "${BUILD_ARGS[@]}" --output type=image,push=false .
fi

echo "--- :docker: Build complete"