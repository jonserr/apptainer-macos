# apptainer-macos

Run [Apptainer](https://apptainer.org/) on macOS with one command.

Apptainer is Linux-only, so on a Mac it has to run inside a Linux container.
This installer wires up Docker Desktop as that Linux VM and drops a small
`apptainer` wrapper into `~/.local/bin` that transparently runs the official
[Apptainer container](https://github.com/apptainer/apptainer/pkgs/container/apptainer).
After install you just type `apptainer ...` like you would on Linux.

## What it does

- Installs [Homebrew](https://brew.sh/) if it's missing.
- Installs `qemu` and `lima` (handy if you'd rather run a native Lima VM).
- Installs Docker Desktop (the daemon that provides the Linux VM) and starts it.
- Pulls the pinned Apptainer image.
- Installs `bin/apptainer` to `~/.local/bin/apptainer` and adds it to your `PATH`.

If `apptainer --version` already works the script exits immediately.

## Install

```bash
git clone https://github.com/jonserr/apptainer-macos.git
cd apptainer-macos
./install.sh
```

Then open a new terminal (or `source ~/.zshrc`) and test:

```bash
apptainer --version
```

> You may be asked for your admin password (Homebrew + Docker Desktop first run)

## Usage

Build a Red Hat / Rocky / Alma image. Example `rhel9.def`:

```
Bootstrap: docker
From: rockylinux:9
%post
    dnf -y update && dnf -y install gcc make
```

Then:

```bash
apptainer build rhel9.sif rhel9.def
apptainer run rhel9.sif
```

## Config

The Apptainer version is pinned in `install.sh`:

```bash
APPT_VER="1.5.1"
```

Change it and re-run `./install.sh` to upgrade. See available tags [here](https://github.com/apptainer/apptainer/pkgs/container/apptainer).

## How it works

`bin/apptainer` is a thin wrapper around:

```bash
docker run --rm -it --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD":"$PWD" -w "$PWD" \
  --entrypoint apptainer \
  ghcr.io/apptainer/apptainer:<version> "$@"
```

Mounts your current directory at the same path inside the container so host
paths Apptainer binds resolve correctly, and runs `--privileged` so image builds
work. The installer copies this template and substitutes the pinned version.

### License - MIT
