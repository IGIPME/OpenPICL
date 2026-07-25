# =============================================================================
# OpenPICL - Multi-stage Docker Build
# Leptos 0.8 + Axum full-stack Rust application
#
# Tuned for memory-constrained build hosts (e.g. 2GB VMs): limits cargo
# parallelism, avoids LTO on the native server build, and uses prebuilt
# binaries for cargo-leptos / dart-sass to skip extra source compilations.
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder - Compile the entire project
# -----------------------------------------------------------------------------
FROM rust:1.91-slim-bookworm AS builder

# Limit how many translation units cargo runs in parallel. The default (one per
# CPU) makes the link/codegen memory peak far exceed what a small VM can give;
# capping it keeps RSS bounded and prevents OOM-killed builds at the cost of
# longer wall-clock time.
ENV CARGO_BUILD_JOBS=1
ENV CARGO_HTTP_MULTIPLEXING=true
# Persist useful crate info if the build aborts.
ENV RUST_BACKTRACE=1
# Override the [profile.release] settings (lto=true, codegen-units=1, opt-level='z')
# at the env level so they apply to BOTH the server (native) and client (wasm)
# builds that cargo-leptos runs with --release. LTO's link-time memory peak is
# the main OOM risk on a 2GB host; disabling it (and spreading codegen across
# 16 units) keeps the peak bounded at the cost of larger binaries — the right
# tradeoff for deployment builds on a memory-constrained VM.
ENV CARGO_PROFILE_RELEASE_LTO=false
ENV CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16

# System dependencies for compilation (plus curl/ca-certs for the binary fetches).
# clang + lld are required: the repo's .cargo/config.toml forces clang as the
# linker with `-fuse-ld=lld` for the native linux target (set up for the local
# Nix/mise dev shell, which provides them). The base rust image only ships gcc.
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    curl \
    ca-certificates \
    build-essential \
    clang \
    lld \
    && rm -rf /var/lib/apt/lists/*

# dart-sass for SCSS compilation (prebuilt binary — avoids a build from source)
RUN curl -fsSL https://github.com/sass/dart-sass/releases/download/1.83.4/dart-sass-1.83.4-linux-x64.tar.gz \
    | tar xz -C /usr/local/bin --strip-components=1 && \
    chmod +x /usr/local/bin/sass

# wasm-bindgen-cli (prebuilt binary, version pinned to match Cargo.toml)
RUN curl -fsSL https://github.com/rustwasm/wasm-bindgen/releases/download/0.2.126/wasm-bindgen-0.2.126-x86_64-unknown-linux-musl.tar.gz \
    | tar xz -C /usr/local/bin --strip-components=1 && \
    chmod +x /usr/local/bin/wasm-bindgen*

# Nightly toolchain (from rust-toolchain.toml) + WASM target.
# rust-analyzer is intentionally NOT installed: it is only useful in an editor
# and adds a large download + install time to the build image.
RUN rustup toolchain install nightly --profile minimal \
        -c rustfmt,clippy,rust-src \
        -t wasm32-unknown-unknown,x86_64-unknown-linux-gnu && \
    rustup default nightly

# cargo-leptos from a prebuilt release binary (pinned) to avoid compiling it
# from source. v0.3.7 pairs with Leptos 0.8.x.
ARG CARGO_LEPTOS_VERSION=v0.3.7
RUN ARCH=$(uname -m) && \
    curl -fsSL "https://github.com/leptos-rs/cargo-leptos/releases/download/${CARGO_LEPTOS_VERSION}/cargo-leptos-${ARCH}-unknown-linux-gnu.tar.gz" \
    | tar xz -C /usr/local/bin --strip-components=1 && \
    chmod +x /usr/local/bin/cargo-leptos && \
    cargo-leptos --version

WORKDIR /build

# Copy dependency manifests first for better layer caching.
COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY app/Cargo.toml ./app/
COPY frontend/Cargo.toml ./frontend/
COPY server/Cargo.toml ./server/
COPY renderer/Cargo.toml ./renderer/
COPY worker/Cargo.toml ./worker/
COPY protocol/Cargo.toml ./protocol/

# Now copy the actual source code and build the full project.
# cargo-leptos handles: WASM compilation, wasm-bindgen, SCSS, and the server
# binary (the README's `target/server/release` path is NOT reliable: this
# version of cargo-leptos builds the server bin into the default target dir
# without `--target-dir`, so the binary may land at target/release/server,
# target/server/release/server, or elsewhere depending on the tool version).
COPY . .

# Build the project and extract artifacts into the image layer.
#
# A prior layer-caching trick (pre-compiling deps against dummy sources, then
# reusing the build via a cache mount on /build/target) was removed: cargo-
# leptos recompiles from a clean target dir on each service build regardless,
# and a stale/dummy binary could otherwise leak into the image. The registry
# cache is retained; the target cache is intentionally NOT mounted so each
# build is reproducible and the correct (fresh) binary is produced.
#
# After building, locate the server binary with `find` to be robust to the
# exact target-dir layout, verify it is the real binary (file type), and
# export it plus the site assets. If the binary cannot be found, print the
# candidate paths so the failure is diagnosable instead of a bare cp error.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo leptos build --release && \
    SERVER_BIN="$(find target -type f -name server -path '*/release/server' -exec test -x {} \; -print | head -1)" && \
    if [ -z "$SERVER_BIN" ]; then \
        echo "!! server binary not found; dumping candidate paths:"; \
        find target -type f -name 'server' -print 2>/dev/null; \
        echo "!! target/release listing:"; ls -la target/release 2>/dev/null; \
        echo "!! target/server/release listing:"; ls -la target/server/release 2>/dev/null; \
        exit 1; \
    fi && \
    echo "found server binary at: $SERVER_BIN" && \
    test -x "$SERVER_BIN" && \
    ls -la "$SERVER_BIN" && \
    cp -a "$SERVER_BIN" /usr/local/bin/open-picl && \
    mkdir -p /export && cp -a target/site /export/site && cp -a public /export/public

# -----------------------------------------------------------------------------
# Stage 2: Runtime - Minimal production image
# -----------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

# Minimal runtime dependencies (curl needed for healthcheck)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Non-root user for security
RUN useradd --create-home --shell /bin/bash appuser

# Copy the compiled server binary and assets produced in the builder stage.
COPY --from=builder /usr/local/bin/open-picl /usr/local/bin/open-picl
COPY --from=builder /export/site /opt/open-picl/site
COPY --from=builder /export/public /opt/open-picl/public

RUN chown -R appuser:appuser /opt/open-picl

USER appuser
WORKDIR /opt/open-picl

# Leptos runtime configuration. LEPTOS_SITE_ADDR must bind 0.0.0.0 so the
# container is reachable from Zeabur's proxy. Zeabur routes external HTTP to
# the service's web port (8080 by default), so bind 8080 (not the leptos
# default 3000) to avoid a port-mismatch 502/404 at the proxy.
ENV LEPTOS_OUTPUT_NAME="open-picl"
ENV LEPTOS_SITE_ROOT="site"
ENV LEPTOS_SITE_PKG_DIR="pkg"
ENV LEPTOS_SITE_ADDR="0.0.0.0:8080"
ENV LEPTOS_RELOAD_PORT="3001"
ENV LEPTOS_ASSETS_DIR="public"
ENV LEPTOS_ENV="PROD"
ENV RUST_LOG="info"
ENV LOGTO_ENDPOINT=https://ufrjei.logto.app
ENV LOGTO_APP_ID=17trhj5ohcsqrgh6ht241
ENV LOGTO_APP_SECRET=${LOGTO_APP_SECRET}
ENV LOGTO_REDIRECT_URI=https://open-picl.zeabur.app/callback
ENV LOGTO_POST_LOGOUT_URI=https://open-picl.zeabur.app


EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

CMD ["open-picl"]
