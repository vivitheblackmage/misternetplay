# Quartus in Docker

The NES core is built with Quartus Prime Lite **17.0.2**, the version MiSTer
cores use, in a Docker image. On Windows everything runs inside **WSL2
(Ubuntu)**: the work folder, `make`, Verilator and the `docker` command;
Windows only runs Docker Desktop.

## Once

1. **Linux.** Ubuntu 24.04 (on Windows: PowerShell as administrator,
   `wsl --install -d Ubuntu`, restart, open "Ubuntu" and create a user).
2. **Docker.** On Windows: Docker Desktop with the WSL2 backend, and
   *Settings → Resources → WSL integration → Ubuntu* switched on. Give Docker at
   least 8 GB of memory and 30 GB of disk (*Resources → Advanced*).
   Check: `docker run --rm hello-world`.
3. **Tools:** `sudo apt update && sudo apt install -y git make g++ verilator python3`
   (Ubuntu 24.04 has Verilator 5, which the testbench needs).
4. **Keep the work folder in the Linux file system**, e.g. `~/netplay`, not
   under `/mnt/c/`. Over `/mnt/c` the Quartus build is many times slower.
5. **Get the image**, one of:
   - **The MiSTer community's image** (no Intel account, ~11 GB, third party; the
     one MiSTer-devel uses in its CI):
     ```bash
     docker pull theypsilon/quartus-lite-c5:17.0.2.docker0
     docker build -t mister-quartus17 - <<'EOF'
     FROM theypsilon/quartus-lite-c5:17.0.2.docker0
     ENV PATH=/opt/intelFPGA_lite/quartus/bin:$PATH
     WORKDIR /build
     EOF
     docker run --rm mister-quartus17 quartus_sh --version   # 17.0.2 Build 602 Lite
     ```
   - **Your own, from Intel's installer.** From Intel's FPGA Software Download
     Center: Quartus Prime **Lite** **17.0.2**, Linux, *Combined Files*:
     `Quartus-lite-17.0.2.602-linux.tar` (about 6 GB). Put it in this folder
     (`tools/quartus-docker/`; it is not checked in) and build the image
     (20–40 min, once):
     ```bash
     docker build -t mister-quartus17 tools/quartus-docker
     ```
     If it stops during the installation, Intel has changed the installer's
     questions; `install_quartus.exp` is the script that answers them. You can
     delete the tar file afterwards.

## Each build

```bash
tools/quartus_build.sh            # 10-30 min
tools/quartus_build.sh --timing   # only check the timing of the last build
```

Done when the script prints `TIMING OK`. The core is in
`NES_MiSTer/output_files/NES.rbf`, where `tools/deploy.sh` and
`tools/make_release.sh` look for it. Log: `NES_MiSTer/output_files/quartus.log`.

## Main_MiSTer (ARM): no Docker needed

In `Main_MiSTer/`:
```bash
source setup_default_toolchain.sh   # downloads ARM gcc 10.2 the first time
make
```
