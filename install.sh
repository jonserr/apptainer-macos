#!/usr/bin/env bash
#
# install.sh
# Set up Apptainer on macOS through a Docker-backed wrapper
#
set -euo pipefail

# ----- config ----------------------------------------------------------------
APPT_VER="${APPT_VER:-1.4.5}"
USE_LATEST_APPTAINER="${USE_LATEST_APPTAINER:-false}"

BIN_DIR="$HOME/.local/bin"
WRAPPER="$BIN_DIR/apptainer"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SRC="$SCRIPT_DIR/bin/apptainer"

export PATH="$BIN_DIR:$PATH"

# ----- helpers ---------------------------------------------------------------
brew_install_formula() {
    local pkg="$1"

    if brew list --formula --versions "$pkg" >/dev/null 2>&1; then
        echo "  $pkg already installed; skipping."
    else
        echo "  Installing $pkg ..."
        brew install "$pkg" || echo "  Warning: $pkg reported an issue; continuing."
    fi
}

brew_install_cask() {
    local cask="$1"
    local app_path="${2:-}"

    if brew list --cask --versions "$cask" >/dev/null 2>&1; then
        echo "  $cask already installed through Homebrew; skipping."
        return 0
    fi

    if [[ -n "${app_path}" && -d "${app_path}" ]]; then
        echo "  Found existing app at ${app_path}; skipping Homebrew cask install for ${cask}."
        echo "  To adopt it into Homebrew later, run:"
        echo "     brew install --cask --adopt ${cask}"
        return 0
    fi

    echo "  Installing $cask ..."
    brew install --cask "$cask" || return 1
}

install_docker_desktop() {
    brew_install_cask docker-desktop "/Applications/Docker.app" || {
        echo "Failed to install Docker Desktop through Homebrew." >&2
        echo "Install Docker Desktop manually, then re-run this script." >&2
        exit 1
    }
}

start_docker_desktop() {
    if docker info >/dev/null 2>&1; then
        echo "Docker daemon already running."
        return 0
    fi

    if [[ ! -d "/Applications/Docker.app" ]]; then
        echo "Docker Desktop not found at /Applications/Docker.app. Installing..."
        install_docker_desktop
    fi

    echo "Starting Docker Desktop from /Applications/Docker.app..."
    open "/Applications/Docker.app" >/dev/null 2>&1 || {
        echo "Failed to launch /Applications/Docker.app." >&2
        exit 1
    }

    printf "Waiting for Docker daemon"

    for _ in $(seq 1 90); do
        if docker info >/dev/null 2>&1; then
            printf " ready.\n"
            return 0
        fi

        printf "."
        sleep 2
    done

    printf "\n"
    echo "Docker is still not running." >&2
    echo "Open Docker Desktop manually, accept any first-run prompts, then re-run this script." >&2
    exit 1
}

resolve_latest_apptainer_version() {
    if [[ "${USE_LATEST_APPTAINER}" != "true" ]]; then
        return 0
    fi

    if ! command -v skopeo >/dev/null 2>&1; then
        echo "skopeo is required for USE_LATEST_APPTAINER=true." >&2
        echo "Installing skopeo..."
        brew_install_formula skopeo
    fi

    echo "Resolving ghcr.io/apptainer/apptainer:latest..."

    local latest_version
    latest_version="$(skopeo list-tags docker://ghcr.io/apptainer/apptainer | jq -r '.Tags[]' | tail -n 1)"

    if [[ -z "${latest_version}" ]]; then
        echo "Could not resolve a version label from :latest; keeping APPT_VER=${APPT_VER}." >&2
        return 0
    fi

    APPT_VER="${latest_version}"
    echo "Resolved latest Apptainer version: ${APPT_VER}"
}

# ----- 1) Homebrew -----------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew already installed; skipping."
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# ----- 2) CLI and VM tooling -------------------------------------------------
echo "Checking CLI and VM tools..."
brew_install_formula docker
brew_install_formula docker-compose
brew_install_formula colima
brew_install_formula qemu
brew_install_formula lima
brew_install_formula jq
brew_install_formula skopeo

# ----- 3) Docker Desktop daemon ----------------------------------------------
echo "Checking Docker Desktop..."
install_docker_desktop
start_docker_desktop

# ----- 4) resolve/pull Apptainer image ---------------------------------------
resolve_latest_apptainer_version

IMAGE="ghcr.io/apptainer/apptainer:${APPT_VER}"

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Image ${IMAGE} already present; skipping pull."
else
    echo "Pulling ${IMAGE} ..."

    if ! docker pull "$IMAGE"; then
        echo "Could not pull ${IMAGE}." >&2
        echo "Confirm the tag exists:" >&2
        echo "  ghcr.io/apptainer/apptainer:${APPT_VER}" >&2
        exit 1
    fi
fi

# ----- 5) install wrapper ----------------------------------------------------
if [[ ! -f "$WRAPPER_SRC" ]]; then
    echo "Wrapper template not found at $WRAPPER_SRC" >&2
    exit 1
fi

mkdir -p "$BIN_DIR"
cp "$WRAPPER_SRC" "$WRAPPER"
sed -i '' "s|__APPT_VER__|${APPT_VER}|g" "$WRAPPER"
chmod +x "$WRAPPER"

echo "Installed wrapper at $WRAPPER using Apptainer ${APPT_VER}."

# ----- 6) PATH setup ---------------------------------------------------------
add_line() {
    grep -qsF "$1" "$2" 2>/dev/null || echo "$1" >> "$2"
}

touch "$HOME/.zshrc"
touch "$HOME/.bashrc"

add_line 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc"
add_line 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"
add_line 'alias apptainer="$HOME/.local/bin/apptainer"' "$HOME/.zshrc"

cat << EOF

Done. Apptainer ${APPT_VER} is linked at:
  ${WRAPPER}

Test:
  apptainer --version

Build example:
  apptainer build my_container.sif my_container.def

EOF
