#!/bin/bash

echo -e "\n[INFO]: BUILD STARTED..!\n"

#init submodules
git submodule update --init --recursive || true

export KERNEL_ROOT="$(pwd)"
export ARCH=arm64
export KBUILD_BUILD_USER="@donnimsipa"

# Pin KernelSU-Next reported tag (shallow clone safety)
export KSU_VERSION_TAG_OVERRIDE="v3.2.0-legacy"

mkdir -p "${KERNEL_ROOT}/out" "${KERNEL_ROOT}/build"

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
    make "${BUILD_OPTIONS[@]}" winnerlte_eur_open_defconfig custom.config droidspaces.config

    # Configure the kernel (TUI) when not in GitHub Actions
    if [ -z "${GITHUB_ACTIONS}" ]; then
        make "${BUILD_OPTIONS[@]}" menuconfig
    fi

    # Build the kernel
    make "${BUILD_OPTIONS[@]}" || exit 1

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

build_zip(){
    cd "${KERNEL_ROOT}/build"
    zip -j9 "Droidspaces-KSUN-Samsung-SM-F900F.zip" boot.img && \
        echo -e "\n[INFO]: ZIP BUILT SUCCESSFULLY..!\n"
    cd "${KERNEL_ROOT}"
}

build_kernel && \
    build_boot && \
    build_tar && \
    build_zip
