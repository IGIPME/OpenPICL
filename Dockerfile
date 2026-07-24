# =============================================================================
# OpenPICL - Multi-stage Docker Build
# Leptos 0.8 + Axum full-stack Rust application
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder - Compile the entire project
# -----------------------------------------------------------------------------
FROM rust:1.91-slim-bookworm AS builder

# Install system dependencies for compilation
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    curl \
    ca-certificates \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install dart-sass for SCSS compilation
RUN curl -fsSL https://github.com/sass/dart-sass/releases/download/1.83.4/dart-sass-1.83.4-linux-x64.tar.gz \
    | tar xz -C /usr/local/bin --strip-components=1 && \
    chmod +x /usr/local/bin/sass

# Install wasm-bindgen-cli (version matching Cargo.toml)
RUN curl -fsSL https://github.com/rustwasm/wasm-bindgen/releases/download/0.2.126/wasm-bindgen-0.2.126-x86_64-unknown-linux-musl.tar.gz \
    | tar xz -C /usr/local/bin --strip-components=1 && \
    chmod +x /usr/local/bin/wasm-bindgen*

# Set Rust to nightly channel and add WASM target
RUN rustup toolchain install nightly && \
    rustup default nightly && \
    rustup target add wasm32-unknown-unknown && \
    rustup component add rustfmt clippy rust-src rust-analyzer

# Install cargo-leptos (the build orchestrator)
RUN cargo install cargo-leptos --locked

# Set working directory
WORKDIR /build

# Copy dependency manifests first for better caching
COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY app/Cargo.toml ./app/
COPY frontend/Cargo.toml ./frontend/
COPY server/Cargo.toml ./server/
COPY renderer/Cargo.toml ./renderer/
COPY worker/Cargo.toml ./worker/
COPY protocol/Cargo.toml ./protocol/

# Create dummy source files to cache dependency builds
RUN mkdir -p app/src frontend/src server/src renderer/src worker/src protocol/src && \
    echo 'pub fn dummy() {}' > app/src/lib.rs && \
    echo '#[wasm_bindgen::prelude::wasm_bindgen] pub fn hydrate() {}' > frontend/src/lib.rs && \
    echo '#[tokio::main] async fn main() {}' > server/src/main.rs && \
    echo 'pub fn dummy() {}' > renderer/src/lib.rs && \
    echo 'pub fn dummy() {}' > worker/src/lib.rs && \
    echo 'pub fn dummy() {}' > protocol/src/lib.rs && \
    mkdir -p style && touch style/main.scss && \
    mkdir -p public

# Pre-build dependencies: compile for native server target (this layer gets cached)
RUN cargo build --release -p server

# Now copy the actual source code
COPY . .

# Build the full project in release mode
# cargo-leptos handles: WASM compilation, wasm-bindgen, SCSS, and server binary
RUN cargo leptos build --release

# -----------------------------------------------------------------------------
# Stage 2: Runtime - Minimal production image
# -----------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

# Install minimal runtime dependencies (curl needed for healthcheck)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser

# Copy the compiled server binary
COPY --from=builder /build/target/server/release/server /usr/local/bin/open-picl

# Copy the static site assets
COPY --from=builder /build/target/site /opt/open-picl/site

# Copy public assets (favicon, etc.)
COPY --from=builder /build/public /opt/open-picl/public

# Set ownership
RUN chown -R appuser:appuser /opt/open-picl

# Switch to non-root user
USER appuser

# Working directory (where site/ and public/ are expected)
WORKDIR /opt/open-picl

# Environment variables for Leptos runtime configuration
ENV LEPTOS_OUTPUT_NAME="open-picl"
ENV LEPTOS_SITE_ROOT="site"
ENV LEPTOS_SITE_PKG_DIR="pkg"
ENV LEPTOS_SITE_ADDR="0.0.0.0:3000"
ENV LEPTOS_RELOAD_PORT="3001"
ENV LEPTOS_ASSETS_DIR="public"
ENV LEPTOS_ENV="PROD"

# Expose the application port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3000/ || exit 1

# Run the server
CMD ["open-picl"]
