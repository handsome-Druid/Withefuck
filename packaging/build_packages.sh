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
FISH_VENDOR_DIR="$pkgroot/usr/share/fish/vendor_conf.d"
mkdir -p "$APP_DIR" "$DOC_DIR" "$PROFILED_DIR" "$ZSHRC_D_DIR" "$FISH_VENDOR_DIR"

# Copy core project files to /opt/Withefuck
cp -a "$PROJECT_ROOT/wtf.sh" "$APP_DIR/"
cp -a "$PROJECT_ROOT/wtf_profile.sh" "$APP_DIR/"
# fish scripts (if present)
cp -a "$PROJECT_ROOT/wtf.fish" "$APP_DIR/" 2>/dev/null || true
cp -a "$PROJECT_ROOT/wtf_profile.fish" "$APP_DIR/" 2>/dev/null || true
cp -a "$PROJECT_ROOT/version.txt" "$APP_DIR/"
cp -a "$PROJECT_ROOT/vendor" "$APP_DIR/" 2>/dev/null || true
cp -a "$PROJECT_ROOT/README.md" "$DOC_DIR/" 2>/dev/null || true
cp -a "$PROJECT_ROOT/README.en.md" "$DOC_DIR/" 2>/dev/null || true
cp -a "$PROJECT_ROOT/LICENSE" "$DOC_DIR/" 2>/dev/null || true


# Python vs Rust payloads
if [[ "$MODE" == "py" ]]; then
  cp -a "$PROJECT_ROOT/wtf.py" "$APP_DIR/"
  cp -a "$PROJECT_ROOT/wtf_script.py" "$APP_DIR/" 2>/dev/null || true
else
  # Rust mode: include compiled binary into /opt/Withefuck only
  # Prefer an explicit environment override, then musl target, then default target, then project root
  BIN=""
  if [[ -n "${WTF_BIN:-}" && -x "${WTF_BIN}" ]]; then
    BIN="${WTF_BIN}"
  elif [[ -x "$PROJECT_ROOT/target/x86_64-unknown-linux-musl/release/wtf" ]]; then
    BIN="$PROJECT_ROOT/target/x86_64-unknown-linux-musl/release/wtf"
  elif [[ -x "$PROJECT_ROOT/target/release/wtf" ]]; then
    BIN="$PROJECT_ROOT/target/release/wtf"
  elif [[ -x "$PROJECT_ROOT/wtf" ]]; then
    BIN="$PROJECT_ROOT/wtf"
  fi

  if [[ -z "$BIN" ]]; then
    echo "Rust mode selected but no compiled 'wtf' binary found." >&2
    echo "Checked: \n  $PROJECT_ROOT/target/x86_64-unknown-linux-musl/release/wtf\n  $PROJECT_ROOT/target/release/wtf\n  $PROJECT_ROOT/wtf" >&2
    echo "Hint: set WTF_BIN=/abs/path/to/wtf to override." >&2
    exit 1
  fi

  install -m 0755 "$BIN" "$APP_DIR/wtf"

  # Post-copy size optimizations (best-effort): strip and upx if available
  if command -v strip >/dev/null 2>&1; then
    strip --strip-all "$APP_DIR/wtf" || true
  fi
  if command -v upx >/dev/null 2>&1; then
    upx -9 "$APP_DIR/wtf" || true
  fi
fi

# Global sourcing: make shell source hooks for all users
cat > "$PROFILED_DIR/withefuck.sh" <<'EOF'
# Withefuck global enablement for Bourne-compatible shells (bash/sh)
# Only proceed in interactive shells
case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac

# Prevent double sourcing (when login shell and rc source multiple times)
[ -n "${__WITHEFUCK_SH_LOADED:-}" ] && return 0 2>/dev/null || true
__WITHEFUCK_SH_LOADED=1

[ -f /opt/Withefuck/wtf_profile.sh ] && . /opt/Withefuck/wtf_profile.sh
[ -f /opt/Withefuck/wtf.sh ] && . /opt/Withefuck/wtf.sh
EOF
chmod 0644 "$PROFILED_DIR/withefuck.sh"

# Zsh global enablement (where /etc/zsh/zshrc sources zshrc.d)
cat > "$ZSHRC_D_DIR/withefuck.zsh" <<'EOF'
# Withefuck global enablement for zsh
export POWERLEVEL9K_INSTANT_PROMPT=off
# Prevent double sourcing (some distros load from multiple paths)
if [[ -n "${__WITHEFUCK_SH_LOADED:-}" ]]; then return; fi
__WITHEFUCK_SH_LOADED=1
if [ -f /opt/Withefuck/wtf_profile.sh ]; then source /opt/Withefuck/wtf_profile.sh; fi
if [ -f /opt/Withefuck/wtf.sh ]; then source /opt/Withefuck/wtf.sh; fi
EOF
chmod 0644 "$ZSHRC_D_DIR/withefuck.zsh"

# Fish global enablement (vendor conf.d)
cat > "$FISH_VENDOR_DIR/withefuck.fish" <<'EOF'
# Withefuck global enablement for fish
if status --is-interactive
  if test -f /opt/Withefuck/wtf_profile.fish
    source /opt/Withefuck/wtf_profile.fish
  end
  if test -f /opt/Withefuck/wtf.fish
    source /opt/Withefuck/wtf.fish
  end
end
EOF
chmod 0644 "$FISH_VENDOR_DIR/withefuck.fish"

# Post-install message: guide user to open a new shell and run config
POSTINST="$STAGING_ROOT/postinstall.sh"
cat > "$POSTINST" <<'EOF'
#!/usr/bin/env bash
set -e

echo "Withefuck has been installed to /opt/Withefuck and globally enabled for all interactive shells.";
echo "- Bash/sh loads automatically via /etc/profile.d/withefuck.sh";
echo "- Zsh loads via /etc/zsh/zshrc.d/withefuck.zsh (if supported)";

# Provide a fallback for Ubuntu/Debian systems where zshrc.d is not enabled:
# If /etc/zsh/zshrc exists and doesn't contain the Withefuck marker, append a safe interactive loading snippet.
if command -v zsh >/dev/null 2>&1; then
  if [ -f /etc/zsh/zshrc ]; then
    if ! grep -q 'Withefuck BEGIN' /etc/zsh/zshrc 2>/dev/null; then
  echo "Detected that /etc/zsh/zshrc does not enable zshrc.d; wrote global fallback snippet (with markers)."
      umask 022
      cat >> /etc/zsh/zshrc <<'ZRC'
# Withefuck BEGIN: global enablement (added by package post-install)
# Only takes effect in interactive zsh; keep minimal intrusion
if [[ -o interactive ]]; then
  export POWERLEVEL9K_INSTANT_PROMPT=off
  # Prevent double sourcing
  if [[ -n "${__WITHEFUCK_SH_LOADED:-}" ]]; then
    return
  fi
  __WITHEFUCK_SH_LOADED=1
  [ -f /opt/Withefuck/wtf_profile.sh ] && . /opt/Withefuck/wtf_profile.sh
  [ -f /opt/Withefuck/wtf.sh ] && . /opt/Withefuck/wtf.sh
fi
# Withefuck END
ZRC
    fi
  fi
fi

echo "For first use, run \"wtf --config\" in a new terminal to configure."
echo "(If writing to /opt/Withefuck/wtf.json fails, run the command as root)"
echo "To apply immediately in the current session, run:"
echo "  . /opt/Withefuck/wtf_profile.sh && . /opt/Withefuck/wtf.sh && wtf --config"
echo
echo "Or for fish shell:"
echo "  . /opt/Withefuck/wtf_profile.fish && . /opt/Withefuck/wtf.fish && wtf --config"
echo
EOF
chmod 0755 "$POSTINST"

# Post-remove cleanup: remove runtime leftovers and revert zsh fallback block
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

# Remove the fallback snippet that may have been added to /etc/zsh/zshrc in post-install
if [ -f /etc/zsh/zshrc ]; then
  if grep -q 'Withefuck BEGIN' /etc/zsh/zshrc 2>/dev/null; then
    tmpfile="$(mktemp)"
    # Delete everything between the markers (including marker lines)
    sed '/Withefuck BEGIN: global enablement (added by package post-install)/,/Withefuck END/d' \
      /etc/zsh/zshrc > "$tmpfile" 2>/dev/null || true
    if [ -s "$tmpfile" ]; then
      cat "$tmpfile" > /etc/zsh/zshrc 2>/dev/null || true
    fi
    rm -f "$tmpfile" 2>/dev/null || true
  fi
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

# dependencies
# - util-linux: for 'script' and other common tools
# - python3: only for py mode
# - ca-certificates: for rs mode when using reqwest+rustls with native roots
DEPENDS=(--depends util-linux --depends script)
if [[ "$MODE" == "py" ]]; then
  DEPENDS+=(--depends python3)
else
  DEPENDS+=(--depends ca-certificates)
fi

echo "Building .deb ..."
fpm -t deb "${COMMON_ARGS[@]}" "${DEPENDS[@]}" \
  --deb-no-default-config-files \
  --after-install "$POSTINST" \
  --after-remove "$POSTRM" \
  --package "$DIST_DIR/${NAME}_${VERSION}_${MODE}_amd64.deb" \
  .

echo "Building .rpm ..."
fpm -t rpm "${COMMON_ARGS[@]}" "${DEPENDS[@]}" \
  --rpm-os linux \
  --after-install "$POSTINST" \
  --after-remove "$POSTRM" \
  --package "$DIST_DIR/${NAME}-${VERSION}-${MODE}-1.x86_64.rpm" \
  .

echo
echo "Packages created in: $DIST_DIR"
ls -l "$DIST_DIR" | sed 's/^/  /'