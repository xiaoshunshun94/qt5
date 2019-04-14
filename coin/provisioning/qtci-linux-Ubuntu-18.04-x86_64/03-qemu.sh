#!/usr/bin/env bash
#############################################################################
##
## Copyright (C) 2017 The Qt Company Ltd.
## Contact: http://www.qt.io/licensing/
##
## This file is part of the provisioning scripts of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL21$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see http://www.qt.io/terms-conditions. For further
## information use the contact form at http://www.qt.io/contact-us.
##
## GNU Lesser General Public License Usage
## Alternatively, this file may be used under the terms of the GNU Lesser
## General Public License version 2.1 or version 3 as published by the Free
## Software Foundation and appearing in the file LICENSE.LGPLv21 and
## LICENSE.LGPLv3 included in the packaging of this file. Please review the
## following information to ensure the GNU Lesser General Public License
## requirements will be met: https://www.gnu.org/licenses/lgpl.html and
## http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
##
## As a special exception, The Qt Company gives you certain additional
## rights. These rights are described in The Qt Company LGPL Exception
## version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
##
## $QT_END_LICENSE$
##
#############################################################################

set -ex

# shellcheck source=../common/unix/SetEnvVar.sh
source "${BASH_SOURCE%/*}/../common/unix/SetEnvVar.sh"

# build latest qemu to usermode
sudo apt-get -y install automake autoconf libtool

tempDir=$(mktemp -d)
git clone git://git.qemu.org/qemu.git "$tempDir"
cd "$tempDir"

#latest commit from the master proven to work
git checkout c7f1cf01b8245762ca5864e835d84f6677ae8b1f
git cherry-pick 75e5b70e6b5dcc4f2219992d7cffa462aa406af0
git cherry-pick 04b33e21866412689f18b7ad6daf0a54d8f959a7
git submodule update --init pixman

patch -p1 <<EOT
From aad6a8f17dc7ad3681d2d98a01e474a8904a129b Mon Sep 17 00:00:00 2001
From: Simon Hausmann <simon.hausmann@qt.io>
Date: Fri, 24 Aug 2018 10:38:29 +0200
Subject: [PATCH] linux-user: add support for MADV_DONTNEED

Most flags to madvise() are just hints, so typically ignoring the
syscall and returning okay is fine. However applications exist that do
rely on MADV_DONTNEED behavior to guarantee that upon subsequent access
the mapping is refreshed from the backing file or zero for anonymous
mappings.
---
 linux-user/mmap.c    | 18 ++++++++++++++++++
 linux-user/qemu.h    |  1 +
 linux-user/syscall.c |  6 +-----
 3 files changed, 20 insertions(+), 5 deletions(-)

diff --git a/linux-user/mmap.c b/linux-user/mmap.c
index 61685bf79e..cb3069f27e 100644
--- a/linux-user/mmap.c
+++ b/linux-user/mmap.c
@@ -764,3 +764,16 @@ int target_msync(abi_ulong start, abi_ulong len, int flags)
     start &= qemu_host_page_mask;
     return msync(g2h(start), end - start, flags);
 }
+
+int target_madvise(abi_ulong start, abi_ulong len, int flags)
+{
+    /* A straight passthrough may not be safe because qemu sometimes
+       turns private file-backed mappings into anonymous mappings.
+       Most flags are hints, except for MADV_DONTNEED that applications
+       may rely on to zero out pages, so we pass that through.
+       Otherwise returning success is ok. */
+    if (flags & MADV_DONTNEED) {
+        return madvise(g2h(start), len, MADV_DONTNEED);
+    }
+    return 0;
+}
diff --git a/linux-user/qemu.h b/linux-user/qemu.h
index 4edd7d0c08..3c975909a1 100644
--- a/linux-user/qemu.h
+++ b/linux-user/qemu.h
@@ -429,6 +429,7 @@ int target_munmap(abi_ulong start, abi_ulong len);
 abi_long target_mremap(abi_ulong old_addr, abi_ulong old_size,
                        abi_ulong new_size, unsigned long flags,
                        abi_ulong new_addr);
+int target_madvise(abi_ulong start, abi_ulong len, int flags);
 int target_msync(abi_ulong start, abi_ulong len, int flags);
 extern unsigned long last_brk;
 extern abi_ulong mmap_next_start;
diff --git a/linux-user/syscall.c b/linux-user/syscall.c
index 11a311f9db..94d8abc745 100644
--- a/linux-user/syscall.c
+++ b/linux-user/syscall.c
@@ -11148,11 +11148,7 @@ abi_long do_syscall(void *cpu_env, int num, abi_long arg1,

 #ifdef TARGET_NR_madvise
     case TARGET_NR_madvise:
-        /* A straight passthrough may not be safe because qemu sometimes
-           turns private file-backed mappings into anonymous mappings.
-           This will break MADV_DONTNEED.
-           This is a hint, so ignoring and returning success is ok.  */
-        ret = get_errno(0);
+        ret = get_errno(target_madvise(arg1, arg2, arg3));
         break;
 #endif
 #if TARGET_ABI_BITS == 32
--
2.17.1
EOT

./configure --target-list=arm-linux-user,aarch64-linux-user --static --disable-werror
make
sudo make install
rm -rf "$tempDir"

# Enable binfmt support
sudo apt-get -y install binfmt-support

# Install qemu binfmt for 32bit and 64bit arm architectures
sudo update-binfmts --package qemu-arm --install arm \
/usr/local/bin/qemu-arm \
--magic \
"\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00" \
--mask \
"\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff"
sudo update-binfmts --package qemu-aarch64 --install aarch64 \
/usr/local/bin/qemu-aarch64 \
--magic \
"\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00" \
--mask \
"\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff"

# First test using QFont fails if fonts-noto-cjk is installed. This happens because
# running fontcache for that font takes > 5 mins when run on QEMU. Running fc-cache
# doesn't help since host version creates cache for a wrong architecture and running
# armv7 fc-cache segfaults on QEMU.
sudo DEBIAN_FRONTEND=noninteractive apt-get -y remove fonts-noto-cjk

# If normal fontconfig paths are used, qemu parses what ever files it finds from
# the toolchain sysroot and the rest from the system fonts.
QEMU_FONTCONFPATH=~/qemu_fonts
QEMU_FONTCONFFILE=$QEMU_FONTCONFPATH/fonts.qemu.conf
mkdir -p $QEMU_FONTCONFPATH

# Copy system font configuration files from system to a location with prefix that can't be found from
# the toolchain sysroot
cp -Lr /etc/fonts/* $QEMU_FONTCONFPATH

# Create links to the actual system font files
ln -s /usr/share/fonts $QEMU_FONTCONFPATH/fonts
ln -s /usr/local/share/fonts $QEMU_FONTCONFPATH/local_fonts

# Change font configuration file to point to files that can't be found from the toolchain sysroot
sed $QEMU_FONTCONFPATH/fonts.conf -e "s:conf.d:$QEMU_FONTCONFPATH/conf.d:" > $QEMU_FONTCONFFILE
sed $QEMU_FONTCONFFILE -e "s:/usr/share/fonts:$QEMU_FONTCONFPATH/fonts:" -i
sed $QEMU_FONTCONFFILE -e "s:/usr/local/share/fonts:$QEMU_FONTCONFPATH/local_fonts:" -i

# Set QEMU font configuration variables
qemu_env="FONTCONFIG_FILE=$QEMU_FONTCONFFILE"
qemu_env="${qemu_env},FONTCONFIG_PATH=$QEMU_FONTCONFPATH"

# Disable QtWayland window decorations, as they cause flakiness when used inside qemu (QTBUG-66173)
qemu_env="${qemu_env},QT_WAYLAND_DISABLE_WINDOWDECORATION=1"

SetEnvVar "QEMU_SET_ENV" "\"${qemu_env}\""
