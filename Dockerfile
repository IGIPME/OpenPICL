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

# System dependencies for compilation (plus curl/ca-certs for the binary fetches)
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    curl \
    ca-certificates \
    build-essential \
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

# Create minimal dummy sources so cargo can resolve & pre-compile the dependency
# graph (native server target) in a cached layer. cargo-leptos uses a separate
# target dir (target/server) for the real build, so this warm-up is best-effort
# caching of the shared dependency crates; skip lib/wasm warm-up here to save
# memory and time.
RUN mkdir -p app/src frontend/src server/src renderer/src worker/src protocol/src && \
    echo 'pub fn dummy() {}' > app/src/lib.rs && \
    echo '#[wasm_bindgen::prelude::wasm_bindgen] pub fn hydrate() {}' > frontend/src/lib.rs && \
    echo 'fn main() {}' > server/src/main.rs && \
    echo 'pub fn dummy() {}' > renderer/src/lib.rs && \
    echo 'pub fn dummy() {}' > worker/src/lib.rs && \
    echo 'pub fn dummy() {}' > protocol/src/lib.rs && \
    mkdir -p style && touch style/main.scss && \
    mkdir -p public

# Pre-build server dependencies with the low-memory server profile.
# dummy main.rs has no real code, so this only compiles the dependency crates —
# the expensive part — and the layer is cached across source edits.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/build/target \
    cargo build --release -p server

# Now copy the actual source code and build the full project.
# cargo-leptos handles: WASM compilation, wasm-bindgen, SCSS, and server binary.
COPY . .

# Build artifacts out to a known location the runtime stage can COPY from.
# (The cache mount is on /build/target, so we must persist the final binary and
# site assets into the image layer itself.)
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/build/target \
    cargo leptos build --release && \
    cp -a target/server/release/server /usr/local/bin/open-picl && \
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
# container is reachable from Zeabur's proxy on the exposed port.
ENV LEPTOS_OUTPUT_NAME="open-picl"
ENV LEPTOS_SITE_ROOT="site"
ENV LEPTOS_SITE_PKG_DIR="pkg"
ENV LEPTOS_SITE_ADDR="0.0.0.0:3000"
ENV LEPTOS_RELOAD_PORT="3001"
ENV LEPTOS_ASSETS_DIR="public"
ENV LEPTOS_ENV="PROD"
ENV RUST_LOG="info"

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3000/ || exit 1

CMD ["open-picl"]
