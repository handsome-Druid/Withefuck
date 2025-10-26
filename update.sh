#!/usr/bin/env bash

set -e

pwd=$(cd "$(dirname "$0")" && pwd)
_version="$(cat "$pwd/version.txt" 2>/dev/null || echo "unknown")"
echo "dir : $pwd"
if [ -f "$pwd/wtf.py" ]; then
    echo "Updating wtf-py via git..."
    (cd "$pwd" && git pull origin python) || { echo "git pull failed; aborting." >&2; exit 1; }
    if [ "$(cat "$pwd/version.txt" 2>/dev/null)" = "$_version" ]; then
        echo "wtf-py is already up to date (version $_version)."
        exit 0
    fi
elif [ -f "$pwd/Cargo.toml" ]; then
    echo "Updating wtf-rs via git..."
    # Pull latest changes from rust branch and detect if anything changed
    if cd "$pwd"; then
        pull_output=$(git pull origin rust 2>&1) || { echo "git pull failed; aborting." >&2; exit 1; }
        echo "$pull_output"
        # If repository already up to date, skip further work early
        if echo "$pull_output" | grep -q "Already up to date"; then
            echo "wtf-rs is already up to date (version $_version)."
            exit 0
        fi
        # If a fast-forward/merge happened, check if Rust sources or build files changed
        if git rev-parse -q --verify 'HEAD@{1}' >/dev/null 2>&1; then
            if ! git diff --name-only 'HEAD@{1}' HEAD | grep -E -q '\\.(rs)$'; then
                echo "No changes detected in rust code; skipping build."
                exit 0
            fi
        fi
    else
        echo "Failed to cd to $pwd; aborting." >&2
        exit 1
    fi
    if [ "$(cat "$pwd/version.txt" 2>/dev/null)" = "$_version" ]; then
        echo "wtf-rs is already up to date (version $_version)."
        exit 0
    fi
fi

ensure_rust_build() {
    # If cargo available, rebuild

    if [ -f "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
    fi

    if command -v cargo >/dev/null 2>&1; then
        echo "cargo found. Building release binary..."
        (cd "$pwd" && cargo clean && cargo build --release) || { echo "cargo build failed; aborting." >&2; return 1; }
        if [ -f "$pwd/target/release/wtf" ]; then
            cp "$pwd/target/release/wtf" "$pwd/wtf"
            chmod +x "$pwd/wtf"
            echo "Built binary copied to $pwd/wtf"
            return 0
        fi
        echo "target/release/wtf not found after build." >&2
        return 1
    fi

    # Install toolchain then build
    echo "cargo not found. Attempting to install Rust toolchain and build..."
    if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
        pkg_mgr=${pkg_mgr:-}
        if command -v apt >/dev/null 2>&1; then pkg_mgr="apt"; else pkg_mgr="apt-get"; fi
        echo "Installing build dependencies via $pkg_mgr (requires sudo)..."
        sudo $pkg_mgr update || { echo "sudo $pkg_mgr update failed" >&2; return 1; }
        sudo $pkg_mgr install -y build-essential curl pkg-config libssl-dev || { echo "sudo $pkg_mgr install failed" >&2; return 1; }
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        if command -v dnf >/dev/null 2>&1; then pkg_mgr="dnf"; else pkg_mgr="yum"; fi
        echo "Installing build dependencies via $pkg_mgr (requires sudo)..."
        if ! sudo $pkg_mgr groupinstall -y "Development Tools" 2>/dev/null; then
            sudo $pkg_mgr install -y gcc make curl openssl-devel pkgconfig || { echo "sudo $pkg_mgr install failed" >&2; return 1; }
        fi
        sudo $pkg_mgr install -y curl openssl-devel pkgconfig || true
    else
        echo "No supported package manager found (apt/dnf/yum). Please install Rust (rustup) manually: https://rustup.rs" >&2
        return 1
    fi

    echo "Installing rustup (non-interactive)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || { echo "rustup installation failed" >&2; return 1; }
    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck disable=SC1090
        . "$HOME/.cargo/env"
    fi
    if ! command -v cargo >/dev/null 2>&1; then
        echo "cargo still not available after rustup install; aborting." >&2
        return 1
    fi
    echo "Building release binary..."
    (cd "$pwd" && cargo build --release) || { echo "cargo build failed; aborting." >&2; return 1; }
    if [ -f "$pwd/target/release/wtf" ]; then
        cp "$pwd/target/release/wtf" "$pwd/wtf"
        chmod +x "$pwd/wtf"
        echo "Built binary copied to $pwd/wtf"
        return 0
    fi
    echo "target/release/wtf not found after build; aborting." >&2
    return 1
}



if [ -f "$pwd/Cargo.toml" ]; then
    ensure_rust_build
fi
