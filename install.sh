#!/usr/bin/env bash
#!/usr/bin/env bash
set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Determine install directory
pwd=$(cd "$(dirname "$0")" && pwd)
echo "install_dir : $pwd"
echo "Home : $HOME"

# Decide install mode strictly by version.txt suffix: "*-py" or "*-rs"
version_file="$pwd/version.txt"
if [ ! -f "$version_file" ]; then
    echo "ERROR: version.txt not found in $pwd. Installation aborted." >&2
    exit 1
fi

raw_ver="$(sed -n '1p' "$version_file" | tr -d '\r' | tr -d ' ')"
case "$raw_ver" in
    *-py)
        install_mode="python"
        ;;
    *-rs)
        install_mode="rust"
        ;;
    *)
        echo "ERROR: Invalid version suffix in version.txt ('$raw_ver'). Expected to end with -py or -rs. Installation aborted." >&2
        exit 1
        ;;
esac

# Helper: add sourcing line to rc files if not already present
add_source_line() {
    local rcfile="$1"
    local src_cmd="$2"
    local target="$3"
    if [ -f "$rcfile" ] && ! grep -q "$target" "$rcfile"; then
        echo "$src_cmd $target" >> "$rcfile"
    fi
}

# Ensure profile symlink and script links exist
ln -sf "$pwd/wtf_profile.sh" "$HOME/.wtf_profile.sh"
chmod +x "$HOME/.wtf_profile.sh"
ln -sf "$pwd/wtf.sh" "$HOME/.wtf.sh"

chmod +x "$pwd/uninstall.sh"

# Choose install path based on version.txt directive only
# - If ends with -rs: build and install Rust binary
# - If ends with -py: install Python scripts

ensure_rust_build() {
    # If binary already available, skip
    if command -v wtf >/dev/null 2>&1 || [ -f "$pwd/wtf" ]; then
        echo "wtf binary already present; skipping Rust build step."
        return 0
    fi

    # If cargo available, build
    if command -v cargo >/dev/null 2>&1; then
        echo "cargo found. Building release binary..."
        (cd "$pwd" && cargo build --release) || { echo "cargo build failed; aborting." >&2; return 1; }
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

ensure_python_env(){
    if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    echo "python not found. Attempting to install Python..."
    if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
        pkg_mgr=${pkg_mgr:-}
        if command -v apt >/dev/null 2>&1; then pkg_mgr="apt"; else pkg_mgr="apt-get"; fi
        echo "Installing build dependencies via $pkg_mgr (requires sudo)..."
        sudo $pkg_mgr update || { echo "sudo $pkg_mgr update failed" >&2; return 1; }
        sudo $pkg_mgr install -y python3 || { echo "sudo $pkg_mgr install failed" >&2; return 1; }
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        if command -v dnf >/dev/null 2>&1; then pkg_mgr="dnf"; else pkg_mgr="yum"; fi
        echo "Installing build dependencies via $pkg_mgr (requires sudo)..."
        sudo $pkg_mgr install -y python3 || { echo "sudo $pkg_mgr install failed" >&2; return 1; }
    else
        echo "No supported package manager found (apt/dnf/yum). Please install Rust (rustup) manually: https://rustup.rs" >&2
        return 1
    fi
}

install_python_scripts() {
    chmod +x "$pwd/wtf.py"
    chmod +x "$pwd/wtf_script.py" || true

    # Create symlinks in /usr/local/bin
    ln -sf "$pwd/wtf.py" /usr/local/bin/wtf.py || true
    ln -sf "$pwd/wtf_script.py" /usr/local/bin/wtf_script.py || true
    ln -sf "$pwd/uninstall.sh" /usr/local/bin/uninstall.sh || true
}

install_rust_binary() {
    # assume ensure_rust_build has been run and $pwd/wtf exists
    if [ -f "$pwd/wtf" ]; then
        ln -sf "$pwd/wtf" /usr/local/bin/wtf || true
        chmod +x /usr/local/bin/wtf || true
    fi
    # expose uninstall helper
    ln -sf "$pwd/uninstall.sh" /usr/local/bin/uninstall.sh || true
}

# Execute the chosen install flow (no silent fallback)
case "$install_mode" in
  rust)
    echo "version.txt ends with -rs: using Rust build/install flow."
    if ! ensure_rust_build; then
        echo "ERROR: Rust build failed. Installation aborted because version.txt requires -rs." >&2
        exit 1
    fi
    install_rust_binary
    ;;
  python)
    echo "version.txt ends with -py: using Python script installation."
    if [ ! -f "$pwd/wtf.py" ]; then
        echo "ERROR: Python mode selected by version.txt, but wtf.py not found. Installation aborted." >&2
        exit 1
    fi
    if ! ensure_python_env; then
        echo "ERROR: Python environment setup failed. Installation aborted because version.txt requires -py." >&2
        exit 1
    fi
    install_python_scripts
    ;;
  *)
    echo "ERROR: Unknown install_mode '$install_mode'." >&2
    exit 1
    ;;
esac

# Add sourcing lines to shell rc files
for rcfile in ~/.bashrc ~/.zshrc ~/.ashrc; do
    if [ -f "$rcfile" ]; then
        if echo "$rcfile" | grep -q "ashrc"; then
            src_cmd="."
        else
            src_cmd="source"
        fi
        add_source_line "$rcfile" "$src_cmd" "$HOME/.wtf.sh"
        add_source_line "$rcfile" "$src_cmd" "$HOME/.wtf_profile.sh"
    fi
done

# Source the scripts into current shell (best-effort)
if [ -f "$HOME/.wtf.sh" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.wtf.sh" || true
fi
if [ -f "$HOME/.wtf_profile.sh" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.wtf_profile.sh" || true
fi

# Run initial configuration using the installed interface
if [ "$install_mode" = "rust" ]; then
    if command -v wtf >/dev/null 2>&1; then
        wtf --config || true
    elif [ -x "$pwd/wtf" ]; then
        "$pwd/wtf" --config || true
    fi
elif [ "$install_mode" = "python" ]; then
    if [ -x "$pwd/wtf.py" ]; then
        "$pwd/wtf.py" --config || true
    elif command -v python3 >/dev/null 2>&1 && [ -f "$pwd/wtf.py" ]; then
        python3 "$pwd/wtf.py" --config || true
    fi
fi

echo "Withefuck has been installed successfully."
echo "Please run:"
echo
echo "      . ~/.wtf_profile.sh && . ~/.wtf.sh"
echo
echo "or restart your terminal session to start logging."