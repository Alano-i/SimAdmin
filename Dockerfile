# syntax=docker/dockerfile:1.7

FROM node:24-bookworm-slim AS frontend-builder
WORKDIR /src/frontend
RUN corepack enable && corepack prepare pnpm@9 --activate
COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile
COPY frontend/ ./
COPY static /src/static
RUN pnpm run build

FROM rust:1-bookworm AS backend-builder
WORKDIR /src
COPY VERSION ./
COPY backend/Cargo.toml backend/Cargo.lock backend/build.rs ./backend/
COPY backend/src ./backend/src
WORKDIR /src/backend
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/backend/target \
    cargo build --locked --release && \
    cp target/release/simadmin /tmp/simadmin

FROM debian:bookworm-slim AS runtime

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      dbus \
      iproute2 \
      iptables \
      libqmi-utils \
      modemmanager \
      net-tools \
      network-manager \
      procps \
      systemd \
      tar \
      unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/simadmin
COPY --from=backend-builder /tmp/simadmin ./simadmin
COPY --from=frontend-builder /src/frontend/dist ./www

RUN mkdir -p /data /opt/simadmin/lpac \
    && chmod 0755 /opt/simadmin/simadmin

ENV HOST=0.0.0.0 \
    PORT=3000 \
    RUST_LOG=info \
    SIMADMIN_CONTAINER=1 \
    SIMADMIN_DATA_DIR=/data \
    DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket

EXPOSE 3000
VOLUME ["/data", "/opt/simadmin/lpac"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/api/health" >/dev/null || exit 1

ENTRYPOINT ["/opt/simadmin/simadmin"]
CMD ["serve"]
