# Zeabur Deployment Notes

This project (Leptos 0.8 + Axum + wgpu) is deployed to Zeabur from the
`main` branch of `github.com/IGIPME/OpenPICL` via the root `Dockerfile`.
Zeabur auto-rebuilds on every push to `main`.

## Identifiers (reuse these — do NOT create duplicate services)

- Project ID: `6a6373077bcbc56e70a0b5bc` (name `open-picl`, Seoul Tencent server)
- Service ID: `6a6375817bcbc56e70a0b675` (Git/GitHub deploy)
- Public URL: https://open-picl.zeabur.app
- Listen port: `8080` (Zeabur's default web port — see below)

## Redeploying after a code change

Just push to `main`. Zeabur triggers a new build automatically. To force a
redeploy of an existing service explicitly:

```bash
npx zeabur@latest deploy --project-id 6a6373077bcbc56e70a0b5bc \
  --service-id 6a6375817bcbc56e70a0b675 --json
```

Always pass `--service-id` when redeploying; omitting it creates a NEW
duplicate service.

## Critical deployment-specific config (do not regress)

1. **App binds port 8080, not 3000.** `LEPTOS_SITE_ADDR=0.0.0.0:8080`,
   `EXPOSE 8080`, healthcheck on 8080. Zeabur routes external HTTP to the
   service's web port (defaults to 8080); binding 3000 causes 502/404.
2. **Build image needs `clang` + `lld`** (installed in the Dockerfile) because
   `.cargo/config.toml` forces `linker = "clang"` with `-fuse-ld=lld` for the
   native linux target. The base `rust:slim` image only ships gcc.
3. **Low-memory build on the 2GB server**: `CARGO_BUILD_JOBS=1`,
   `CARGO_PROFILE_RELEASE_LTO=false`, `CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16`
   cap the compile/link memory peak (LTO is what OOMs a 2GB host).
4. **Server binary located with `find`**, not a hardcoded path. This version
   of `cargo-leptos` writes the server bin to `target/release/server` (default
   target dir), not the README's `target/server/release/server`.
5. **`cargo-leptos` installed from a pinned prebuilt binary** (v0.3.7), using
   `tar ... --strip-components=1` (the release tarball wraps the binary in a
   top-level dir).
6. Do NOT use bare `file`/`netstat` in the Dockerfile — neither exists in
   `rust:slim`. Use `test -x` / `ls` and read `/proc/net/tcp` instead.

## Watching a build

```bash
npx zeabur@latest deployment list --service-id 6a6375817bcbc56e70a0b675 -i=false --json
npx zeabur@latest deployment log --deployment-id <DEPLOYMENT_ID> -t build -i=false
npx zeabur@latest deployment log --service-id 6a6375817bcbc56e70a0b675 -t runtime -i=false
```

## Dashboard

https://zeabur.com/projects/6a6373077bcbc56e70a0b5bc
