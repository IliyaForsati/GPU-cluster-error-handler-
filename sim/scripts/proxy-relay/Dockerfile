# This container is the ONE fixed target every kind node points its proxy
# at. kind copies the host's HTTP_PROXY/HTTPS_PROXY into every node at
# creation time as "http://127.0.0.1:10808" - wrong inside a container, and
# the raw fix (the kind network's gateway IP) changes with every recreate.
# A container name is stable across recreates, so nodes never need editing
# again: they always talk to "kind-proxy-relay", and only this one
# container needs to know how to reach the real proxy on the host.
FROM alpine:3.20
RUN apk add --no-cache socat
ENTRYPOINT ["sh", "-c", "socat TCP-LISTEN:10808,fork,reuseaddr TCP:host.docker.internal:10808"]
