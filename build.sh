#!/bin/bash

echo -e "\n[INFO]: BUILD STARTED..!\n"

export KERNEL_ROOT="$(pwd)"
export ARCH=arm64
export KBUILD_BUILD_USER="@donnimsipa"

#init submodules
git submodule update --init --recursive || true

# Wire KernelSU-Next into drivers/kernelsu (expected by drivers/Kconfig:268)
# Use a symlink (not a copy) so Kbuild can still resolve the git root of KernelSU-Next;
# copying loses .git and forces KSU_VERSION fallback to 1 / tag v0.0.1 in CI.
if [ -L "${KERNEL_ROOT}/drivers/kernelsu" ] || [ -d "${KERNEL_ROOT}/drivers/kernelsu" ]; then
    rm -rf "${KERNEL_ROOT}/drivers/kernelsu"
fi
if [ ! -d "${KERNEL_ROOT}/KernelSU-Next/kernel" ]; then
    echo "[INFO]: KernelSU-Next submodule empty; cloning directly..."
    git clone --depth=1 --branch legacy https://github.com/KernelSU-Next/KernelSU-Next.git "${KERNEL_ROOT}/KernelSU-Next" || true
fi
if [ -d "${KERNEL_ROOT}/KernelSU-Next/kernel" ]; then
    mkdir -p "${KERNEL_ROOT}/drivers"
    if ! ln -sfn "${KERNEL_ROOT}/KernelSU-Next/kernel" "${KERNEL_ROOT}/drivers/kernelsu"; then
        echo "[WARN]: symlink failed; falling back to copy (KSU_VERSION will fall back)"
        cp -r "${KERNEL_ROOT}/KernelSU-Next/kernel" "${KERNEL_ROOT}/drivers/kernelsu"
    fi
    echo "[INFO]: drivers/kernelsu wired from KernelSU-Next"
else
    echo "[WARN]: KernelSU-Next not available; drivers/kernelsu will be missing"
fi

mkdir -p "${KERNEL_ROOT}/out" "${KERNEL_ROOT}/build"

# Resolve KernelSU-Next tag explicitly (must be exactly v3.2.0-legacy).
# Passing it on the make command line wins over Kbuild's git-describe fallback,
# so the built driver always reports KSU_VERSION_TAG=v3.2.0-legacy.
KSU_VERSION_TAG="$(git -C "${KERNEL_ROOT}/KernelSU-Next" describe --tags --abbrev=0 2>/dev/null || true)"
if [ -n "${KSU_VERSION_TAG}" ]; then
    echo "[INFO]: KernelSU-Next tag: ${KSU_VERSION_TAG}"
    KSU_VERSION_ARGS=(KSU_VERSION_TAG="${KSU_VERSION_TAG}" KSU_GIT_TAG="${KSU_VERSION_TAG}")
else
    echo "[WARN]: Unable to resolve KernelSU-Next tag from git; relying on Kbuild detection"
    KSU_VERSION_ARGS=()
fi

# Export toolchain paths
export PATH="${KERNEL_ROOT}/prebuilts/toolchain/llvm-arm-toolchain-ship/10.0.9/bin:${PATH}"
export LD_LIBRARY_PATH="${KERNEL_ROOT}/prebuilts/toolchain/llvm-arm-toolchain-ship/10.0.9/lib:${LD_LIBRARY_PATH}"

# Set cross-compile environment variables
export BUILD_CROSS_COMPILE="${KERNEL_ROOT}/prebuilts/toolchain/gcc-cfp/gcc-cfp-single/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
export BUILD_CC="${KERNEL_ROOT}/prebuilts/toolchain/llvm-arm-toolchain-ship/10.0.9/bin/clang"

# Build options for the kernel
export BUILD_OPTIONS=(
    -C "${KERNEL_ROOT}"
    O="${KERNEL_ROOT}/out"
    -j"$(nproc)"
    ARCH=arm64
    DTC_EXT="${KERNEL_ROOT}/tools/dtc"
    CONFIG_BUILD_ARM64_DT_OVERLAY=y
    CROSS_COMPILE="${BUILD_CROSS_COMPILE}"
    CC="${BUILD_CC}"
    CLANG_TRIPLE=aarch64-linux-gnu-
)

build_kernel(){
    # Cleanup
    # make "${BUILD_OPTIONS[@]}" clean && make "${BUILD_OPTIONS[@]}" mrproper

    # Make default configuration: base defconfig + custom.config + droidspaces.config
    make "${BUILD_OPTIONS[@]}" "${KSU_VERSION_ARGS[@]}" winnerlte_eur_open_defconfig custom.config droidspaces.config

    # Resolve new symbols non-interactively (required in CI)
    yes "" | make "${BUILD_OPTIONS[@]}" "${KSU_VERSION_ARGS[@]}" oldconfig

    # Configure the kernel (TUI) when not in GitHub Actions
    if [ -z "${GITHUB_ACTIONS}" ]; then
        make "${BUILD_OPTIONS[@]}" "${KSU_VERSION_ARGS[@]}" menuconfig
    fi

    # Build the kernel (yes "" feeds defaults to any interactive oldconfig prompts)
    yes "" | make "${BUILD_OPTIONS[@]}" "${KSU_VERSION_ARGS[@]}" || exit 1

    # Copy the built kernel+dtb to the build directory
    cp "${KERNEL_ROOT}/out/arch/arm64/boot/Image-dtb" "${KERNEL_ROOT}/build/Image-dtb"

    echo -e "\n[INFO]: BUILD FINISHED..!\n}"
}

build_boot(){
    # unpack, replace, pack using magiskboot
    cd "${KERNEL_ROOT}/prebuilts/magiskboot" && \
        cp "${KERNEL_ROOT}/build/Image-dtb" kernel && \
        ./libmagiskboot repack boot.img && \
        mv new-boot.img "${KERNEL_ROOT}/build/boot.img" && \
        git clean -xfd || true
    cd "${KERNEL_ROOT}"
}

build_tar(){
    cd "${KERNEL_ROOT}/build"
    tar -cvf "Droidspaces-KSUN-Samsung-SM-F900F.tar" boot.img && \
        echo -e "\n[INFO]: TAR BUILT SUCCESSFULLY..!\n"
    cd "${KERNEL_ROOT}"
}

build_kernel && \
    build_boot && \
    build_tar
