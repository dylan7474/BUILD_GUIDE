# Master Development & AI Environment Installer

This repository contains `master_install.sh`, a guided installer for provisioning a
Ubuntu workstation with NVIDIA GPU support for both general development tools and
popular AI creation/serving stacks. The script is intended to be re-runnable and
collects the previously separate setup steps into a single workflow.

## Supported environment

* Ubuntu 22.04 (other releases are untested; the CUDA repository that is
  configured targets 22.04 specifically)
* A system with sudo privileges
* An NVIDIA GPU that supports CUDA 12.5 or later

## What the script does

Running `./master_install.sh` without arguments executes the initial installation
(stage 1). Major tasks include:

1. **Install core packages** – Updates apt metadata and installs compiler
   toolchains, Windows cross-compilation tools, SDL dependencies, Wine, Python,
   Git, and other utilities required by downstream tooling.
2. **Build btop from source** – Clones the upstream `btop` repository, compiles
   it with GPU metrics enabled, and installs it globally.
3. **Install Inform7** – Downloads the 6M62 release, runs the bundled installer,
   and exposes the compiler on `PATH` for interactive fiction development.
4. **Install NVIDIA CUDA Toolkit 12.5** – Adds the NVIDIA apt repository, installs
   the CUDA Toolkit (including drivers when necessary), and registers the CUDA
   binary/library paths system wide.
5. **Install Docker and the NVIDIA Container Toolkit** – Installs Docker Engine,
   adds the current user to the `docker` group, configures the NVIDIA container
   runtime, and restarts the Docker daemon.
6. **Install ComfyUI** – Clones the ComfyUI repository into `~/ai-tools/ComfyUI`,
   sets up a Python virtual environment, installs CUDA-enabled PyTorch and the
   project requirements, and downloads Stable Diffusion XL plus Stable Video
   Diffusion checkpoints.
7. **Install AUTOMATIC1111 Stable Diffusion Web UI** – Clones the repository into
   `~/ai-tools/automatic1111` and creates symbolic links to the shared
   checkpoint downloads.
8. **Install and configure Ollama** – Installs Ollama if missing, updates its
   systemd unit to wait for NVIDIA drivers, enables `nvidia-persistenced`, and
   stops the service pending a reboot.
9. **Create launcher scripts** – Generates `~/start_automatic1111.sh` and
   `~/start_comfyui.sh` helper scripts to simplify launching the installed UIs.
10. **Prompt for reboot** – Reminds the user to reboot and rerun the script with
    the `post-reboot` argument for final setup.

Stage 2 is triggered with `./master_install.sh post-reboot`. It performs the
post-install tasks:

* Pulls the latest `ghcr.io/open-webui/open-webui:main` container image.
* Removes any pre-existing `open-webui` container.
* Starts Open WebUI bound to the host network with GPU access, persisting its
  data volume, and prints the URL for access.
* Reiterates the availability of the launcher scripts created during stage 1.

### Uninstallation

Run `./master_install.sh uninstall` to remove the AI tooling directory
(`~/ai-tools`) and optionally delete the launcher scripts.

## Usage

```bash
chmod +x master_install.sh
./master_install.sh          # Stage 1 (initial installation)
# Reboot when prompted
./master_install.sh post-reboot   # Stage 2 (start Open WebUI)
./master_install.sh uninstall     # Remove AI tooling and launchers
```

Because several steps modify system packages and services, the script will prompt
for your sudo password. Some stages involve large downloads (CUDA, model
checkpoints), so ensure you have a stable Internet connection and adequate disk
space before beginning.

## Development-only installer

If you only need a lightweight development environment without NVIDIA GPU
tooling or Stable Diffusion components, run the companion script
`dev_install.sh`. It provisions the same core development dependencies and
configures Docker, Ollama, and Open WebUI so you can start experimenting with
local models quickly.

```bash
chmod +x dev_install.sh
./dev_install.sh
```

During execution the script installs build toolchains, SDL libraries, Wine,
Inform7, and btop; sets up Docker; installs Ollama; and launches Open WebUI in a
Docker container bound to `http://localhost:8080`.

## Suggested improvements and future enhancements

* **OS and hardware validation** – Detect unsupported Ubuntu versions or missing
  NVIDIA hardware early and provide actionable messages (for example, fail fast
  if `lsb_release -rs` is not 22.04 or if `nvidia-smi` is absent).
* **Configurable feature sets** – Allow users to toggle optional components
  (e.g., skip Inform7, choose which AI UIs or models to install) via command-line
  flags or an interactive menu.
* **Download management** – Verify checksums for model downloads, support
  resumable transfers, and optionally seed local model caches instead of
  downloading every run.
* **Logging and verbosity controls** – Emit logs to a file and expose quiet or
  verbose modes to simplify troubleshooting.
* **Service health checks** – After the post-reboot phase, automatically test the
  Open WebUI endpoint and provide diagnostic output if the container is not
  responding.
* **Resource prerequisites** – Check for free disk space, GPU driver versions,
  and available VRAM before installation to avoid mid-process failures.
* **Automated updates** – Provide a subcommand that updates each installed
  component (git pull, pip upgrade, docker image refresh) without rerunning the
  entire setup.

These refinements would make the installer more resilient, customizable, and
maintainable for a wider range of development environments.
