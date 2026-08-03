#!/usr/bin/env bash
# Every kind node is a fresh container with its own containerd image
# store, so `kind load docker-image` has to be redone after every single
# `kind create cluster` - the load doesn't survive a cluster recreate.
#
# On a server with no outbound internet, these upstream images (pulled
# once wherever there is internet, then `docker save | ssh ... docker
# load`d onto this host) would otherwise leave every pod stuck in
# ImagePullBackOff. This script only loads images that are already
# sitting in the host's docker - if one isn't there, it's skipped
# silently and Kubernetes just pulls it from the internet as normal, so
# this is a no-op on a machine that already has network access.
#
# Keep this list in sync with the versions pinned elsewhere: ECK_VERSION
# in k8s/eck/install-eck-operator.sh, `version:` in
# k8s/eck/elasticsearch.yaml/kibana.yaml, the fluent-bit image in
# k8s/fleet/fake-node-daemonset.yaml, and the kubeai/kubeai-model-loader
# versions pulled in by k8s/kubeai/vendor's chart version.
set -euo pipefail

CLUSTER_NAME="${1:-gpu-sim}"

IMAGES=(
  docker.elastic.co/elasticsearch/elasticsearch:8.15.0
  docker.elastic.co/kibana/kibana:8.15.0
  docker.elastic.co/eck/eck-operator:2.14.0
  fluent/fluent-bit:3.1
  ghcr.io/kubeai-project/kubeai:v0.23.4
  ghcr.io/kubeai-project/kubeai-model-loader:v0.14.0
)

TO_LOAD=()
for img in "${IMAGES[@]}"; do
  if docker image inspect "$img" >/dev/null 2>&1; then
    TO_LOAD+=("$img")
  fi
done

if [ "${#TO_LOAD[@]}" -eq 0 ]; then
  echo "No pre-cached upstream images found on this host - Kubernetes will pull them from the internet as normal."
else
  echo "Preloading ${#TO_LOAD[@]} already-cached image(s) into every node of '$CLUSTER_NAME'..."
  kind load docker-image "${TO_LOAD[@]}" --name "$CLUSTER_NAME"
fi
