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
# step needs *some* route to the internet - on a machine with a local
# proxy (e.g. your laptop with v2ray) that's host.docker.internal:10808.
# On a locked-down server with no outbound proxy at all, don't try to
# fix that server-wide - instead build this image wherever you do have
# network access and hand it over as a plain file, no server config
# touched:
#   docker save kind-proxy-relay:local | ssh <user>@<server> 'docker load'
# If the image is already present (built locally or loaded this way),
# skip the build entirely - this is what makes the script safe to run
# on a server with no internet access of its own.
if docker image inspect kind-proxy-relay:local >/dev/null 2>&1; then
  echo "kind-proxy-relay:local already present, skipping build"
else
  # Bounded so a machine with neither internet nor a proxy on 10808 fails
  # fast and loud instead of hanging - see the block comment above for
  # the two ways to actually fix that (transfer the image, or run a
  # proxy on 10808).
  timeout 120 docker build \
    --add-host=host.docker.internal:host-gateway \
    --build-arg HTTP_PROXY=http://host.docker.internal:10808 \
    --build-arg HTTPS_PROXY=http://host.docker.internal:10808 \
    --build-arg NO_PROXY=localhost,127.0.0.1 \
    -t kind-proxy-relay:local "$SCRIPT_DIR/proxy-relay"
fi

docker rm -f kind-proxy-relay >/dev/null 2>&1 || true
docker run -d --name kind-proxy-relay \
  --network kind \
  --add-host=host.docker.internal:host-gateway \
  --restart unless-stopped \
  kind-proxy-relay:local

echo "kind-proxy-relay is up, forwarding to host.docker.internal:10808"
