#!/usr/bin/env bash
# Builds and (re)starts the central proxy relay container on the "kind"
# docker network. Run this once after `kind create cluster` - kind names
# that network "kind" regardless of which cluster you create, so this
# container's name is a stable target for every node, every time.
#
# host.docker.internal:host-gateway lets this one container reach the
# real proxy (v2ray) running on your host, without any node needing to
# know the host's address itself.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The relay container doesn't exist yet at build time, so its own `apk add`
# step can't route through it - it has to reach the host's real proxy
# directly via host.docker.internal, same as the running container does.
docker build \
  --add-host=host.docker.internal:host-gateway \
  --build-arg HTTP_PROXY=http://host.docker.internal:10808 \
  --build-arg HTTPS_PROXY=http://host.docker.internal:10808 \
  --build-arg NO_PROXY=localhost,127.0.0.1 \
  -t kind-proxy-relay:local "$SCRIPT_DIR/proxy-relay"

docker rm -f kind-proxy-relay >/dev/null 2>&1 || true
docker run -d --name kind-proxy-relay \
  --network kind \
  --add-host=host.docker.internal:host-gateway \
  --restart unless-stopped \
  kind-proxy-relay:local

echo "kind-proxy-relay is up, forwarding to host.docker.internal:10808"
