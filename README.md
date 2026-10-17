# README.md
**English** | [中文](README_zhCN.md)
```markdown
# PHP 8.5.11 on Cygwin

target: run composer
composer not run problem: 
./configure add two config
--with-external-pcre
--enable-filter


## Background

The newest PHP available in the Cygwin package repository is **8.1.28**, but I need to run **PHP 8.5.11**.

Building PHP 8.5.11 on Cygwin is straightforward **if you build it statically**. Building dynamic extension DLLs, however, runs into all sorts of strange problems (undefined symbols, PE/SEH linking quirks, etc.) that are painful to untangle.

**Recommendation: build PHP statically.** All extensions are compiled directly into `php.exe`, which sidesteps the DLL linking issues entirely.

---

## One-Step Static Build

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
```

After a successful `configure`, build and install:

```bash
time make -j$(nproc)
time make install
```

---

## Build Workflow for Dynamic PHP 8.5 (5 Steps)

If you need **dynamic extension DLLs** instead of a static build, the process is more involved. The following 5 steps outline the dynamic build workflow:

1. **Install dependencies** via `setup.exe` (development packages and libraries).  
   Helper script: `php85-install-cygwin.sh`

2. **Download the PHP source** (`php-8.5.11.tar.xz` / `.tar.gz`).

3. **Build and install `libzip` ** on the local machine.[low version can't build at php-8.5.11]
LIBZIP_VER="1.12"
LIBZIP_URL="https://libzip.org/download/libzip-${LIBZIP_VER}.tar.gz"
LIBZIP_DIR="libzip-${LIBZIP_VER}"

4. **Configure, build, and install PHP** with `php85-build-cygwin.sh`.
need do some hacks. please check php85-share-build.sh

5. **Run smoke tests** to verify the installation.

Alternatively, you can use the package manager route:

```bash
export MIRROR_URL=<your-preferred-mirror>
apt-cyg mirror "${MIRROR_URL}"
apt-cyg update
apt-cyg install php8.5-base
```

This assumes a `php8.5-base` package is available from the mirror. Otherwise, fall back to the source-build workflow above.

---

## Notes

- **`MARCH="x86-64-v3"`** is chosen for portability across modern x86-64 CPUs (Intel Haswell / AMD Excavator and later). Use `native` only if the build machine and the target machine are the same.
- **`--with-external-gd`** relies on the system GD library. Make sure `gdlib.pc` and its dependencies resolve cleanly under `pkg-config`.
- **`ac_cv_func_ttyname_r_works=yes`** works around a Cygwin detection quirk.
- **`--disable-fiber-asm`** avoids a Cygwin-specific assembly issue with PHP fibers.
- If `iconv` fails to link, prepend `LDFLAGS="-L/usr/lib -liconv"` to the `configure` invocation.
- All extensions are **statically linked**; no `extension=` lines are needed in `php.ini`.

---

## Verifying the Installation

```bash
${PREFIX}/bin/php -v
${PREFIX}/bin/php -m
${PREFIX}/bin/php --ini
```

Expected output for `--ini`:

```
Loaded Configuration File:         /usr/local/php8.5/etc/php.ini
Scan for additional .ini files in: /usr/local/php8.5/etc/php.d
```
```
---
