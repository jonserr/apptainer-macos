#!/usr/bin/env bash
#
# install.sh
# Set up Apptainer on macOS via a Docker-backed wrapper, plus VM tooling.
#
#   * Hardcoded Apptainer version (modify APPT_VER below if needed)
#   * Installs Homebrew (if missing), QEMU + Lima, and Docker Desktop.
#   * Installs the apptainer wrapper (bin/apptainer) to ~/.local/bin/apptainer
#   * Builds/runs Red Hat-family (.sif) images out of the box.
#
# Apptainer is Linux-only, so on macOS it runs inside a Linux container.
# Docker Desktop provides the Linux VM.
# Steps are idempotent: anything already installed is skipped
# if `apptainer --version` already works the script exits
#
# Note: you may be prompted for your admin password (Homebrew + Docker Desktop
# first run), and Docker Desktop's first launch may ask you to accept terms.

set -euo pipefail

# ----- config ----------------------------------------------------------------
APPT_VER="1.4.5"
IMAGE="ghcr.io/apptainer/apptainer:${APPT_VER}"
BIN_DIR="$HOME/.local/bin"
WRAPPER="$BIN_DIR/apptainer"

# Resolve the directory this script lives in so we can find bin/apptainer.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SRC="$SCRIPT_DIR/bin/apptainer"

# Make a previously-installed wrapper visible to the check below.
export PATH="$BIN_DIR:$PATH"

# ----- helpers ---------------------------------------------------------------
# Install a Homebrew formula only if it isn't already installed.
brew_install_formula() {
	local pkg="$1"
	if brew list --formula --versions "$pkg" > /dev/null 2>&1; then
		echo "  $pkg already installed; skipping."
	else
		echo "  Installing $pkg ..."
		brew install "$pkg" || echo "  Warning: $pkg reported an issue; continuing."
	fi
}

# Install a Homebrew cask only if it isn't already installed.
brew_install_cask() {
	local cask="$1"
	if brew list --cask --versions "$cask" > /dev/null 2>&1; then
		echo "  $cask already installed; skipping."
		return 0
	fi
	echo "  Installing $cask ..."
	brew install --cask "$cask" \
		|| brew install --cask --force "$cask" \
		|| return 1
}

install_docker_desktop() {
	# The 'docker' formula is CLI-only; the cask 'docker-desktop' ships the daemon.
	brew_install_cask docker-desktop \
		|| {
			echo "Failed to install Docker Desktop via Homebrew. Install it manually:" >&2
			echo "  https://www.docker.com/products/docker-desktop" >&2
			exit 1
		}
}

# ----- 0) already installed? -------------------------------------------------
if command -v apptainer > /dev/null 2>&1 && apptainer --version > /dev/null 2>&1; then
	echo "apptainer already installed: $(apptainer --version)"
	exit 0
fi

# ----- 1) Homebrew -----------------------------------------------------------
if ! command -v brew > /dev/null 2>&1; then
	echo "Homebrew not found. Installing..."
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
	echo "Homebrew already installed; skipping."
fi
# Load brew into THIS shell (Apple Silicon = /opt/homebrew, Intel = /usr/local).
if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
if [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi

# ----- 2) VM tools -----------------------------------------------------------
# Docker Desktop already ships the Linux VM the wrapper uses. QEMU + Lima are
# installed too in case you want a native Lima VM instead:
#   limactl start template://apptainer
echo "Checking VM tooling (qemu, lima)..."
brew_install_formula qemu
brew_install_formula lima

# ----- 3) Docker (CLI + daemon) ----------------------------------------------
if ! command -v docker > /dev/null 2>&1; then
	echo "Docker CLI not found. Installing Docker Desktop..."
	install_docker_desktop
else
	echo "Docker CLI already present; skipping install."
fi

# A CLI alone has no daemon on macOS; make sure the Desktop app is present.
if [ ! -d "/Applications/Docker.app" ] && ! docker info > /dev/null 2>&1; then
	echo "Docker daemon not available. Installing Docker Desktop..."
	install_docker_desktop
fi

# Start Docker Desktop and wait for the daemon to come up.
if ! docker info > /dev/null 2>&1; then
	echo "Starting Docker Desktop..."
	open -a Docker 2> /dev/null || open -a "Docker Desktop" 2> /dev/null || true
	printf "Waiting for Docker to start"
	for _ in $(seq 1 90); do
		if docker info > /dev/null 2>&1; then printf " ready.\n"; break; fi
		printf "."
		sleep 2
	done
fi
if ! docker info > /dev/null 2>&1; then
	echo "Docker is still not running! Try the following:"
	echo "1. Open Docker Desktop"
	echo "2. Accept the first-time prompts."
	echo "3. Wait for the whale icon to settle, then re-run this script."
	exit 1
fi

# ----- 4) pull the Apptainer image (fail fast on a bad tag) ------------------
if docker image inspect "$IMAGE" > /dev/null 2>&1; then
	echo "Image ${IMAGE} already present; skipping pull."
else
	echo "Pulling ${IMAGE} ..."
	if ! docker pull "$IMAGE"; then
		echo "Could not pull ${IMAGE}." >&2
		echo "Confirm the tag '${APPT_VER}' exists at:" >&2
		echo "  https://github.com/apptainer/apptainer/pkgs/container/apptainer" >&2
		exit 1
	fi
fi

# ----- 5) install the apptainer wrapper --------------------------------------
[ -f "$WRAPPER_SRC" ] || {
	echo "Wrapper template not found at $WRAPPER_SRC" >&2
	exit 1
}
mkdir -p "$BIN_DIR"
cp "$WRAPPER_SRC" "$WRAPPER"
sed -i '' "s|__APPT_VER__|${APPT_VER}|g" "$WRAPPER"
chmod +x "$WRAPPER"
echo "Installed wrapper at $WRAPPER (Apptainer ${APPT_VER})."

# ----- 6) PATH + alias (added once, no duplicate lines) ----------------------
add_line() { grep -qsF "$1" "$2" 2> /dev/null || echo "$1" >> "$2"; }
add_line 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc
add_line 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc
add_line 'alias apptainer="$HOME/.local/bin/apptainer"' ~/.zshrc

cat << EOF

Done. Apptainer ${APPT_VER} is linked at ${WRAPPER}
Open a new terminal (or source run commands), and test:
    apptainer --version

Build a Red Hat / Rocky / Alma image. Example rhel9.def:
	Bootstrap: docker
	From: rockylinux:9
	%post
		dnf -y update && dnf -y install gcc make
Then:
	apptainer build rhel9.sif rhel9.def
EOF
