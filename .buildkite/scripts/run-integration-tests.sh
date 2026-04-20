#!/usr/bin/env bash
set -euo pipefail

# Script to run integration tests in Buildkite CI environment
# This script handles setup, execution, and cleanup of integration tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default values
SUITE=${SUITE:-""}
BROWSER=${BROWSER:-"chromium"}
HEADLESS=${HEADLESS:-"true"}
TIMEOUT=${TIMEOUT:-"60000"}
RETRIES=${RETRIES:-"1"}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -s, --suite SUITE       Test suite to run (required)
  -b, --browser BROWSER   Browser to use (default: chromium)
  --no-headless           Run browser in headed mode
  -t, --timeout MS        Test timeout in milliseconds (default: 60000)
  -r, --retries N         Number of retries on failure (default: 1)
  -h, --help              Show this help message
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|--suite)
        SUITE="$2"
        shift 2
        ;;
      -b|--browser)
        BROWSER="$2"
        shift 2
        ;;
      --no-headless)
        HEADLESS="false"
        shift
        ;;
      -t|--timeout)
        TIMEOUT="$2"
        shift 2
        ;;
      -r|--retries)
        RETRIES="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

check_dependencies() {
  log "Checking required dependencies..."
  local deps=("docker" "docker-compose" "node" "yarn")
  for dep in "${deps[@]}"; do
    if ! command -v "${dep}" &>/dev/null; then
      die "Required dependency not found: ${dep}"
    fi
  done
  log "All dependencies satisfied."
}

setup_environment() {
  log "Setting up test environment for suite: ${SUITE}"
  cd "${ROOT_DIR}"

  # Ensure the test network exists
  docker network inspect integration-tests &>/dev/null || \
    docker network create integration-tests

  # Pull required images
  log "Pulling Docker images..."
  docker-compose -f internal/suites/docker-compose.yml pull --quiet 2>/dev/null || true
}

run_tests() {
  log "Starting integration tests for suite: ${SUITE}"
  log "Browser: ${BROWSER}, Headless: ${HEADLESS}, Timeout: ${TIMEOUT}ms, Retries: ${RETRIES}"

  cd "${ROOT_DIR}"

  local exit_code=0

  SUITE="${SUITE}" \
  BROWSER="${BROWSER}" \
  HEADLESS="${HEADLESS}" \
  yarn test:integration \
    --timeout "${TIMEOUT}" \
    --retries "${RETRIES}" \
    --suite "${SUITE}" || exit_code=$?

  return ${exit_code}
}

cleanup() {
  log "Cleaning up test environment..."
  cd "${ROOT_DIR}"
  docker-compose -f internal/suites/docker-compose.yml down --volumes --remove-orphans 2>/dev/null || true
  log "Cleanup complete."
}

main() {
  parse_args "$@"

  [[ -z "${SUITE}" ]] && die "Test suite must be specified. Use -s or --suite."

  check_dependencies
  setup_environment

  trap cleanup EXIT INT TERM

  run_tests
  local result=$?

  if [[ ${result} -eq 0 ]]; then
    log "Integration tests passed for suite: ${SUITE}"
  else
    log "Integration tests FAILED for suite: ${SUITE} (exit code: ${result})"
  fi

  exit ${result}
}

main "$@"
