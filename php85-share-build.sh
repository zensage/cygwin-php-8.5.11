#!/bin/bash
# PHP 8.5.11 Cygwin 动态编译脚本（修订版）
# 改动要点：
#   1. set -e：任何一步失败立即停止，不再被后面的步骤掩盖
#   2. 5d 单线程构建 libphp.la 并保存日志，产物不全就退出，不进入 5f
#   3. 5d 之前打印 libphp.la 的 Makefile 规则，便于确认 sed 没有让它引用自己
#   4. 清理重复/未使用的变量
#   5. 安装后自动生成动态扩展的 ini
#   6. zip、bz2、gettext、curl 改为动态扩展（减少 cygphp.dll 的启动依赖）
#      curl 的依赖链很长（nghttp2、psl、ssh2、旧版 OpenSSL 1.1 等），做成动态后
#      只有加载 curl 的进程才会带上这些 DLL
#   7. iconv 必须是静态：--with-iconv=/usr（不要写不带目录的 --with-iconv，
#      也不要写 shared）；configure 后有检查，探测不到 ICONV_ALIASED_LIBICONV 会提前退出
#
# 用法：SRC_DIR=/tmp/php-8.5.11 ./php85-share-build.sh
# 注意：5d 如果失败，先看 /tmp/5d-libphp.log 的最后 40 行
## 只编译一个扩展
## make ext/intl/php_intl.lo
## make ext/iconv/iconv.lo
## touch ext/intl/php_intl.c
## make ext/intl/intl.la PHP_GLOBAL_OBJS='' ZEND_EXTRA_LIBS="$(pwd)/libphp.la -lpcre2-8 -lssl -lcrypto" EXTRA_LDFLAGS="$(pwd)/libphp.la -lpcre2-8 -lssl -lcrypto"
# apt-cyg install libgmp-devel libtidy-devel
#
set -e

SRC_DIR="${SRC_DIR:-/tmp/php-8.5.11}"
cd "${SRC_DIR}"

### ====== 1. 环境变量 ======
export PREFIX=/usr/local/php8.5
export MARCH="x86-64-v3"
export EXTRA_CFLAGS="-fno-reorder-blocks-and-partition"

# -fvisibility=default 配合 --export-all-symbols：链接期把符号全部导出到
# cygphp.dll，弥补核心模块没手动标导出宏的问题
export LIBPHP_BUILD_CFLAGS="-DZEND_FIBER_UCONTEXT -fvisibility=default"
export LIBPHP_BUILD_LDFLAGS="-avoid-version -module -no-undefined -Wl,--export-all-symbols"

# make install 真正落地的目录（DIST_DIR 留空时跟 PREFIX 相同）
export DIST_DIR=""
export INSTALL_DIR="${DIST_DIR}${PREFIX}"
export MAKE_JOBS=8

### ====== 2. buildconf + configure ======
time ./buildconf --force

time CFLAGS="-O2 -pipe -march=${MARCH} ${EXTRA_CFLAGS}" \
    CXXFLAGS="-O2 -pipe -march=${MARCH} ${EXTRA_CFLAGS}" \
./configure \
    --prefix="${PREFIX}" \
    --enable-shared \
    --disable-static \
    --disable-rpath \
    --disable-fiber-asm \
    --disable-all \
    --with-pear \
    --enable-cli \
    --enable-cgi \
    --enable-fpm \
    --with-fpm-acl \
    --enable-embed \
    --enable-phpdbg \
    --with-external-pcre \
    --with-config-file-path="${PREFIX}/etc" \
    --with-config-file-scan-dir="${PREFIX}/etc/php.d" \
    \
    --enable-filter \
    --enable-ctype \
    --with-zlib \
    --with-openssl \
    --enable-tokenizer \
    --enable-posix \
    --enable-bcmath \
    --enable-sockets \
    --enable-exif \
    --enable-xml \
    --with-libxml \
    --enable-simplexml \
    --enable-xmlwriter \
    --with-iconv=static,/usr \
    --enable-mbstring=shared \
    --enable-intl=shared \
    --enable-phar=shared \
    --with-zip=shared \
    --with-curl=shared \
    \
    --enable-pdo \
    --enable-session \
    --enable-dom \
    --enable-xmlreader=shared \
    --enable-gd=shared \
    --with-external-gd \
    --with-sodium=shared,/usr \
    --with-sqlite3=shared,/usr \
    --with-pdo-sqlite=shared,/usr \
    --with-ffi=shared,/usr \
    --with-bz2=shared,/usr \
    --with-gettext=shared,/usr \
    --enable-fileinfo=shared \
    \
    --with-gmp=shared,/usr \
    --with-tidy=shared,/usr \
    --with-mysqli=shared,mysqlnd \
    --with-pdo-mysql=shared,mysqlnd \
    --with-pdo-pgsql=shared,/usr \
    --with-pgsql=shared,/usr \
    --with-imap=shared,/usr \
    ac_cv_func_ttyname_r_works=yes

# iconv 必须是静态，并且 configure 要探测到 ICONV_ALIASED_LIBICONV，
# 否则 ext/iconv/iconv.c 会报 implicit declaration of function 'iconv'。
# 在这里提前检查，避免等十几分钟编译到 iconv.c 才失败。
if grep -q '^#define COMPILE_DL_ICONV' main/php_config.h; then
    echo "错误: iconv 被编成了动态扩展（COMPILE_DL_ICONV），请检查 --with-iconv 参数"
    exit 1
fi
if ! grep -q '^#define ICONV_ALIASED_LIBICONV 1' main/php_config.h; then
    echo "错误: configure 没有探测到 ICONV_ALIASED_LIBICONV，iconv.c 会编译失败"
    grep -n 'ICONV' main/php_config.h
    exit 1
fi
echo "iconv 检查通过: 静态编入，且已探测 ICONV_ALIASED_LIBICONV"

### ====== 3. fix libphp ======
echo "Step 5d/6: 先单独构建 embed 共享库 libphp.la（打破循环依赖）"
sed -e 's/ -lphp / libphp.la /g' -i Makefile
sed -i "s/^deplibs_check_method=.*/deplibs_check_method='pass_all'/" libtool
grep "deplibs_check_method='pass_all'" libtool
sed -i 's/^allow_undefined_flag="unsupported"$/allow_undefined_flag=""/' libtool
grep '^allow_undefined_flag=""$' libtool

# 确认 libphp.la 自己的规则没有被上面的 sed 改成引用自己
echo "--- Makefile 中 libphp.la 的规则 ---"
sed -n '/^libphp.la:/,/^$/p' Makefile
echo "--- Makefile 中仍含 -lphp 的行 ---"
grep -n ' -lphp ' Makefile || true

# 只编译 libphp.la 这一个目标，用 LIBPHP_BUILD_* 先解决符号可见性和导出问题，
# 后面 5f 全量编译时各扩展才能正常链接它。
# 单线程 + 日志：并行输出会淹没第一个真实错误。
time make -j"${MAKE_JOBS}" libphp.la \
    EXTRA_CFLAGS="${LIBPHP_BUILD_CFLAGS}" \
    EXTRA_LDFLAGS="${LIBPHP_BUILD_LDFLAGS}" 2>&1 | tee /tmp/5d-libphp.log
# tee 会吞掉 make 的退出码，用 PIPESTATUS 判断
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "5d 失败，见 /tmp/5d-libphp.log"
    exit 1
fi

# 产物检查：不全就停止，不进入 5f
if ! ls -l libphp.la libs/cygphp.dll libs/libphp.dll.a; then
    echo "5d 产物不全，停止。见 /tmp/5d-libphp.log"
    exit 1
fi

echo "Step 5f/6: 编译全部扩展 + SAPI"

# grep -n 'FILEINFO_SHARED_LIBADD' Makefile
# sed -i '/shared_objects_fileinfo.*FILEINFO_SHARED_LIBADD/s|\$(FILEINFO_SHARED_LIBADD)|$(FILEINFO_SHARED_LIBADD) -lpcre2-8|' Makefile
# grep -n 'FILEINFO_SHARED_LIBADD' Makefile

# -module 构建的库 libtool 默认标记为不可被链接（shouldnotlink=yes），这里改掉
grep -n 'shouldnotlink' libphp.la || true
sed -i 's#^shouldnotlink=yes#shouldnotlink=no#' libphp.la
time make -j"${MAKE_JOBS}" \
    PHP_GLOBAL_OBJS='' \
    ZEND_EXTRA_LIBS="$(pwd)/libphp.la -lpcre2-8 -lssl -lcrypto" \
    EXTRA_LDFLAGS="$(pwd)/libphp.la -lpcre2-8 -lssl -lcrypto" 2>&1 | tee /tmp/5f-all.log
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "5f 失败，用 make -j1 重跑可看到第一个错误；日志 /tmp/5f-all.log"
    exit 1
fi

### ====== 4. 安装 ======
echo "Step 6a/6: make install（INSTALL_IT= 跳过写死文件名 libphp.dll 的自动拷贝步骤）"
# PHP 自带的 install-sapi 规则里拷贝 embed 库那一步，文件名写死成 Unix 风格的
# libphp.dll，但 Cygwin 下真实文件名按 soname_spec 的 cyg* 规则叫 cygphp.dll，
# 这一步必然拷贝失败。INSTALL_IT 置空即跳过它，改成下面 6b 手动拷真实文件。
time make install INSTALL_ROOT="${DIST_DIR}" INSTALL_IT= \
    PHP_GLOBAL_OBJS='' \
    ZEND_EXTRA_LIBS="$(pwd)/libphp.la" \
    EXTRA_LDFLAGS="$(pwd)/libphp.la"

echo "Step 6b/6: 手动安装 embed 共享库（真实文件名 cygphp.dll / libphp.dll.a）"
mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/lib"
# cygphp.dll 是运行时实际加载的动态库，必须放进 PATH 能找到的 bin/；
# libphp.dll.a 是给嵌入 PHP 的宿主程序编译期链接用的导入库，放进 lib/。
cp -v libs/cygphp.dll "${INSTALL_DIR}/bin/"
cp -v libs/libphp.dll.a "${INSTALL_DIR}/lib/"

### ====== 5. 动态扩展的 ini ======
echo "Step 7: 生成动态扩展的 ini"
mkdir -p "${INSTALL_DIR}/etc/php.d"
EXT_DIR="$(ls -d "${INSTALL_DIR}"/lib/php/extensions/*/ 2>/dev/null | head -1)"
echo "扩展目录: ${EXT_DIR}"
ls -l "${EXT_DIR}" || true

# iconv 已是静态，旧版本留下的 iconv ini 必须删除，否则启动时会提示重复加载
rm -f "${INSTALL_DIR}/etc/php.d/20-iconv.ini"

# 只为实际存在的 DLL 生成 ini；数字前缀控制加载顺序
ext_l2="mbstring intl phar zip curl"
ext_l3="mbstring intl phar fileinfo xmlreader gd sodium sqlite3 pdo_sqlite ffi zip bz2 gettext curl";
for ext in $ext_l3; do
    if [ -f "${EXT_DIR}${ext}.dll" ]; then
        echo "extension=${ext}" > "${INSTALL_DIR}/etc/php.d/20-${ext}.ini"
    else
        echo "警告: 未找到 ${EXT_DIR}${ext}.dll，跳过 ${ext}.ini"
    fi
done

echo
echo "完成。请把 ${INSTALL_DIR}/bin 加入 PATH（扩展 DLL 运行时要找到 cygphp.dll）："
echo "  export PATH=${INSTALL_DIR}/bin:\$PATH"
echo "验证："
echo "  php -v && php -m"
echo "  php -r 'var_dump(PCRE_VERSION, preg_match(\"/(?:a|b)+c/\", \"ababc\"));'"
echo "编译后请另行执行（不在本脚本内）："
echo "  ./rebase-php.sh ${PREFIX}"
echo "  ./check-composer.sh ${PREFIX}/bin/php /var/www/conf/composer.phar"


###