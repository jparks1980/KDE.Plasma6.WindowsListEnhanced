#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
APPLET_DIR="$ROOT_DIR/window-list-enhanced"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$ROOT_DIR/.build/package"
APPLET_ID="org.kde.plasma.windowlistenhanced"
PACKAGE_FILE="$DIST_DIR/${APPLET_ID}.plasmoid"
REAL_HOME="$(getent passwd "$USER" | cut -d: -f6)"
REAL_XDG_DATA_HOME="$REAL_HOME/.local/share"
REAL_XDG_CONFIG_HOME="$REAL_HOME/.config"
REAL_XDG_CACHE_HOME="$REAL_HOME/.cache"

compute_widget_version() {
    if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local commit_count
        commit_count="$(git -C "$ROOT_DIR" rev-list --count HEAD)"
        echo "1.0.${commit_count}"
        return
    fi

    echo ""
}

apply_staged_version() {
    local widget_version="$1"

    if [[ -z "$widget_version" ]]; then
        return
    fi

    if grep -Eq '"Version"[[:space:]]*:' "$STAGE_DIR/metadata.json"; then
        sed -E -i "s/(\"Version\"[[:space:]]*:[[:space:]]*\")[^\"]*(\"[[:space:]]*,)/\\1${widget_version}\\2/" "$STAGE_DIR/metadata.json"
    else
        sed -E -i "s/(\"License\"[[:space:]]*:[[:space:]]*\"[^\"]*\",)/\\1\n        \"Version\": \"${widget_version}\",/" "$STAGE_DIR/metadata.json"
    fi

    echo "Using widget version: $widget_version"
}

usage() {
    cat <<'EOF'
Usage: scripts/build-deploy.sh [build|deploy|restart|all]

Commands:
  build    Create a .plasmoid package archive in ./dist
    deploy   Install or upgrade the applet, then restart Plasma
    deploy-no-restart  Install or upgrade without restarting Plasma
  restart  Restart Plasma shell to reload applets
  all      Build, deploy, and restart (default)
EOF
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command not found: $cmd" >&2
        exit 1
    fi
}

assert_project_layout() {
    if [[ ! -f "$APPLET_DIR/metadata.json" ]]; then
        echo "Error: metadata.json not found at: $APPLET_DIR" >&2
        exit 1
    fi
}

stage_package_layout() {
    assert_project_layout

    rm -rf "$STAGE_DIR"
    mkdir -p "$STAGE_DIR/contents/ui" "$STAGE_DIR/contents/config"

    cp "$APPLET_DIR/metadata.json" "$STAGE_DIR/metadata.json"
    apply_staged_version "$(compute_widget_version)"

    cp "$APPLET_DIR/main.qml" "$STAGE_DIR/contents/ui/main.qml"
    cp "$APPLET_DIR/MenuButton.qml" "$STAGE_DIR/contents/ui/MenuButton.qml"
    cp "$APPLET_DIR/ConfigGeneral.qml" "$STAGE_DIR/contents/ui/ConfigGeneral.qml"

    cp "$APPLET_DIR/config.qml" "$STAGE_DIR/contents/config/config.qml"
    cp "$APPLET_DIR/main.xml" "$STAGE_DIR/contents/config/main.xml"

    # Keep extraction helpers in staged package for parity with source tree.
    cp "$APPLET_DIR/Messages.sh" "$STAGE_DIR/Messages.sh"
}

build_package() {
    require_cmd zip
    stage_package_layout

    mkdir -p "$DIST_DIR"
    rm -f "$PACKAGE_FILE"

    (
        cd "$STAGE_DIR"
        zip -qr "$PACKAGE_FILE" .
    )

    echo "Built package: $PACKAGE_FILE"
}

deploy_applet() {
    require_cmd kpackagetool6
    stage_package_layout

    if env HOME="$REAL_HOME" \
        XDG_DATA_HOME="$REAL_XDG_DATA_HOME" \
        XDG_CONFIG_HOME="$REAL_XDG_CONFIG_HOME" \
        XDG_CACHE_HOME="$REAL_XDG_CACHE_HOME" \
        kpackagetool6 --type Plasma/Applet --upgrade "$STAGE_DIR"; then
        echo "Upgraded applet: $APPLET_ID"
    else
        env HOME="$REAL_HOME" \
            XDG_DATA_HOME="$REAL_XDG_DATA_HOME" \
            XDG_CONFIG_HOME="$REAL_XDG_CONFIG_HOME" \
            XDG_CACHE_HOME="$REAL_XDG_CACHE_HOME" \
            kpackagetool6 --type Plasma/Applet --install "$STAGE_DIR"
        echo "Installed applet: $APPLET_ID"
    fi
}

restart_plasma() {
    if ! command -v kquitapp6 >/dev/null 2>&1 || ! command -v plasmashell >/dev/null 2>&1; then
        echo "Skipping restart: kquitapp6 or plasmashell not found"
        return 0
    fi

    env HOME="$REAL_HOME" \
        XDG_DATA_HOME="$REAL_XDG_DATA_HOME" \
        XDG_CONFIG_HOME="$REAL_XDG_CONFIG_HOME" \
        XDG_CACHE_HOME="$REAL_XDG_CACHE_HOME" \
        kquitapp6 plasmashell || true
    nohup env HOME="$REAL_HOME" \
        XDG_DATA_HOME="$REAL_XDG_DATA_HOME" \
        XDG_CONFIG_HOME="$REAL_XDG_CONFIG_HOME" \
        XDG_CACHE_HOME="$REAL_XDG_CACHE_HOME" \
        plasmashell >/dev/null 2>&1 &
    echo "Restarted plasmashell"
}

ACTION="${1:-all}"

case "$ACTION" in
    build)
        build_package
        ;;
    deploy)
        deploy_applet
        restart_plasma
        ;;
    deploy-no-restart)
        deploy_applet
        ;;
    restart)
        restart_plasma
        ;;
    all)
        build_package
        deploy_applet
        restart_plasma
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
