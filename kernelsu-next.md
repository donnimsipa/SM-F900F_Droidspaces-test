# KernelSU-Next in the Droidspaces Kernel — How It Works

This document describes how KernelSU-Next is integrated in this repository, why the
pieces are arranged the way they are, and how to replicate the same setup for a
different kernel. It is based on what actually happened while bringing the
GitHub Actions build back to green (run `43252365373`, commit `49e1baec4`).

> **Coming here because a build failed?** Read **Section 9 — Post-mortem: why the old
> builds failed (and how the fix works)** — it explains every failure signature in the
> old logs and which change killed it.

---

## 1. The repository at a glance

| Item | Value |
|---|---|
| Repo | `SM-F900F_Droidspaces` (fork remote: `github.com/donnimsipa/SM-F900F_Droidspaces-test`, branch `main`) |
| Device target | Samsung Galaxy Z Fold 1st Gen (SM-F900F), `winnerlte`, base defconfig `winnerlte_eur_open_defconfig` |
| Linux version | 4.14.190 (arm64) |
| KernelSU-Next | git submodule, pinned at `a54e4fa4` (tag-14 → `v3.2.0-legacy-14-ga54e4fa4`) |
| Build system | `build.sh` + `.github/workflows/build.yml` (GitHub Actions, `workflow_dispatch`) |
| Release output | `build/boot.img` → tar → `build/Droidspaces-KSUN-Samsung-SM-F900F.tar` |

---

## 2. What KernelSU-Next is, mechanically, inside a kernel tree

Inside a kernel, KernelSU-Next lives at `drivers/kernelsu/` and is compiled in with:

- `drivers/Makefile:247` → `obj-$(CONFIG_KSU) += kernelsu/`
- `drivers/Kconfig:268` → `source "drivers/kernelsu/Kconfig"`

Both lines were added by the KernelSU `setup.sh` (or manually) and are committed to
this tree. The source itself is **not** vendored by this repo — it is a submodule.

Submodule wiring (`.gitmodules`):

```ini
[submodule "KernelSU-Next"]
	path = KernelSU-Next
	url = https://github.com/KernelSU-Next/KernelSU-Next.git
	branch = legacy
```

The submodule is checked out at `a54e4fa4` (`v3.2.0-legacy-14-ga54e4fa4`), i.e. the
`legacy` branch tip used by `build.sh`. The repo root tracks that exact commit in its
index; `git submodule update --init --recursive` in CI reproduces it byte-for-byte.

---

## 3. How the build wires KernelSU-Next (the important part)

### The wrong way that broke CI

The original script did:

```bash
cp -r "${KERNEL_ROOT}/KernelSU-Next/kernel" "${KERNEL_ROOT}/drivers/kernelsu"
```

That copy had no `.git`, so KernelSU-Next's `Kbuild` could not compute its own
version and printed the fallback lines that *looked* like the build was broken:

```
../drivers/kernelsu/Kbuild:96: "KSU_GIT_VERSION not defined! It is better to make KernelSU-Next a git repository!"
../drivers/kernelsu/Kbuild:107: "KSU_VERSION_TAG not defined! It is better to make KernelSU-Next a git submodule!"
-- KernelSU-Next version fallback: 1
-- KernelSU-Next tag fallback: v0.0.1
```

Worse, the compile died later with:

```
../drivers/kernelsu/policy/app_profile.h:4:10: fatal error: 'uapi/app_profile.h' file not found
```

because `/kernel/include/uapi` in the submodule is a **git symlink**
(`kernel/include/uapi -> ../../uapi`). The target only resolves if `drivers/kernelsu`
is itself a symlink back into the submodule. `cp -r` broke that chain.

### The way it works now (`build.sh`)

```bash
# 1) Remove anything stale
if [ -L "${KERNEL_ROOT}/drivers/kernelsu" ] || [ -d "${KERNEL_ROOT}/drivers/kernelsu" ]; then
    rm -rf "${KERNEL_ROOT}/drivers/kernelsu"
fi

# 2) Use a symlink, not a copy
if [ -d "${KERNEL_ROOT}/KernelSU-Next/kernel" ]; then
    ln -sfn "${KERNEL_ROOT}/KernelSU-Next/kernel" "${KERNEL_ROOT}/drivers/kernelsu"
fi

# 3) Pin the tag exactly
KSU_VERSION_TAG="$(git -C "${KERNEL_ROOT}/KernelSU-Next" describe --tags --abbrev=0)"
KSU_VERSION_ARGS=(KSU_VERSION_TAG="${KSU_VERSION_TAG}" KSU_GIT_TAG="${KSU_VERSION_TAG}")
```

Every `make` invocation (defconfig, `oldconfig`, `menuconfig`, the final build) passes
`"${KSU_VERSION_ARGS[@]}"` on the command line, which beats Kbuild's git fallback.

### How `Kbuild` computes the version (for reference)

From `KernelSU-Next/kernel/Kbuild`:

```make
GIT_ROOT := $(shell cd $(MDIR) && git rev-parse --show-toplevel)
KERNEL_GIT_ROOT := $(shell cd $(srctree) && git rev-parse --show-toplevel)
ifneq ($(GIT_ROOT),$(KERNEL_GIT_ROOT))
KSU_GIT_VERSION := $(shell git rev-list --count HEAD)
KSU_GIT_TAG     := $(shell git describe --tags --abbrev=0)
KSU_VERSION     = 30000 + $(KSU_GIT_VERSION) + 200
```

Current values in CI:

```
-- KernelSU-Next Git repo detected at: .../KernelSU-Next
-- KernelSU-Next version: 33193
-- KernelSU-Next tag: v3.2.0-legacy
```

The numeric `KSU_VERSION` is formula-based (`30000 + commits + 200`) and is **not**
pinned. The tag is exactly the repo tag (`v3.2.0-legacy`), which was the requirement.

Also important: `KSU_GIT_VERSION` is derived from `git rev-list --count HEAD`, i.e.
the number of commits since the repository root. The CI checkout therefore uses
`fetch-depth: 0` — a shallow checkout would produce `KSU_VERSION = 30201` and mismatch.

---

## 4. Configuration (in priority order applied by `make`)

1. `winnerlte_eur_open_defconfig` — base 4.14.190 config. Notably **no** `CONFIG_KPROBES`.
2. `custom.config` — Samsung/OEM anti-root disabled, DTB settings, and KernelSU bits:
   ```
   # disable Samsung anti-root / security features
   CONFIG_UH=n
   CONFIG_UH_RKP=n
   CONFIG_UH_LKMAUTH=n
   CONFIG_UH_LKM_BLOCK=n
   CONFIG_RKP_CFP=n
   CONFIG_RKP_CFP_JOPP=n
   CONFIG_RKP_CFP_ROPP=n
   CONFIG_FIVE=n
   CONFIG_SECURITY_DEFEX=n
   CONFIG_PROCA=n

   # device DTB
   CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y
   CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y
   CONFIG_BUILD_ARM64_DT_OVERLAY=y
   CONFIG_IMG_DTB=y
   CONFIG_LOCALVERSION="ZFold-KSUN@donnimsipa"
   CONFIG_LOCALVERSION_AUTO=n

   # KernelSU-Next
   CONFIG_KSU=y
   CONFIG_KSU_ALLOWLIST_WORKAROUND=y
   CONFIG_KSU_MANUAL_HOOK=y
   ```
3. `droidspaces.config` — namespaces, IPC, seccomp + filter, cgroups (pids, cpuset,
   cpuacct, sched, device, freezer, net_prio), `user_namespaces`, overlayfs,
   tmpfs ACL/xattr, bridge/veth/MASQUERADE, IPv6 NAT, `CONFIG_NETFILTER_XT_*` for
   UFW/fail2ban, `CONFIG_IP_SET`, etc. This is what makes the kernel usable for
   containers (Droidspaces use cases).

### Hook mode: why `MANUAL_HOOK`

`KSU_KPROBES_HOOK` requires `KRETPROBES && KPROBES && HAVE_SYSCALL_TRACEPOINTS`.
The Samsung 4.14 defconfig disables kprobes, so this kernel uses **manual hooks**.

Manual hook is satisfied by `kernel/reboot.c`, which the kernel source carries:

```c
/* kernel source, NOT the submodule */
__weak int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd,
				     void __user **arg)
{
	return 0;
}
...
#ifdef CONFIG_KSU
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);
#endif

SYSCALL_DEFINE4(reboot, ...)
{
#ifdef CONFIG_KSU
	ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);
#endif
	...
}
```

KernelSU-Next's `Kbuild` verifies the hook exists:

```make
ifeq ($(CONFIG_KSU_MANUAL_HOOK), y)
HAVE_KSU_HOOK := $(shell grep -q "ksu_handle_sys_reboot" $(srctree)/kernel/reboot.c && echo 0 || echo 1)
endif

ifneq ($(HAVE_KSU_HOOK),0)
$(error -- KernelSU-Next: No hooks were defined, please integrate manual hooks in your kernel!)
endif
```

**The `ksu_handle_sys_reboot` definition is in the kernel tree itself, not in the submodule.**
That is what you add when porting to another kernel. Without it, manual-hook builds fail
at `Kbuild` time with `No hooks were defined`.

---

## 5. CI flow (`.github/workflows/build.yml`)

1. `workflow_dispatch` (optional `tag` input; empty → `vYYYYMMDDHHMM`).
2. `runs-on: ubuntu-22.04`, `permissions: contents: write`.
3. `actions/checkout@v5` with **`submodules: recursive`** and **`fetch-depth: 0`**
   (needed for `git rev-list --count` and `git describe --tags`).
4. Dependencies: git, DTC, lz4, xz-utils, zlib1g-dev, openjdk-17, gcc/g++, python2
   (aliased to `python`), p7zip, android-sdk-libsparse-utils, erofs-utils, default-jdk,
   gnupg, libncurses5.
5. `bash build.sh` → produces `build/Image-dtb`, then magiskboot repack → `build/boot.img`,
   then `build/Droidspaces-KSUN-Samsung-SM-F900F.tar`.
6. `actions/upload-artifact@v4` uploads the tar (build marked green; Node.js 20 deprecation
   annotation, non-fatal).
7. `ncipollo/release-action@v1` publishes a release tagged with `RELEASE_TAG`
   (auto-generated if input empty) with the tar attached.

Verified green: run `43252365373` → release `Kernel Release v202611121553`.

---

## 6. Local vs CI differences

| Aspect | Local (laptop) | CI (GitHub Actions) |
|---|---|---|
| `menuconfig` | opens (interactive) | skipped (`GITHUB_ACTIONS` is set) |
| `drivers/kernelsu` symlink | macOS may refuse with `Operation not permitted` on some volumes | OK (workspace is writable) |
| `grep -P` | BSD grep lacks `-P` — **don't use `-P`** (the old `setup.sh` had this bug; fixed to `grep -E`) | GNU grep fine |
| `realpath --relative-to` | BSD `realpath` lacks the option (fixed) | GNU fine |
| Network | may need proxy | runner has direct egress |
| `yes ""` around `make` | harmless | required (no TTY for oldconfig prompts) |

Note: `KernelSU-Next/kernel/setup.sh` in the submodule was adjusted locally for BSD
portability; it is a submodule file and **cannot be pushed to the upstream repo** from
here. It is irrelevant for CI (which uses `build.sh`). It only helps on macOS.

---

## 7. Replicating this setup for another kernel

### Step 1 — prerequisites in the target kernel

- An in-tree `drivers/Kconfig` and `drivers/Makefile` that can adapt
  (`source "drivers/kernelsu/Kconfig"` / `obj-$(CONFIG_KSU) += kernelsu/`).
- Out-of-tree build support (`make O=out …`), or adapt paths accordingly.
- A way to build the `boot.img` (this repo uses a local `prebuilts/magiskboot` with
  `boot.img` and a repack flow).
- If the kernel has `CONFIG_KPROBES` working, you can opt for Kprobes hook mode
  instead of manual hooks (see Step 4).

### Step 2 — add the submodule

```bash
cd <kernel-root>
git submodule add -b legacy https://github.com/KernelSU-Next/KernelSU-Next.git KernelSU-Next
git config -f .gitmodules submodule.KernelSU-Next.branch legacy
```

### Step 3 — wire `drivers/kernelsu` with a symlink (not a copy)

```bash
ln -sfn "<kernel-root>/KernelSU-Next/kernel" "<kernel-root>/drivers/kernelsu"
grep -q kernelsu "$DRIVER_MAKEFILE" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$DRIVER_MAKEFILE"
grep -q 'source "drivers/kernelsu/Kconfig"' "$DRIVER_KCONFIG" \
  || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "$DRIVER_KCONFIG"
```

### Step 4 — choose the hook mode

**Option A — Manual hooks (used here):** add `ksu_handle_sys_reboot` (weak function)
and the `#ifdef CONFIG_KSU` call inside `kernel/reboot.c` — see section 4 of this doc.
Then in your defconfig/fragment: `CONFIG_KSU_MANUAL_HOOK=y`.

**Option B — Kprobes hooks:** enable `CONFIG_KPROBES=y`, `CONFIG_KRETPROBES=y` and
(if on ≥ 5.3 or older kernels with syscall tracepoints) `HAVE_SYSCALL_TRACEPOINTS=y`;
do **not** set `CONFIG_KSU_MANUAL_HOOK`. KernelSU-Next then defaults
`KSU_KPROBES_HOOK=y`.

### Step 5 — defconfig fragment

Create a fragment like `custom.config` with:

```
CONFIG_KSU=y
CONFIG_KSU_ALLOWLIST_WORKAROUND=y
# CONFIG_KSU_MANUAL_HOOK=y   (or not, if Kprobes mode)
# disable OEM anti-root / anti-su here (Samsung: UH*, RKP*, PROCA, DEFEX, FIVE)
```

and an additional fragment for your runtime (namespaces, seccomp, cgroups, iptables/…)
like this repo's `droidspaces.config`.

### Step 6 — `build.sh` essentials (copy and adapt)

- `git submodule update --init --recursive`
- symlink wiring (Section 3)
- `KSU_VERSION_TAG="$(git -C KernelSU-Next describe --tags --abbrev=0)"` and export it to
  `make` as `KSU_VERSION_TAG=… KSU_GIT_TAG=…`
- base defconfig + fragments, then `yes "" | make … oldconfig`
- non-interactive: gate `menuconfig` behind `[ -z "$GITHUB_ACTIONS" ]`

### Step 7 — GitHub Actions (adapt `.github/workflows/build.yml`)

Minimum working recipe:

```yaml
- uses: actions/checkout@v5        # or v5+, with:
  with:
    submodules: recursive
    fetch-depth: 0                  # REQUIRED for KSU version detection
- run: |
    sudo apt update
    sudo apt install -y git device-tree-compiler lz4 xz-utils zlib1g-dev \
      openjdk-17-jdk gcc g++ python2 p7zip-full android-sdk-libsparse-utils \
      erofs-utils default-jdk gnupg libncurses5
    sudo ln -sf /usr/bin/python2 /usr/bin/python
- run: bash build.sh
- uses: actions/upload-artifact@v4
  with:
    name: <your-artifact-name>
    path: build/<your-artifact>.tar
```

If it must match this repo exactly, copy `.github/workflows/build.yml`, `build.sh`,
`arch/arm64/configs/custom.config`, `arch/arm64/configs/droidspaces.config` and adjust
paths, the magiskboot/boot-repack part, the defconfig names, and the release action.

### Step 8 — verify after build (do this, don't trust the exit code)

```bash
gh run view --log <run-id> | grep -E "KernelSU-Next|drivers/kernelsu wired"
```

Expected (success):

```
[INFO]: drivers/kernelsu wired from KernelSU-Next
[INFO]: KernelSU-Next tag: v3.2.0-legacy
-- KernelSU-Next Git repo detected at: .../KernelSU-Next
-- KernelSU-Next version: 33193          # may vary, depends on git count
-- KernelSU-Next tag: v3.2.0-legacy
-- KernelSU-Next: Hook mode: Manual       # or Kprobes
```

Failure signatures and what they mean:

| Log line | Meaning |
|---|---|
| `KSU_GIT_VERSION not defined!` / `tag fallback: v0.0.1` | `drivers/kernelsu` lost its git context (copied, or shallow CI checkout). Wire as symlink and use `fetch-depth: 0`. |
| `drivers/kernelsu/policy/app_profile.h: fatal error: 'uapi/…'` | Same root cause; the `include/uapi -> ../../uapi` symlink chain is broken by a copy. |
| `No hooks were defined, please integrate manual hooks` | `KSU_MANUAL_HOOK=y` but `kernel/reboot.c` has no `ksu_handle_sys_reboot`, or `KSU_KPROBES_HOOK` deps (`KPROBES`/`KRETPROBES`) unmet. |
| `KSU_NEXT_MANAGER_HASH` mismatch at runtime | Runtime manager APK differs from `KSU_NEXT_MANAGER_HASH` in Kbuild — update the constant in the submodule or build with the expected manager APK. |
| `make: secgetspf: No such file or directory` | Samsung toolchain's `secgetspf` not found; harmless warning in this repo's CI. |
| Release step fails on empty tag | Leave `tag` input empty (auto-generate) or pass `workflow_run` as shown in Section 5. |

### Step 9 — release

`ncipollo/release-action@v1` publishes automatically on success. Leave `tag` blank for a
timestamp tag, or dispatch with a chosen tag:

```bash
gh workflow run "Build Kernel" -f tag=r2
```

---

## 8. What this repo specifically has (checklist to reproduce)

- [x] `KernelSU-Next` as git submodule on `legacy`, pinned at `a54e4fa4` / `v3.2.0-legacy-14`
- [x] `drivers/Makefile` → `obj-$(CONFIG_KSU) += kernelsu/`
- [x] `drivers/Kconfig` → `source "drivers/kernelsu/Kconfig"`
- [x] `kernel/reboot.c` → weak `ksu_handle_sys_reboot` + `#ifdef CONFIG_KSU` call
- [x] `arch/arm64/configs/custom.config` → disable OEM anti-root + `CONFIG_KSU=y`
- [x] `arch/arm64/configs/droidspaces.config` → container/runtime support
- [x] `build.sh` → submodule wiring, `KSU_VERSION_TAG` pin, `yes "" | make oldconfig`
- [x] `.github/workflows/build.yml` → `fetch-depth: 0`, submodule recursive, release publish
- [x] Local scripts made BSD/macOS safe (`grep -E`, no `realpath --relative-to`, absolute symlink path)
- [x] Proven green: run `43252365373`, release `v202611121553`

---

## 9. Post-mortem: why the old builds failed (and how the fix works)

This section documents every error signature that was hit while bringing CI to green —
where it came from, why it appeared, and which specific change killed it.

### 9.1 The symptoms

**On the Mac (running `setup.sh` directly from upstream):**

```
[+] Setting up KernelSU-Next...
[+] Repository cloned.
No local changes to save
[-] Stashed current changes.
grep: invalid option -- P
usage: grep [-abcdDEFGHhIiJLlMmnOopqRSsUVvwXxZz] [-A num] [-B num] ...
remote: Enumerating objects: 316, done.          <- fetch still ran
...
Switched to a new branch 'legacy'
[-] Checked out legacy.
realpath: illegal option -- -
usage: realpath [-q] [path ...]
ln: kernelsu/.: Operation not permitted
[+] Modified Makefile.          <- Makefile/Kconfig sed edits still ran
[+] Modified Kconfig.
[+] Done.
```

What those local lines mean: `git status | grep -P` failed (BSD grep has no `-P`), the
`git pull` had nothing to fast-forward but didn't abort the script, `realpath` had no
`--relative-to` option, and `ln` could not create the symlink on the `/Volumes` mount.
The final sed edits to `drivers/Makefile` and `drivers/Kconfig` still succeeded, which is
why the local tree ended "half wired" — the symlink itself was missing locally, but that
never mattered: CI uses `build.sh`, not this script.

**In GitHub Actions (job `Build Kernel`, step "Build Kernel", run 42941869037):**

```
[INFO]: drivers/kernelsu wired from KernelSU-Next
../drivers/kernelsu/Kbuild:96: "KSU_GIT_VERSION not defined! It is better to make KernelSU-Next a git repository!"
../drivers/kernelsu/Kbuild:107: "KSU_VERSION_TAG not defined! It is better to make KernelSU-Next a git submodule!"
-- KernelSU-Next version fallback: 1
-- KernelSU-Next tag fallback: v0.0.1                          <- appears twice (defconfig step and full build)
-- KernelSU-Next Manager signature size: 0x3e6
-- KernelSU-Next Manager signature hash: 79e590113c4c4c0c222978e413a5faa801666957b1212a328e46c00c69821bf7
-- KernelSU-Next: Hook mode: Manual
../drivers/kernelsu/policy/app_profile.h:4:10: fatal error: 'uapi/app_profile.h' file not found
make[3]: *** [../scripts/Makefile.build:361: drivers/kernelsu/core/init.o] Error 1
make: *** [Makefile:146: sub-make] Error 2
##[error]Process completed with exit code 1.
(yes: standard output: Broken pipe             ← harmless)
make[1]: secgetspf: No such file or directory  ← harmless Samsung toolchain lookup
cp: cannot stat '../../../system/core/liblog/include/log/perflog.h'   ← harmless Samsung include fallback
```

**Related runs:** 42940971197 (4m09s) — same root cause.  42941869037 (10m07s) — same.
The fixed run is 43252365373 (~9 min, success). At a glance these all produced the same
"version fallback" banner; the fatal difference was the missing `uapi` include.

### 9.2 The five root causes (and exactly why each appears)

1. **`drivers/kernelsu` was a *copy*, not a symlink** *(main cause)*.
   `build.sh` did `cp -r KernelSU-Next/kernel drivers/kernelsu`.
   KernelSU-Next's `Kbuild` detects its own git root with:

   ```make
   GIT_ROOT := $(shell cd $(MDIR) && git rev-parse --show-toplevel)   # = kernel root after copy
   KERNEL_GIT_ROOT := $(shell cd $(srctree) && git rev-parse --show-toplevel)
   ifneq ($(GIT_ROOT),$(KERNEL_GIT_ROOT))   # skipped — they are equal
   ```

   The `git rev-list --count HEAD` never ran, so `KSU_VERSION` and `KSU_VERSION_TAG`
   were never defined → the `:96` / `:107` warnings and the `v0.0.1`/`version 1` fallbacks.
   These are **non-fatal warnings** — the build continued, which is why this looked like
   "just a version issue" but hid a fatal error further down.

2. **The `include/uapi` symlink broke under `cp -r`** *(the actual compile killer)*.
   `kernel/include/uapi` in the submodule is a **git symlink → `../../uapi`**
   (repo-root `uapi/`). With a real directory copy the containing path becomes
   `drivers/kernelsu/include/` and `../../uapi` resolves to `drivers/uapi`, which does not
   exist → `policy/app_profile.h:4:10: fatal error: 'uapi/app_profile.h'`.
   With `drivers/kernelsu -> KernelSU-Next/kernel` the kernel resolves the chain through
   the symlink and lands on `KernelSU-Next/uapi/app_profile.h`. Same content, different path.

3. **Shallow CI checkouts mis-compute the version.**
   `actions/checkout` defaults to `fetch-depth: 1`, so `git rev-list --count HEAD` = 1
   and `KSU_VERSION` would be `30201` — wrong but plausible-looking. The fix
   (`fetch-depth: 0`) gives the true count (→ `33193` here) and makes
   `git describe --tags --abbrev=0` see `v3.2.0-legacy`.

4. **The `Makefile:146: sub-make` error is only the messenger.**
   The parent `make` fails because the `drivers/kernelsu/*.o` sub-make failed.
   And in this repo the *fatal* sub-make failure was the missing `uapi` header, not a
   KernelSU version mismatch. The version fallback banner was a red herring.

5. **Local-machine BSD/macOS incompatibilities** *(not part of CI, but same script lineage)*.
   - `grep -P` (Perl regex) → BSD `grep` on macOS has no `-P` → script continued but
     silently skipped the `v*tag*` branch detection.
   - `realpath --relative-to=…` → BSD `realpath` only has `-q`; GNU coreutils option.
   - `ln: kernelsu/.: Operation not permitted` → creating a symlink inside `drivers/`
     on this particular volume is not permitted locally. In CI `ubuntu-22.04` workspaces
     are writable, so the symlink approach works fine there.

### 9.3 What the older "ci:" commits were actually fixing, and why they didn't cure the CI red

The repository already had a chain of CI fixes before this one:

```
1742d463e ci: wire KernelSU-Next submodule into drivers/kernelsu for build
172cbb283 ci: fix KernelSU-Next submodule wiring for drivers/kernelsu
166c3b7ba ci: clone KernelSU-Next directly when submodule is empty
f9631ffed ci: set KERNEL_ROOT before submodule/KernelSU setup
b1d4f42ef ci: add olddefconfig to resolve new symbols non-interactively
dcb1df44c ci: pipe yes to oldconfig for non-interactive CI
c284ad78b ci: touch auto.conf after olddefconfig to prevent re-run
111751931 ci: pipe yes to both oldconfig and build make for non-interactive CI
acacaf89c revert: keep SCHED_WALT=y to avoid scheduler build error
```

These attacks the **interactivity** axis only (oldconfig prompts would otherwise hang CI)
and early **submodule plumbing**. None of them restored git context to `drivers/kernelsu`,
so all of them ran into the same twin failures (2 + 1 in §9.2). The build *reached* the
compile phase (Net/wireless modules were compiling) before dying on `uapi/app_profile.h`.

### 9.4 The fix that actually cured it (commit `49e1baec4`)

| # | Change | Where | Root cause killed |
|---|---|---|---|
| 1 | `rm -rf` stale `drivers/kernelsu` before wiring | `build.sh` | keeps CI idempotent |
| 2 | `ln -sfn KernelSU-Next/kernel drivers/kernelsu` instead of copying | `build.sh` | §9.2 #1 and #2 (git context + `include/uapi` chain) |
| 3 | `fetch-depth: 0` for both repo and submodule | `.github/workflows/build.yml` | §9.2 #3 |
| 4 | Pass `KSU_VERSION_TAG=v3.2.0-legacy` and `KSU_GIT_TAG=v3.2.0-legacy` on every `make` command line — wins over Kbuild's makefile eval | `build.sh` | belt-and-braces: even if the symlink path fails and it falls back, tag/version still resolve correctly |
| 5 | macOS `grep -P` → `grep -E`; drop GNU-only `realpath --relative-to` | `KernelSU-Next/kernel/setup.sh` (local) | §9.2 #5 (local only) |

Expected log from a healthy build (as in run `43252365373`):

```
[INFO]: drivers/kernelsu wired from KernelSU-Next
[INFO]: KernelSU-Next tag: v3.2.0-legacy
-- KernelSU-Next Git repo detected at: .../KernelSU-Next
-- KernelSU-Next version: 33193
-- KernelSU-Next tag: v3.2.0-legacy          <- exact repo tag, no v0.0.1 fallback
-- KernelSU-Next: Hook mode: Manual
```

### 9.5 How to solve it, in order of likelihood

1. **Is the build dying at `policy/app_profile.h: … uapi/app_profile.h`?** →
   you have a `cp -r` somewhere over the submodule path. Replace with a symlink to
   `KernelSU-Next/kernel` and delete the stale directory before wiring (§9.4 #1–#2).

2. **Are warnings `KSU_GIT_VERSION not defined` / `v0.0.1` still present but the build
   actually compiles?** → the copy path is still somehow in use, or a stale `out/`
   directory is being reused. Remove `out/`, re-run, confirm wiring log line appears.
   If it persists and the symlink exists, pass `KSU_VERSION_TAG` explicitly as in §9.4 #4.

3. **Is `KSU_VERSION = 30201` (or otherwise implausibly small) in the log?** → shallow
   checkout. Set `fetch-depth: 0` on the `actions/checkout` step.

4. **`No hooks were defined, please integrate manual hooks in your kernel!`** →
   `CONFIG_KSU_MANUAL_HOOK=y` but `kernel/reboot.c` lacks `ksu_handle_sys_reboot`
   (or the `#ifdef CONFIG_KSU` call site). Copy the hook from this repo's `kernel/reboot.c`,
   or enable `KPROBES`/`KRETPROBES` + `KSU_KPROBES_HOOK` instead.

5. **Local macOS run fails at `ln -sf` into `drivers/`** → not a CI concern; the volume
   or SIP blocks symlinks there. `build.sh` already creates the symlink itself; do not
   create it manually, and note the local submodule `setup.sh` fix lives in the submodule,
   not the parent repo, and cannot be pushed to upstream.

6. **Release step fails on tags** → leave the `tag` input empty (auto `vYYYYMMDDHHMM`),
   or dispatch with `-f tag=<name>`. Artifact: `build/Droidspaces-KSUN-Samsung-SM-F900F.tar`.

### 9.6 Timeline of the failures

| Run | Duration | Date | Outcome |
|---|---|---|---|
| 42940971197 | 4m09s | 2026-11-11 | `failure` — same root cause (missing `.git` in copy / uapi symlink broken); died earlier because oldconfig interactivity and git plumbing were the assumed blocker then |
| 42941869037 | 10m07s | 2026-11-11 | `failure` — reached final `make`, died on `uapi/app_profile.h` not found after the version-fallback red herring |
| 43252365373 | ~9m | 2026-11-12 | **success** — after symlink wiring, `fetch-depth: 0`, explicit `KSU_VERSION_TAG=v3.2.0-legacy` |

> 💡 Rule of thumb: treat the `KSU_VERSION_TAG fallback: v0.0.1` banner as a **build-log
> symptom, not the disease**. The disease is always the `.git` context of `drivers/kernelsu`.
> Make the wiring a symlink once, and both the version banner and the `uapi` compile error
> disappear together.
