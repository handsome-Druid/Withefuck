#!/usr/bin/env bash
set -euo pipefail

# Withefuck packager (deb + rpm) using fpm
# - Packages the project into /opt/Withefuck
# - No network installs, no user rc modifications at install time
# - After installation, users can run `withefuck-enable` to enable shell logging & function

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING_ROOT="$PROJECT_ROOT/packaging/.stage"
DIST_DIR="$PROJECT_ROOT/packaging/dist"
NAME="withefuck"

mkdir -p "$STAGING_ROOT" "$DIST_DIR"

# Read version and mode from version.txt (expects ...-py or ...-rs)
if [[ ! -f "$PROJECT_ROOT/version.txt" ]]; then
  echo "version.txt not found; aborting" >&2
  exit 1
fi
RAW_VER="$(sed -n '1p' "$PROJECT_ROOT/version.txt" | tr -d '\r' | tr -d ' ')"
case "$RAW_VER" in
  *-py) MODE="py" ;;
  *-rs) MODE="rs" ;;
  *) echo "Invalid version suffix in version.txt ($RAW_VER), expected -py or -rs" >&2; exit 1 ;;
esac
VERSION="${RAW_VER%-py}"
VERSION="${VERSION%-rs}"

echo "Packaging $NAME version=$VERSION mode=$MODE"

pkgroot="$STAGING_ROOT/$NAME"
rm -rf "$pkgroot"

# Files layout inside the package
APP_DIR="$pkgroot/opt/Withefuck"
DOC_DIR="$pkgroot/usr/share/doc/$NAME"
PROFILED_DIR="$pkgroot/etc/profile.d"
ZSHRC_D_DIR="$pkgroot/etc/zsh/zshrc.d"
mkdir -p "$APP_DIR" "$DOC_DIR" "$PROFILED_DIR" "$ZSHRC_D_DIR"

# Copy core project files to /opt/Withefuck
cp -a "$PROJECT_ROOT/wtf.sh" "$APP_DIR/"
cp -a "$PROJECT_ROOT/wtf_profile.sh" "$APP_DIR/"
cp -a "$PROJECT_ROOT/version.txt" "$APP_DIR/"
cp -a "$PROJECT_ROOT/vendor" "$APP_DIR/" 2>/dev/null || true
cp -a "$PROJECT_ROOT/README.md" "$DOC_DIR/" 2>/dev/null || true
cp -a "$PROJECT_ROOT/README.en.md" "$DOC_DIR/" 2>/dev/null || true
cp -a "$PROJECT_ROOT/LICENSE" "$DOC_DIR/" 2>/dev/null || true

# Ensure a default config template exists in package (preserved on upgrade)
if [[ ! -f "$APP_DIR/wtf.json" ]]; then
  echo '{}' > "$APP_DIR/wtf.json"
fi

# Python vs Rust payloads
if [[ "$MODE" == "py" ]]; then
  cp -a "$PROJECT_ROOT/wtf.py" "$APP_DIR/"
  cp -a "$PROJECT_ROOT/wtf_script.py" "$APP_DIR/" 2>/dev/null || true
else
  # Rust mode: include compiled binary into /opt/Withefuck only
  if [[ -x "$PROJECT_ROOT/target/release/wtf" ]]; then
    install -m 0755 "$PROJECT_ROOT/target/release/wtf" "$APP_DIR/wtf"
  elif [[ -x "$PROJECT_ROOT/wtf" ]]; then
    install -m 0755 "$PROJECT_ROOT/wtf" "$APP_DIR/wtf"
  else
    echo "Rust mode selected but no compiled 'wtf' binary found in target/release or project root." >&2
    exit 1
  fi
fi

# Global sourcing: make shell source hooks for all users
cat > "$PROFILED_DIR/withefuck.sh" <<'EOF'
# Withefuck global enablement for Bourne-compatible shells (bash/sh)
# Only proceed in interactive shells
case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac

[ -f /opt/Withefuck/wtf_profile.sh ] && . /opt/Withefuck/wtf_profile.sh
[ -f /opt/Withefuck/wtf.sh ] && . /opt/Withefuck/wtf.sh
EOF
chmod 0644 "$PROFILED_DIR/withefuck.sh"

# Zsh global enablement (where /etc/zsh/zshrc sources zshrc.d)
cat > "$ZSHRC_D_DIR/withefuck.zsh" <<'EOF'
# Withefuck global enablement for zsh
export POWERLEVEL9K_INSTANT_PROMPT=off
if [ -f /opt/Withefuck/wtf_profile.sh ]; then source /opt/Withefuck/wtf_profile.sh; fi
if [ -f /opt/Withefuck/wtf.sh ]; then source /opt/Withefuck/wtf.sh; fi
EOF
chmod 0644 "$ZSHRC_D_DIR/withefuck.zsh"

# Post-install message: guide user to open a new shell and run config
POSTINST="$STAGING_ROOT/postinstall.sh"
cat > "$POSTINST" <<'EOF'
#!/usr/bin/env bash
set -e

echo "\nWithefuck 已安装到 /opt/Withefuck，并已为所有交互式 shell 全局启用。";
echo "- Bash/sh 通过 /etc/profile.d/withefuck.sh 自动加载";
echo "- Zsh (若系统支持) 通过 /etc/zsh/zshrc.d/withefuck.zsh 自动加载";
echo "\n首次使用请在新开的终端运行：wtf --config 进行配置。"
echo "(如写入 /opt/Withefuck/wtf.json 失败，请以 root 账号执行该命令)"
echo "若要在当前会话立即生效，可执行："
echo "  . /opt/Withefuck/wtf_profile.sh && . /opt/Withefuck/wtf.sh"
echo
EOF
chmod 0755 "$POSTINST"

# Post-remove cleanup: remove runtime leftovers (__pycache__, vendor residue, root logs)
POSTRM="$STAGING_ROOT/postremove.sh"
cat > "$POSTRM" <<'EOF'
#!/usr/bin/env bash
set -e

# Remove python cache dirs if any were generated at runtime
find /opt/Withefuck -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
rm -rf /opt/Withefuck/_pycache_ 2>/dev/null || true

# Remove vendor dir if it still exists (should be owned by package, but clean up just in case)
if [ -d /opt/Withefuck/vendor ]; then
  rm -rf /opt/Withefuck/vendor 2>/dev/null || true
fi

# Try to remove the app dir if empty (e.g., only conffiles may remain)
if [ -d /opt/Withefuck ]; then
  rmdir /opt/Withefuck 2>/dev/null || true
fi

# Clean root's session logs if present (user-owned logs in /home/*/.shell_logs are not removed)
if [ -d /root/.shell_logs ]; then
  rm -rf /root/.shell_logs 2>/dev/null || true
fi
EOF
chmod 0755 "$POSTRM"

# Build with fpm
if ! command -v fpm >/dev/null 2>&1; then
  cat <<'TIP' >&2
ERROR: fpm not found.
Install fpm (one-time), for example:
  # Debian/Ubuntu
  sudo apt-get update && sudo apt-get install -y ruby ruby-dev build-essential && sudo gem install --no-document fpm
  # RHEL/CentOS/Fedora
  sudo dnf install -y ruby-devel gcc make rpm-build && sudo gem install --no-document fpm
TIP
  exit 1
fi

COMMON_ARGS=(
  -s dir
  -C "$pkgroot"
  -n "$NAME"
  -v "$VERSION-$MODE"
  --description "Withefuck - shell command fixer with LLM"
  --license "BSD-3-Clause"
  --url "https://github.com/handsome-Druid/Withefuck"
  --maintainer "Withefuck Maintainers <noreply@example.com>"
)

# dependencies common to both modes
DEPENDS=(--depends util-linux)
if [[ "$MODE" == "py" ]]; then
  DEPENDS+=(--depends python3)
fi

echo "Building .deb ..."
fpm -t deb "${COMMON_ARGS[@]}" "${DEPENDS[@]}" \
  --deb-no-default-config-files \
  --config-files /opt/Withefuck/wtf.json \
  --after-install "$POSTINST" \
  --after-remove "$POSTRM" \
  --package "$DIST_DIR/${NAME}_${VERSION}_${MODE}_amd64.deb" \
  .

echo "Building .rpm ..."
fpm -t rpm "${COMMON_ARGS[@]}" "${DEPENDS[@]}" \
  --rpm-os linux \
  --config-files /opt/Withefuck/wtf.json \
  --after-install "$POSTINST" \
  --after-remove "$POSTRM" \
  --package "$DIST_DIR/${NAME}-${VERSION}-${MODE}-1.x86_64.rpm" \
  .

echo
echo "Packages created in: $DIST_DIR"
ls -l "$DIST_DIR" | sed 's/^/  /'
