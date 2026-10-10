#!/usr/bin/env bash
# Build Mobius for Ubuntu Linux via Docker
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "\n${CYAN}=== Building Mobius for Ubuntu Linux via Docker ===${NC}"

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[FAIL] Docker is not installed or not in PATH.${NC}"
    exit 1
fi

DIST_DIR="$ROOT/dist"
mkdir -p "$DIST_DIR"

export DOCKER_BUILDKIT=1
echo -e "${YELLOW}Starting Docker BuildKit build with Dockerfile.ubuntu...${NC}"
echo -e "Outputs will be exported to: $DIST_DIR\n"

if docker build -f "$ROOT/Dockerfile.ubuntu" --target export -o "$DIST_DIR" "$ROOT"; then
    echo -e "\n${GREEN}[ OK ] Docker build succeeded! Artifacts exported to ./dist:${NC}"
    ls -lh "$DIST_DIR"
    exit 0
fi

echo -e "\n${YELLOW}BuildKit export target failed, falling back to volume mount extract...${NC}"
docker build -f "$ROOT/Dockerfile.ubuntu" -t mobius-ubuntu "$ROOT"
docker run --rm -v "$DIST_DIR:/output" mobius-ubuntu cp -r /build/mobius/dist/. /output/

echo -e "\n${GREEN}[ OK ] Linux Ubuntu artifacts ready in ./dist:${NC}"
ls -lh "$DIST_DIR"
