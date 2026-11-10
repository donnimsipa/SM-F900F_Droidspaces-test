# TODO — SM-F900F Z Fold 1st Gen Custom Kernel Project

## Overview

Phased roadmap from stock kernel → fully customized DroidSpaces kernel for the Galaxy Z Fold 1st gen (SM-F900F, `winnerlte`, SM8150/Snapdragon 855).

---

## Phase 1: Build Stock Kernel First ✅ COMPLETED

Goal: Verify the Z Fold kernel source compiles as-is before making any changes.

### 1.1 Verify Build Environment ✅
- [x] Check `toolchain/llvm-arm-toolchain-ship/10.0/bin/clang` exists ✅ (installed from prebuilt toolchain in toolchain/)
- [x] Check `toolchain/gcc-cfp/gcc-cfp-single/aarch64-linux-android-4.9/bin/aarch64-linux-android-` exists ✅ (symlinked from prebuilt toolchain in toolchain/)
- [x] Check `tools/dtc` exists ✅ (device tree compiler binary available)
- [x] Install missing build dependencies (Ubuntu 20.04 for LLVM 10.0) ✅ (all apt packages installed)
- [x] Python2 symlink ✅ (`ln -sf /usr/bin/python2 /usr/bin/python`)

### 1.2 Build Stock Kernel ✅
- [x] Run `bash build_kernel.sh` ✅ (build completed successfully)
- [x] Verify `out/arch/arm64/boot/Image` is produced ✅ (48MB kernel image at `arch/arm64/boot/Image`)
- [x] If build fails → diagnose: toolchain paths, LLVM version match, defconfig issues ✅ (build succeeded)

### 1.3 Handle Build Errors (if any) ✅
- [x] Build had `__packed` warning in `gsi.c` but completed successfully (genksyms warning only, not fatal)
- [x] Toolchain paths configured correctly via symlinks

### 1.4 (Optional) Verify Stock Kernel Boots
- [ ] If device is available: create `boot.img` from stock `out/arch/arm64/boot/Image`
- [ ] Flash and confirm boot
- [ ] Record `uname -a`, `cat /proc/version`, `cat /proc/cmdline`

---

## Phase 2: Set Up Build System & Configs

Goal: Replace the simple `build_kernel.sh` with a layered `build.sh` that merges `custom.config` + `droidspaces.config` on top of the base defconfig.

### 2.1 Create `custom.config` ✅
- [x] Create `arch/arm64/configs/custom.config` (initially empty) ✅
- [x] Add `.gitignore` additions ✅ (`*.patch`, `*.rej`, `*.orig`, `prebuilts/boot_editor_v15_r1/`)
- [x] Add DTB and build flags ✅ (verified merged via out/.config)
  ```
  CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y
  CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y
  CONFIG_BUILD_ARM64_DT_OVERLAY=y
  CONFIG_IMG_DTB=y
  CONFIG_LOCALVERSION="ZFold-KSUN@donnimsipa"
  CONFIG_LOCALVERSION_AUTO=n
  ```
  Merged output: CONFIG_LOCALVERSION="ZFold-KSUN@donnimsipa", CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y all present in out/.config
- [x] Add Samsung anti-root disables ✅ (grep confirmed 10 options, all disabled in custom.config; verified # CONFIG_UH is not set etc. in out/.config)

### 2.2 Create `droidspaces.config` ✅
- [x] Create `arch/arm64/configs/droidspaces.config` — device-independent LXC networking config (~126 lines) ✅

### 2.3 Copy Build Files ✅
- [x] `build.config.aarch64` — copy ✅
- [x] `build.config.common` — copy ✅
- [x] `AndroidKernel.mk`, `Android.bp` → `Androidbp` ✅
- [x] `disable_dbgfs.sh`, `kernel_headers.py` ✅
- [x] `tools/thermal/tmon/` ✅
- [x] `.gitmodules` — copy ✅
- [x] See project docs for complete list ✅

### 2.4 Create `build.sh` ✅
- [x] Adapt `build.sh` from reference repo — `make ... winnerlte_eur_open_defconfig custom.config droidspaces.config` ✅
- [x] Set `KBUILD_BUILD_USER="@donnimsipa"` ✅
- [x] Add `build_kernel`, `build_boot`, `build_tar` functions ✅
- [x] Support `make menuconfig` when `GITHUB_ACTIONS` is not set ✅

### 2.5 Test the New Build System ✅
- [x] Run `bash build.sh` ✅ — config merge verified
- [x] Verify `out/arch/arm64/boot/Image-dtb` produced ✅ (46MB Image-dtb produced)
- [x] Verify `out/arch/arm64/boot/dts/qcom/*.dtb` contain `winner` trees ✅

---

## Phase 3: Import KernelSU-Next — Root Access

Goal: Add kernel-level root access via KernelSU-Next. **Must complete after Phase 2.**

### 3.1 Add KernelSU-Next Submodule
- [ ] Run:
  ```bash
  curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy
  ```
- [ ] Verify: `drivers/kernelsu/` exists, `drivers/Kconfig` has `source "drivers/kernelsu/Kconfig"`, `drivers/Makefile` has `obj-y += kernelsu/`

### 3.2 Apply `scope_min_manual_hooks_v1.6.patch`
- [ ] Obtain `scope_min_manual_hooks_v1.6.patch` from the KernelSU-Next project
- [ ] Run `git apply --check scope_min_manual_hooks_v1.6.patch` first
- [ ] If clean: `git apply scope_min_manual_hooks_v1.6.patch`
- [ ] If not: manually patch these 14 files (hook functions may differ in Z Fold kernel):
  - `drivers/input/input.c`, `fs/exec.c`, `fs/internal.h`, `fs/namespace.c`, `fs/open.c`, `fs/read_write.c`, `fs/stat.c`, `include/linux/seccomp.h`, `kernel/reboot.c`, `security/selinux/hooks.c`, `security/selinux/include/objsec.h`, `security/selinux/selinuxfs.c`, `security/selinux/xfrm.c`, `.gitignore`

### 3.3 Enable KernelSU in `custom.config`
- [ ] Add to `custom.config`:
  ```
  CONFIG_KSU=y
  CONFIG_KSU_ALLOWLIST_WORKAROUND=y
  CONFIG_KSU_MANUAL_HOOK=y
  ```

### 3.4 Build and Verify
- [ ] Build: `bash build.sh`
- [ ] Verify `drivers/kernelsu/` compiled
- [ ] Verify `CONFIG_KSU=y` in `out/.config`

---

## Phase 4: Apply Kernel Source Fixes

Goal: Resolve compilation and compatibility issues.

### 4.1 GSI genksyms Fix
- [ ] Check `drivers/platform/msm/gsi/gsi.c` for redundant `__packed` attributes:
  ```bash
  grep -n "__packed" drivers/platform/msm/gsi/gsi.c
  ```
- [ ] If present: remove redundant `__packed` (adapt from original GenKSyms fix)
- [ ] Rebuild — verify `genksyms` no longer fails

### 4.2 Cgroup Fix for DroidSpaces
- [ ] Fix `kernel/cgroup/cgroup.c` — restore cgroup file prefix handling 
- [ ] Rebuild

### 4.3 DTB Compilation
- [ ] Wire up DTB compilation so the stock DTB is correctly appended to `Image` (S10: modified `arch/arm64/boot/Makefile`)

---

## Phase 5: Package for Flashing

Goal: Create a bootable Odin-flashable artifact.

### 5.1 Add `boot_editor_v15_r1`
- [ ] Copy from prebuilts/:
  ```bash
  cp -r <path-to-prebuilts>/boot_editor_v15_r1 ./prebuilts/boot_editor_v15_r1
  ```
- [ ] Update `.gitignore` to include `prebuilts/boot_editor_v15_r1/`

### 5.2 Extract Stock `boot.img` for Z Fold
- [ ] Download Z Fold 1st gen (SM-F900F) firmware from Samsung
- [ ] Extract `boot.img` from the AP tarball
- [ ] Place at `prebuilts/boot.img`

### 5.3 Update `build.sh` with Boot/Tar Functions
- [ ] Add `build_boot` function using `boot_editor_v15_r1`:
  ```bash
  cd prebuilts/boot_editor_v15_r1 && ./gradlew pack && mv boot.img.signed build/boot.img
  ```
- [ ] Add `build_tar` function to create `Droidspaces-KSUN-Samsung-SM-F900F.tar`

### 5.4 Test Packaging
- [ ] Run `bash build.sh` — verify all phases complete:
  - `build_kernel` → `build/Image-dtb`
  - `build_boot` → `build/boot.img`
  - `build_tar` → `build/Droidspaces-KSUN-Samsung-SM-F900F.tar`
- [ ] Verify `build/boot.img` boots on device

---

## Phase 6: CI/CD Pipeline

Goal: Automate builds via GitHub Actions.

### 6.1 Create `.github/workflows/build.yml`
- [ ] Create `.github/workflows/build.yml` (CI workflow)
- [ ] Change `runs-on: ubuntu-22.04` → `runs-on: ubuntu-20.04` (LLVM 10.0 glibc compatibility)
- [ ] Change artifact name to `Droidspaces-KSUN-Samsung-SM-F900F`
- [ ] Verify `bash build.sh` works in CI

---

## Phase 7: Verify on Device

Goal: Validate everything on the actual Z Fold 1st gen.

### 7.1 Boot & Basic Functionality
- [ ] Flash `Droidspaces-KSUN-Samsung-SM-F900F.tar` via Odin (AP slot only)
- [ ] Device boots without bootloop
- [ ] `adb shell cat /proc/version` shows `ZFold-KSUN@donnimsipa`
- [ ] Verify normal functionality: camera, sound, USB, Wi-Fi, Bluetooth

### 7.2 Root Verification (KernelSU-Next)
- [ ] Install KernelSU-Next Manager APK on device
- [ ] Manager confirms KernelSU-Next active
- [ ] `adb shell su - id` returns `uid=0`

### 7.3 DroidSpaces Verification
- [ ] Install DroidSpaces app
- [ ] Create and start a container:
  ```bash
  droidspace create test01 && droidspace start test01 && droidspace exec test01 uname -a
  ```
- [ ] Inside container, verify:
  ```bash
  ip addr show              # bridge/veth present
  ls /sys/fs/cgroup/devices # devices cgroup present
  mount | grep overlay      # overlay mount works
  curl https://example.com  # Internet via NAT/bridge
  ```

---

## Phase 8: Maintenance

### 8.1 Upstream Sync
- [ ] When Samsung releases a new kernel dump for SM-F900F, rebase:
  - Import new defconfig and DTS from new dump
  - Keep `custom.config`, `droidspaces.config`, `KernelSU-Next`, `boot_editor_v15_r1` on top
  - Document as `Upstream: [NEW_BUILD_ID]`

### 8.2 Optional Improvements (after Phase 7 stable)
- SUSFS / root hiding mechanisms
- WireGuard kernel backend
- CPU/GPU tuning, scheduler modifications
- Debug feature toggles

---

## Milestones

| # | Milestone | Definition of Done |
|---|-----------|-------------------|
| M1 | Stock kernel builds | `out/arch/arm64/boot/Image` produced |
| M2 | Build system customized | `custom.config` + `droidspaces.config` + new `build.sh` compile |
| M3 | KernelSU-Next integrated | Hooks patched, `CONFIG_KSU=y`, build succeeds |
| M4 | Boot image packaged | `build/Droidspaces-KSUN-Samsung-SM-F900F.tar` produced |
| M5 | Device boots | Odin flash succeeds, `uname` shows custom localversion |
| M6 | Root works | `adb shell su - id` = uid=0 |
| M7 | DroidSpaces works | Containers run, Internet via NAT/bridge |
| M8 | CI/CD automated | GitHub Actions builds and uploads artifact |

---
## How to Use

- Work phases in order — each depends on the previous
- Check off items as completed
- When a phase fails, read the compiler output and see `SKILLS.md` for the corresponding skill
- Keep base kernel files clean — modify `custom.config`/`droidspaces.config`/`build.sh`/KernelSU, not the base defconfig
- **Before Phase 3**, complete Phase 1 and Phase 2 — root requires a working build system first

