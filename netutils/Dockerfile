# syntax=docker/dockerfile:1
FROM debian:trixie-20260406-slim@sha256:5fb70129351edec3723d13f427400ecae3f13b83750e23ad47c46721effcf2db
ENTRYPOINT ["sleep", "infinity"]
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  dnsutils \
  iproute2 \
  iputils-ping \
  net-tools \
  netcat-openbsd \
  tcpdump \
  traceroute && \
  rm -rf /var/lib/apt/lists/*
