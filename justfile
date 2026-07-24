set windows-shell := ["powershell.exe"]
export RUST_BACKTRACE := "1"

# 展示可用的命令
@just:
    just --list

#
[windows]
mise:
    choco install mise

#
[unix]
mise:
    curl https://mise.run | sh

#
init:
    mise install

#
[windows]
assets:
    mkdir build
    Copy-Item -Path "./public" -Destination "./build/public" -Recurse -Force

#
[unix]
assets:
    mkdir build
    cp -r ./public ./build/public

# 启动 Leptos 前端（通过 Trunk 工具），默认不自动打开页面
serve:
    trunk serve

#
build:
    trunk build --release
    tar -czvf OpenPICL.tar.gz build

# 清理构建产物（Windows）
[windows]
clean:
    cargo clean
    Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue

# 清理构建产物（Unix）
[unix]
clean:
    cargo clean
    rm -rf build