# README_zhCN.md
[English](README.md) | **中文**

```markdown
# Cygwin 上的 PHP 8.5.11

## 背景

Cygwin 软件源中最新的 PHP 版本是 **8.1.28**，但我需要使用 **PHP 8.5.11**。

在 Cygwin 上编译 PHP 8.5.11，**静态编译非常简单**；但若想生成动态扩展 DLL，就会遇到各种奇怪的问题（未定义符号、PE/SEH 链接异常等），调试起来非常麻烦。

**建议：直接静态编译 PHP。** 所有扩展都编入 `php.exe`，从根本上绕开 DLL 链接问题。

---

## 一步完成静态编译

```bash
MARCH="x86-64-v3"
EXTRA_CFLAGS="-fno-reorder-blocks-and-partition"
PREFIX="/usr/local/php8.5"
CONFIG_FILE_PATH="${PREFIX}/etc"
CONFIG_SCAN_DIR="${PREFIX}/etc/php.d"

time CFLAGS="-O2 -pipe -march=${MARCH} ${EXTRA_CFLAGS}" \
CXXFLAGS="-O2 -pipe -march=${MARCH} ${EXTRA_CFLAGS}" \
./configure \
    --prefix="${PREFIX}" \
    --exec-prefix="${PREFIX}" \
    --localstatedir="${PREFIX}/var" \
    --sysconfdir="${PREFIX}/etc" \
    --with-config-file-path="${CONFIG_FILE_PATH}" \
    --with-config-file-scan-dir="${CONFIG_SCAN_DIR}" \
    --with-layout=GNU \
    --disable-rpath \
    --disable-fiber-asm \
    --disable-all \
    --enable-cli \
    --enable-cgi \
    --enable-fpm \
    --with-fpm-acl \
    --enable-embed \
    --enable-phpdbg \
    \
    --enable-phar \
    --with-curl \
    --enable-mbstring \
    --enable-gd \
    --with-external-gd \
    --with-iconv \
    --enable-intl \
    --enable-pdo \
    --with-pdo-sqlite \
    --with-sqlite3 \
    --with-sodium \
    --enable-xml \
    --with-libxml \
    --enable-xmlreader \
    --enable-xmlwriter \
    --with-zip \
    --with-zlib \
    --enable-dom \
    --enable-fileinfo \
    --enable-session \
    --enable-simplexml \
    --enable-ctype \
    --enable-bcmath \
    --with-mysqli=mysqlnd \
    --with-pdo-mysql=mysqlnd \
    --with-jpeg \
    --with-freetype \
    --with-webp \
    --enable-exif \
    --with-gettext \
    --enable-sockets \
    --enable-tokenizer \
    --with-bz2 \
    ac_cv_func_ttyname_r_works=yes
```

`configure` 通过后，执行编译与安装：

```bash
time make -j$(nproc)
time make install
```

---

## 动态 PHP 8.5 的编译流程（共 5 步）

如果你需要的是**动态扩展 DLL** 而不是静态编译，过程会复杂许多。以下 5 步概述了动态编译的工作流程：

1. **通过 `setup.exe` 安装依赖**（开发包和库文件）。  
   辅助脚本：`php85-install-cygwin.sh`

2. **下载 PHP 源码**（`php-8.5.11.tar.xz` / `.tar.gz`）。

3. **在本机编译并安装 `libzip` 和 `libsodium`**。

4. **使用 `php85-build-cygwin.sh` 配置、编译并安装 PHP**。

5. **运行测试**，验证安装是否正常。

也可以改用包管理器方式：

```bash
export MIRROR_URL=<你偏好的镜像地址>
apt-cyg mirror "${MIRROR_URL}"
apt-cyg update
apt-cyg install php8.5-base
```

前提是镜像里确实存在 `php8.5-base` 包。否则请回到上面的源码编译流程。

---

## 注意事项

- **`MARCH="x86-64-v3"`**：选择这个级别是为了在主流 x86-64 CPU（Intel Haswell / AMD Excavator 及之后）上保持兼容。只有在编译机与运行机完全相同时，才建议用 `native`。
- **`--with-external-gd`**：依赖系统 GD 库，需确保 `pkg-config` 能正确解析 `gdlib.pc` 及其依赖链。
- **`ac_cv_func_ttyname_r_works=yes`**：绕过 Cygwin 上的一项功能检测问题。
- **`--disable-fiber-asm`**：避免 PHP Fiber 在 Cygwin 上的汇编兼容性问题。
- 若 `iconv` 链接失败，在 `configure` 前加上 `LDFLAGS="-L/usr/lib -liconv"`。
- 所有扩展均为**静态链接**，`php.ini` 中**无需**写任何 `extension=` 行。

---

## 验证安装

```bash
${PREFIX}/bin/php -v
${PREFIX}/bin/php -m
${PREFIX}/bin/php --ini
```

`--ini` 的预期输出：

```
Loaded Configuration File:         /usr/local/php8.5/etc/php.ini
Scan for additional .ini files in: /usr/local/php8.5/etc/php.d
```
```
