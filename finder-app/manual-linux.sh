#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig || {
        echo "make defconfig failed"
        exit 1
    }
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j$(nproc) Image || {
        echo "Kernel build failed"
        exit 1
    }

fi

echo "Adding the Image in outdir"
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/Image" || {
    echo "Failed to copy kernel image"
    exit 1
}

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
mkdir -p "${OUTDIR}/rootfs"/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,home,dev,lib,lib64} || {
    echo "Failed to create rootfs directory structure"
    exit 1
}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
    make defconfig
else
    cd busybox
fi

# TODO: Make and install busybox
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j$(nproc) || {
    echo "Busybox build failed"
    exit 1
}
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} CONFIG_PREFIX="${OUTDIR}/rootfs" install || {
    echo "Busybox install failed"
    exit 1
}

echo "Library dependencies"
${CROSS_COMPILE}readelf -a "${OUTDIR}/rootfs/bin/busybox" | grep "program interpreter"
${CROSS_COMPILE}readelf -a "${OUTDIR}/rootfs/bin/busybox" | grep "Shared library"

# TODO: Add library dependencies to rootfs
cd "${OUTDIR}/rootfs"
# Copy program interpreter (ld-linux-aarch64.so.1)
INTERPRETER=$(${CROSS_COMPILE}readelf -a "${OUTDIR}/rootfs/bin/busybox" | grep "program interpreter" | sed -E 's/.*\[(.*)\]/\1/')
if [ -n "$INTERPRETER" ]; then
    INTERPRETER_PATH=$(find /usr -name "$(basename "$INTERPRETER")" 2>/dev/null | head -n 1)
    if [ -n "$INTERPRETER_PATH" ]; then
        cp "$INTERPRETER_PATH" lib/ || {
            echo "Failed to copy program interpreter"
            exit 1
        }
    else
        echo "Warning: Could not find program interpreter $(basename "$INTERPRETER") in /usr"
        SYSROOT=$(${CROSS_COMPILE}gcc --print-sysroot)
        if [ -n "$SYSROOT" ] && [ -f "${SYSROOT}/lib/$(basename "$INTERPRETER")" ]; then
            cp "${SYSROOT}/lib/$(basename "$INTERPRETER")" lib/ || {
                echo "Failed to copy program interpreter from sysroot"
                exit 1
            }
        else
            echo "Error: Could not find program interpreter in sysroot"
            exit 1
        fi
    fi
fi
# Copy shared libraries
# Detect sysroot for cross-compiler
SYSROOT=$(${CROSS_COMPILE}gcc --print-sysroot)

# Create lib directories
mkdir -p ${OUTDIR}/rootfs/lib
mkdir -p ${OUTDIR}/rootfs/lib64

# Copy the dynamic linker
cp -a ${SYSROOT}/lib/ld-linux-aarch64.so.1 ${OUTDIR}/rootfs/lib/

# Copy shared libraries including symlinks
cp -a ${SYSROOT}/lib64/libm.so.* ${OUTDIR}/rootfs/lib64/
cp -a ${SYSROOT}/lib64/libc.so.* ${OUTDIR}/rootfs/lib64/
cp -a ${SYSROOT}/lib64/libresolv.so.* ${OUTDIR}/rootfs/lib64/

# Set permissions and ownership
sudo chmod 755 ${OUTDIR}/rootfs/lib/ld-linux-aarch64.so.1
sudo chmod 755 ${OUTDIR}/rootfs/lib64/*.so.*
sudo chown root:root ${OUTDIR}/rootfs/lib/ld-linux-aarch64.so.1
sudo chown root:root ${OUTDIR}/rootfs/lib64/*.so.*

# TODO: Make device nodes
sudo mknod -m 666 "${OUTDIR}/rootfs/dev/null" c 1 3 || {
    echo "Failed to create /dev/null"
    exit 1
}
sudo mknod -m 666 "${OUTDIR}/rootfs/dev/console" c 5 1 || {
    echo "Failed to create /dev/console"
    exit 1
}

# TODO: Clean and build the writer utility
cd "${FINDER_APP_DIR}"
make CROSS_COMPILE="${CROSS_COMPILE}" clean || {
    echo "Warning: 'make clean' failed, continuing with build"
}
make CROSS_COMPILE="${CROSS_COMPILE}" writer || {
    echo "Failed to build writer utility"
    exit 1
}
if [ ! -f writer ]; then
    echo "Error: writer binary not found after build"
    exit 1
fi
# Ensure rootfs/home is writable
sudo chmod -R u+w "${OUTDIR}/rootfs/home" || {
    echo "Failed to set write permissions on rootfs/home"
    exit 1
}
cp writer "${OUTDIR}/rootfs/home/" || {
    echo "Failed to copy writer utility"
    exit 1
}
if [ ! -d "${OUTDIR}/rootfs/home" ]; then
    echo "Error: ${OUTDIR}/rootfs/home directory does not exist"
    sudo mkdir -p "${OUTDIR}/rootfs/home" || {
        echo "Failed to create ${OUTDIR}/rootfs/home directory"
        exit 1
    }
fi

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
cp "${FINDER_APP_DIR}/finder.sh" "${OUTDIR}/rootfs/home/" || {
    echo "Failed to copy finder.sh"
    exit 1
}
mkdir -p "${OUTDIR}/rootfs/home/conf"
cp "${FINDER_APP_DIR}/conf/username.txt" "${OUTDIR}/rootfs/home/conf/" || {
    echo "Failed to copy username.txt"
    exit 1
}
cp "${FINDER_APP_DIR}/conf/assignment.txt" "${OUTDIR}/rootfs/home/conf/" || {
    echo "Failed to copy assignment.txt"
    exit 1
}
cp "${FINDER_APP_DIR}/finder-test.sh" "${OUTDIR}/rootfs/home/" || {
    echo "Failed to copy finder-test.sh"
    exit 1
}
cp "${FINDER_APP_DIR}/autorun-qemu.sh" "${OUTDIR}/rootfs/home/" || {
    echo "Failed to copy autorun-qemu.sh"
    exit 1
}
# Modify finder-test.sh to use correct conf path
sed -i 's|\.\./conf/assignment.txt|conf/assignment.txt|g' "${OUTDIR}/rootfs/home/finder-test.sh" || {
    echo "Failed to modify finder-test.sh"
    exit 1
}

# TODO: Chown the root directory
sudo chown -R root:root "${OUTDIR}/rootfs" || {
    echo "Failed to chown rootfs"
    exit 1
}
# Set SUID bit on busybox after install
sudo chmod u+s "${OUTDIR}/rootfs/bin/busybox" || {
    echo "Failed to set SUID bit on busybox"
    exit 1
}

# TODO: Create initramfs.cpio.gz
cd "${OUTDIR}/rootfs"
sudo tee init > /dev/null << EOF
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
exec /bin/sh
EOF
sudo chmod +x init
find . | cpio -o -H newc | gzip > "${OUTDIR}/initramfs.cpio.gz" || {
    echo "Failed to create initramfs.cpio.gz"
    exit 1
}

