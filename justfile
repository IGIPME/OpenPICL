set windows-shell := ["powershell.exe"]
export RUST_BACKTRACE := "1"

# 展示可用的命令
@just:
    just --list

# 安装 mise 工具
[windows]
mise:
    choco install mise

# 安装 mise 工具
[unix]
mise:
    curl https://mise.run | sh

# 安装依赖
init:
    mise install

# 启动 Leptos 前端
serve:
    cargo leptos watch

# 构建 OpenPICL 项目
build:
    cargo leptos build --release

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