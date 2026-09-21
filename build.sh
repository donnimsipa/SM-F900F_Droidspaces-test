#!/bin/bash

echo -e "\n[INFO]: BUILD STARTED..!\n"

#init submodules
git submodule update --init --recursive || true

export KERNEL_ROOT="$(pwd)"
export ARCH=arm64
export KBUILD_BUILD_USER="@donnimsipa"

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
    echo -e "\n[INFO]: BUILDING FLASHABLE ZIP..!\n"
    AK3_DIR="${KERNEL_ROOT}/build/AnyKernel3"
    ZIP_NAME="Droidspaces-KSUN-Samsung-SM-F900F.zip"

    # Fetch AnyKernel3 template if missing
    if [ ! -d "${AK3_DIR}/.git" ]; then
        rm -rf "${AK3_DIR}"
        git clone --depth=1 https://github.com/osm0sis/AnyKernel3 "${AK3_DIR}" || exit 1
    fi

    # Clean previous images/zips
    rm -f "${AK3_DIR}"/Image* "${AK3_DIR}"/zImage "${AK3_DIR}"/*.zip "${KERNEL_ROOT}/build/${ZIP_NAME}"

    # Copy kernel image (Image-dtb contains appended DTB)
    cp "${KERNEL_ROOT}/build/Image-dtb" "${AK3_DIR}/Image-dtb"
    # Also provide as zImage for AnyKernel3 compatibility
    cp "${KERNEL_ROOT}/build/Image-dtb" "${AK3_DIR}/zImage"

    # Customize anykernel.sh for SM-F900F (winner)
    sed -i \
        -e 's|^kernel.string=.*|kernel.string=Droidspaces-KSUN by @donnimsipa for Samsung SM-F900F|' \
        -e 's|^do.devicecheck=.*|do.devicecheck=1|' \
        -e 's|^device.name1=.*|device.name1=winner|' \
        -e 's|^device.name2=.*|device.name2=winnerlte|' \
        -e 's|^device.name3=.*|device.name3=winnerltexx|' \
        -e 's|^device.name4=.*|device.name4=SM-F900F|' \
        -e 's|^device.name5=.*|device.name5=winnerlteeur|' \
        "${AK3_DIR}/anykernel.sh"

    # Auto-detect boot partition / slot mode across recoveries
    sed -i \
        -e 's|^BLOCK=.*|BLOCK=auto;|' \
        -e 's|^IS_SLOT_DEVICE=.*|IS_SLOT_DEVICE=auto;|' \
        "${AK3_DIR}/anykernel.sh"

    # Build flashable zip (exclude .git metadata and leftover zips)
    ( cd "${AK3_DIR}" && zip -r9 "${KERNEL_ROOT}/build/${ZIP_NAME}" * -x '.git/*' README.md '*.zip' ) || exit 1

    echo -e "\n[INFO]: ZIP BUILT SUCCESSFULLY: build/${ZIP_NAME}\n"
}

build_kernel && \
    build_boot && \
    build_tar && \
    build_zip
