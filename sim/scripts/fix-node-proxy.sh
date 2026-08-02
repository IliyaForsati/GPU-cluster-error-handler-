#!/usr/bin/env bash
# Points every kind node's proxy config at the central kind-proxy-relay
# container (see setup-proxy-relay.sh) instead of the wrong 127.0.0.1
# address kind copies in from the host. Run this once after
# setup-proxy-relay.sh, every time you create the cluster fresh.
#
# Fixes both places a node reads its proxy from:
#   - the systemd DefaultEnvironment file (used by containerd, so image
#     pulls for pods work)
#   - the static pod manifests for the control-plane components (kubeadm
#     bakes the same wrong proxy value into these on the control-plane
#     node)
set -euo pipefail

CLUSTER_NAME="${1:-gpu-sim}"
PROXY_URL="http://kind-proxy-relay:10808"

for node in $(kind get nodes --name "$CLUSTER_NAME"); do
  echo "Fixing proxy on $node -> $PROXY_URL"

  docker exec "$node" sed -i -E \
    "s#https?://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:10808#${PROXY_URL}#g" \
    /etc/systemd/system.conf.d/proxy-default-environment.conf

  # Only the control-plane node has these manifests. Worker nodes make the
  # "[ -f "$f" ]" check fail on every file, and since that failure would be
  # the last command's exit status, it would kill this whole script under
  # "set -e" in the caller - so this inner shell always ends on "exit 0".
  docker exec "$node" sh -c '
    for f in /etc/kubernetes/manifests/kube-apiserver.yaml \
             /etc/kubernetes/manifests/kube-controller-manager.yaml \
             /etc/kubernetes/manifests/kube-scheduler.yaml; do
      [ -f "$f" ] && sed -i -E "s#https?://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:10808#'"${PROXY_URL}"'#g" "$f"
    done
    exit 0
  '

  docker exec "$node" systemctl daemon-reload
  docker exec "$node" systemctl restart containerd
done

echo "Done. All nodes now proxy through kind-proxy-relay."
