#!/bin/bash
#
# php85-install-cygwin.sh —— 准备编译 PHP 8.5.11（完整版）所需的 Cygwin 环境
#
# @update-time: 2026-10-14
# @author: zensage
# https://github.com/zensage/cygwin-php-8.5.11
#
# 2026-10-14 更新：改用 Cygwin 官方自带的 setup-x86_64.exe 命令行形式装包，
# 不再用 apt-cyg。原因：apt-cyg 装这些 -devel 库时偶尔会出现奇怪的问题，
# 装着装着漏掉一些依赖（比如依赖解析不干净、某些包装了一半），
# setup-x86_64.exe 是 Cygwin 官方装机工具本身，走的是同一套 setup.ini，
# 行为更可靠、不容易漏包。
#
# 2026-10-14 同一天再更新：libsodium-devel、libzip-devel 这两个 Cygwin
# 官方包都已知版本太旧编不过 PHP 8.5（libzip 停在 1.5.1，libsodium 同样
# 版本落后），已经从下面的 PACKAGES 清单里去掉，改成自行从源码编译安装到
# /usr 前缀（sodium 用新版 libsodium，zip 用 libzip >=1.8，实测用的是
# 1.12）。跑 config-cygwin.sh 之前，先确认这两个库已经手动装好：
#   pkg-config --modversion libsodium
#   pkg-config --modversion libzip
# 查得到版本号就说明装对了。本脚本不负责这两个库的自行编译安装步骤。
#
# 完整版 = PHP 8.5.11 核心 + config-cygwin.sh 里开的全部共享扩展需要的
# -devel 库。对应 min 版见 install-cygwin-min.sh（只覆盖 openssl/curl/
# mbstring/phar/pdo_sqlite/sqlite3/zlib 这几个基础扩展）。
#
# 包名核对状态：下面这份清单已经对着 PHP 8.5.11 真实源码配出的扩展列表
# （见 config-cygwin.sh 的 configure 调用）配出来，并对着 Cygwin 官方
# 镜像目录核对过存在性，但没有在真实 Cygwin 环境里逐个装过验证 100%
# 准确——如果 setup-x86_64.exe 报某个包名不存在，去
# https://cygwin.com/packages/package_list.html 确认真实包名后改这里，
# 脚本本身对重复安装是幂等的。
#
# 包名核对记录（2026-10-14，对着 Cygwin 官方镜像目录核实）：
#   libiodbc-devel（odbc/pdo_odbc 走 iODBC 这条路，不是 unixODBC——
#     Cygwin 压根没有 unixODBC 包，ext/odbc 和 ext/pdo_odbc 的
#     config.m4 里 iODBC 和 unixODBC 是两条独立检测分支，用
#     --with-iodbc / --with-pdo-odbc=iodbc 就行）
#   libffi-devel（ffi）
#   openldap-devel（ldap，不是 libldap-devel，Cygwin 没有这个名字）
#   net-snmp-devel（snmp，不是 libnetsnmp-devel/snmp-devel）
#   libenchant-devel（enchant）
#
# 没加（确认 Cygwin 没有打包，装不了，config-cygwin.sh 里对应也没开）：
#   imap 扩展要的 c-client/libc-client 库 —— 官方镜像目录里没有任何
#     imap/c-client 相关包（搜过 "imap" 只匹配到跟 PHP 毫无关系的
#     kf5-kimap，KDE 的东西）。
#   pdo_firebird 要的 Firebird 客户端库/fb_config —— 官方镜像目录里
#     没有 firebird 相关包，Firebird 通常要去官网单独装客户端。
#   com_dotnet 扩展压根没有 config.m4（只有 config.w32），是纯 Windows
#     COM/VC++ 专属实现，不是"没打包"，是这套 autoconf/Cygwin 构建
#     方式原理上就编不出来，没有变通办法。
#   oci8 / pdo_oci —— PHP 8.0 起已经从核心源码树移到 PECL（
#     `ls ext/` 下已经找不到这两个目录了），而且依赖 Oracle 官方的
#     Instant Client SDK，不是哪个包管理器能装的，需要单独去 Oracle
#     官网下载、PECL 单独编译，这份脚本不覆盖。
#   dl_test —— 这是 PHP 自己测试套件用的内部测试扩展（ext/dl_test），
#     不是给生产环境用的功能扩展，故意不开。
#
# 用法：
#   ./install-cygwin.sh
#   SITE=https://mirrors.ustc.edu.cn/cygwin/ ./install-cygwin.sh   # 换镜像
#
set -euo pipefail

log() { time_tag=$(date '+%Y-%m-%d %H:%M:%S'); echo -e "\n[$time_tag]==== $* ====\n"; }
die() { time_tag=$(date '+%Y-%m-%d %H:%M:%S'); echo "[$time_tag]错误: $*" >&2; exit 1; }

### ====== 可调参数 ======
SITE="${SITE:-https://mirrors.163.com/cygwin/}"

### ====== 1. 确保 setup-x86_64.exe 本身可用 ======
SETUP_EXE=""
if command -v setup-x86_64.exe >/dev/null 2>&1; then
    SETUP_EXE="setup-x86_64.exe"
else
    for cand in "/cygdrive/c/cygwin64/setup-x86_64.exe" "$(cygpath "${SYSTEMDRIVE:-C:}" 2>/dev/null)/cygwin64/setup-x86_64.exe"; do
        if [ -n "${cand}" ] && [ -f "${cand}" ]; then
            SETUP_EXE="${cand}"
            break
        fi
    done
fi
if [ -z "${SETUP_EXE}" ]; then
    log "Step 0/2: 没找到已有的 setup-x86_64.exe，先下载一份到临时目录"
    command -v wget >/dev/null 2>&1 || die "连 wget 都没有，没法自动下载 setup-x86_64.exe，请手动下载 https://cygwin.com/setup-x86_64.exe 后把本脚本里 SETUP_EXE 改成那个文件的路径"
    wget -O /tmp/setup-x86_64.exe https://cygwin.com/setup-x86_64.exe
    SETUP_EXE="/tmp/setup-x86_64.exe"
fi
echo "setup-x86_64.exe: ${SETUP_EXE}"
echo "镜像: ${SITE}"

### ====== 2. 安装编译工具链 + 全部共享扩展所需的 -devel 库 ======
log "Step 1/2: 组装 PACKAGES 清单"
## 多个包之间用逗号分隔，按 config-cygwin.sh 的 configure 调用顺序分组，
## 方便对照；改 configure 参数时记得同步改这里。
PACKAGES="gcc-core,gcc-g++,make,binutils"
PACKAGES="${PACKAGES},autoconf,autoconf2.5,automake,automake1.15,libtool,m4"
PACKAGES="${PACKAGES},gettext-devel,libintl-devel,pkg-config,bison"
PACKAGES="${PACKAGES},wget,curl,tar,gzip,xz,diffutils,patch,zip,unzip"
# 核心 / SAPI 必需
PACKAGES="${PACKAGES},libpcre2-devel,libcurl-devel,libssl-devel,libiconv-devel"
# bcmath / bz2 / gmp
PACKAGES="${PACKAGES},libbz2-devel,gmp-devel"
# dba 系列后端（cdb 用内置实现，其余几个要库）
PACKAGES="${PACKAGES},gdbm-devel,lmdb-devel"
# exif/fileinfo/ftp —— 无额外 -devel 需求
# gd + 格式支持
PACKAGES="${PACKAGES},libjpeg-devel,libpng-devel,libwebp-devel,libfreetype-devel,libgd-devel"
# gettext/intl (icu)
PACKAGES="${PACKAGES},icu-devel"
# libedit（交互式 cli 的行编辑/历史）
PACKAGES="${PACKAGES},libedit-devel"
# mysqli / pdo_mysql —— 用内置 mysqlnd，无需系统 mysql 库
# opcache —— 无额外 -devel 需求
# password-argon2
PACKAGES="${PACKAGES},libargon2-devel"
# pdo_pgsql / pgsql
PACKAGES="${PACKAGES},libpq-devel"
# pdo_sqlite / sqlite3
PACKAGES="${PACKAGES},libsqlite3-devel"
# sodium —— 2026-10-14 更新：不再用 Cygwin 官方 libsodium-devel 包装，
# 实测这个包版本太低，编不过（跟 libzip 的情况一样）。改成自己从源码编
# 一份新版 libsodium 装到 /usr 前缀，跑 config-cygwin.sh 前先确认装好、
# pkg-config --modversion libsodium 能查到版本。本脚本不负责这一步。
# tidy
PACKAGES="${PACKAGES},tidy-devel"
# xml 全家桶 (dom/simplexml/xmlreader/xmlwriter/xsl/soap) + libxml
PACKAGES="${PACKAGES},libxml2-devel,libxslt-devel"
# zip / zlib —— 2026-10-14 更新：不再用 Cygwin 官方 libzip-devel 包装，
# 之前实测停留在 1.5.1（2018 年），PHP 8.5 的 ext/zip 要用到更新的函数
# （例如 zip_compression_method_supported）。改成自己从源码编一份新版
# libzip（>=1.8，实测用的是 1.12）装到 /usr 前缀覆盖/补齐，跑
# config-cygwin.sh 前先确认装好、pkg-config --modversion libzip 能查到
# 版本。本脚本不负责这一步，只装 zlib-devel。
PACKAGES="${PACKAGES},zlib-devel"
# ffi / ldap / snmp / enchant / odbc+pdo_odbc（走 iODBC）
PACKAGES="${PACKAGES},libffi-devel,openldap-devel,net-snmp-devel,libenchant-devel"
# openssl / soap / sysvshm 不需要额外的 -devel 包：openssl 用的是上面
# 已经列的 libssl-devel；soap 只需要 libxml2（已列）；sysvshm 靠 Cygwin
# 自带的 System V IPC 模拟，不需要额外库。

log "Step 2/2: 调用 setup-x86_64.exe 静默安装"
echo "PACKAGES=${PACKAGES}"
"${SETUP_EXE}" --no-desktop --no-shortcuts --no-startmenu --quiet-mode \
    --disable-buggy-antivirus --site "${SITE}" --packages "${PACKAGES}"

echo ""
echo "autoconf : $(autoconf --version | head -1)"
echo "libtool  : $(libtool --version | head -1)"
echo "gcc      : $(gcc --version | head -1)"
echo ""

# ============================================================
# 主流程
# ============================================================
build_libsodium
build_libzip

# ============================================================
# 汇总
# ============================================================
banner "全部完成"
printf "  %-12s %-10s %s\n" "库"         "版本"       "安装前缀"
printf "  %-12s %-10s %s\n" "-----------" "----------" "---------"
printf "  %-12s %-10s %s\n" "libsodium"  "${LIBSODIUM_VER}" "${PREFIX}"
printf "  %-12s %-10s %s\n" "libzip"     "${LIBZIP_VER}"    "${PREFIX}"
echo
echo "  PHP 8.5.11 configure 时可使用:"
echo "      --with-sodium=shared --with-zip=shared"

echo "环境准备完成，下一步跑 ./config-cygwin.sh"


# ============================================================
# 通用函数: 处理 libsodium
# ============================================================
build_libsodium() {
    local NEED_BUILD=1

    banner "libsodium ${LIBSODIUM_VER}"
    step "CHECK" "检查 libsodium 是否已安装"

    local PC_VER
    PC_VER=$(check_pc libsodium || true)

    if [ -n "$PC_VER" ]; then
        ok "pkg-config 找到 libsodium, 版本: $PC_VER"
        if check_header "${PREFIX}/include/sodium.h"; then
            ok "头文件存在: ${PREFIX}/include/sodium.h"
        else
            warn "头文件缺失: ${PREFIX}/include/sodium.h"
        fi
        if check_lib "${PREFIX}/lib/libsodium.*"; then
            ok "库文件存在:"
            ls -l "${PREFIX}"/lib/libsodium.* | sed 's/^/       /'
        else
            warn "库文件缺失: ${PREFIX}/lib/libsodium.*"
        fi
        info "libsodium 已安装, 跳过编译流程"
        NEED_BUILD=0
    else
        warn "pkg-config 未找到 libsodium, 需要从源码编译"
    fi

    if [ "$NEED_BUILD" -eq 1 ]; then
        # ---------- download ----------
        step "DOWNLOAD" "下载 libsodium ${LIBSODIUM_VER}"
        cd "${WORK_DIR}"
        if [ -f "${LIBSODIUM_DIR}.tar.gz" ]; then
            info "已存在 ${LIBSODIUM_DIR}.tar.gz, 跳过下载"
        else
            wget "${LIBSODIUM_URL}"
        fi
        rm -rf "${LIBSODIUM_DIR}"
        tar -xf "${LIBSODIUM_DIR}.tar.gz"

        # ---------- config ----------
        step "CONFIG" "配置 libsodium"
        cd "${WORK_DIR}/${LIBSODIUM_DIR}"
        time ./configure --prefix="${PREFIX}"

        # ---------- make ----------
        step "MAKE" "编译 libsodium"
        time make -j"${JOBS}"

        # ---------- install ----------
        step "INSTALL" "安装 libsodium 到 ${PREFIX}"
        time make install
    fi

    # ---------- verify ----------
    step "VERIFY" "验证 libsodium"

    local V
    V=$(check_pc libsodium || echo "NOT FOUND")
    info "pkg-config libsodium : $V"

    ls -l "${PREFIX}"/lib/libsodium.*            2>/dev/null | sed 's/^/       /' || warn "库文件未找到"
    ls -l "${PREFIX}"/include/sodium.h           2>/dev/null | sed 's/^/       /' || warn "sodium.h 未找到"
    ls -l "${PREFIX}"/lib/pkgconfig/libsodium.pc 2>/dev/null | sed 's/^/       /' || warn "libsodium.pc 未找到"
}

# ============================================================
# 通用函数: 处理 libzip
# ============================================================
build_libzip() {
    local NEED_BUILD=1

    banner "libzip ${LIBZIP_VER}"
    step "CHECK" "检查 libzip 是否已安装"

    local PC_VER
    PC_VER=$(check_pc libzip || true)

    if [ -n "$PC_VER" ]; then
        ok "pkg-config 找到 libzip, 版本: $PC_VER"
        if check_header "${PREFIX}/include/zip.h"; then
            ok "头文件存在: ${PREFIX}/include/zip.h"
        else
            warn "头文件缺失: ${PREFIX}/include/zip.h"
        fi
        if check_lib "${PREFIX}/lib/libzip.*"; then
            ok "库文件存在:"
            ls -l "${PREFIX}"/lib/libzip.* | sed 's/^/       /'
        else
            warn "库文件缺失: ${PREFIX}/lib/libzip.*"
        fi
        info "libzip 已安装, 跳过编译流程"
        NEED_BUILD=0
    else
        warn "pkg-config 未找到 libzip, 需要从源码编译"
    fi

    if [ "$NEED_BUILD" -eq 1 ]; then
        # ---------- download ----------
        step "DOWNLOAD" "下载 libzip ${LIBZIP_VER}"
        cd "${WORK_DIR}"
        if [ -f "${LIBZIP_DIR}.tar.gz" ]; then
            info "已存在 ${LIBZIP_DIR}.tar.gz, 跳过下载"
        else
            wget "${LIBZIP_URL}"
        fi
        rm -rf "${LIBZIP_DIR}"
        tar zxvf "${LIBZIP_DIR}.tar.gz"

        # ---------- config ----------
        step "CONFIG" "配置 libzip"
        cd "${WORK_DIR}/${LIBZIP_DIR}"
        rm -rf build && mkdir -p build && cd build
        cmake .. \
            -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
            -DBUILD_SHARED_LIBS=ON \
            -DENABLE_GNUTLS=OFF \
            -DENABLE_OPENSSL=OFF \
            -DENABLE_MBEDTLS=OFF

        # ---------- make ----------
        step "MAKE" "编译 libzip"
        time make -j"${JOBS}"

        # ---------- install ----------
        step "INSTALL" "安装 libzip 到 ${PREFIX}"
        time make install
    fi

    # ---------- verify ----------
    step "VERIFY" "验证 libzip"

    local V
    V=$(check_pc libzip || echo "NOT FOUND")
    info "pkg-config libzip : $V"

    ls -l "${PREFIX}"/lib/libzip.*             2>/dev/null | sed 's/^/       /' || warn "库文件未找到"
    ls -l "${PREFIX}"/include/zip.h            2>/dev/null | sed 's/^/       /' || warn "zip.h 未找到"
    ls -l "${PREFIX}"/lib/pkgconfig/libzip.pc  2>/dev/null | sed 's/^/       /' || warn "libzip.pc 未找到"
}
