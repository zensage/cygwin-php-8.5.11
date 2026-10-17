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
## run result

** php base and extension and config is run ok **
```
/usr/local/php8.5/bin/php -v && /usr/local/php8.5/bin/php --ini && /usr/local/php8.5/bin/php-config
PHP 8.5.11 (cli) (built: Oct 17 2026 13:12:20) (NTS)
Copyright (c) The PHP Group
Zend Engine v4.5.11, Copyright (c) Zend Technologies
    with Zend OPcache v8.5.11, Copyright (c), by Zend Technologies
Configuration File (php.ini) Path: "/usr/local/php8.5/etc"
Loaded Configuration File:         "/usr/local/php8.5/etc/php.ini"
Scan for additional .ini files in: "/usr/local/php8.5/etc/php.d"
Additional .ini files parsed:      /usr/local/php8.5/etc/php.d/20-bz2.ini,
/usr/local/php8.5/etc/php.d/20-curl.ini,
/usr/local/php8.5/etc/php.d/20-ffi.ini,
/usr/local/php8.5/etc/php.d/20-fileinfo.ini,
/usr/local/php8.5/etc/php.d/20-gd.ini,
/usr/local/php8.5/etc/php.d/20-gettext.ini,
/usr/local/php8.5/etc/php.d/20-gmp.ini,
/usr/local/php8.5/etc/php.d/20-intl.ini,
/usr/local/php8.5/etc/php.d/20-mbstring.ini,
/usr/local/php8.5/etc/php.d/20-mysqli.ini,
/usr/local/php8.5/etc/php.d/20-pgsql.ini,
/usr/local/php8.5/etc/php.d/20-phar.ini,
/usr/local/php8.5/etc/php.d/20-sodium.ini,
/usr/local/php8.5/etc/php.d/20-sqlite3.ini,
/usr/local/php8.5/etc/php.d/20-tidy.ini,
/usr/local/php8.5/etc/php.d/20-xmlreader.ini,
/usr/local/php8.5/etc/php.d/20-zip.ini,
/usr/local/php8.5/etc/php.d/30-pdo_mysql.ini,
/usr/local/php8.5/etc/php.d/30-pdo_pgsql.ini,
/usr/local/php8.5/etc/php.d/30-pdo_sqlite.ini

Usage: /usr/local/php8.5/bin/php-config [OPTION]
Options:
  --prefix            [/usr/local/php8.5]
  --includes          [-I/usr/local/php8.5/include/php -I/usr/local/php8.5/include/php/main -I/usr/local/php8.5/include/php/TSRM -I/usr/local/php8.5/include/php/Zend -I/usr/local/php8.5/include/php/ext -I/usr/local/php8.5/include/php/ext/date/lib]
  --ldflags           []
  --libs              [  -lstdc++ -liconv  -lxml2 -lssl -lcrypto -lpcre2-8 -lz -lxml2 -lxml2 -lxml2 -lxml2 -lz -lssl -lcrypto]
  --extension-dir     [/usr/local/php8.5/lib/php/extensions/no-debug-non-zts-20250925]
  --include-dir       [/usr/local/php8.5/include/php]
  --lib-dir           [/usr/local/php8.5/lib]
  --lib-embed         [libphp.so]
  --man-dir           [/usr/local/php8.5/php/man]
  --php-binary        [/usr/local/php8.5/bin/php.exe]
  --php-sapis         [ cli embed fpm phpdbg cgi]
  --ini-path          [/usr/local/php8.5/etc]
  --ini-dir           [/usr/local/php8.5/etc/php.d]
  --configure-options [--prefix=/usr/local/php8.5 --enable-shared --disable-static --disable-rpath --disable-fiber-asm --disable-all --with-pear --enable-cli --enable-cgi --enable-fpm --with-fpm-acl --enable-embed --enable-phpdbg --with-external-pcre --with-config-file-path=/usr/local/php8.5/etc --with-config-file-scan-dir=/usr/local/php8.5/etc/php.d --enable-filter --enable-ctype --with-zlib --with-openssl --enable-tokenizer --enable-posix --enable-bcmath --enable-sockets --enable-exif --enable-xml --with-libxml --enable-simplexml --enable-xmlwriter --with-iconv=static,/usr --enable-mbstring=shared --enable-intl=shared --enable-phar=shared --with-zip=shared --with-curl=shared --enable-pdo --enable-session --enable-dom --enable-xmlreader=shared --enable-gd=shared --with-external-gd --with-sodium=shared,/usr --with-sqlite3=shared,/usr --with-pdo-sqlite=shared,/usr --with-ffi=shared,/usr --with-bz2=shared,/usr --with-gettext=shared,/usr --enable-fileinfo=shared --with-gmp=shared,/usr --with-tidy=shared,/usr --with-mysqli=shared,mysqlnd --with-pdo-mysql=shared,mysqlnd --with-pdo-pgsql=shared,/usr --with-pgsql=shared,/usr --with-imap=shared,/usr ac_cv_func_ttyname_r_works=yes]
  --version           [8.5.11]
  --vernum            [80511]
```

** pecl and composer check ok **
```
/usr/local/php8.5/bin/pecl help version && /usr/local/php8.5/bin/php /usr/local/php8.5/bin/composer diagnose
PEAR Version: 1.10.18
PHP Version: 8.5.11
Zend Engine Version: 4.5.11
Running on: CYGWIN_NT-10.0-26200 HS125-PC 3.7.0-0.618.g8f145421c964.x86_64 2026-09-30 13:32 UTC x86_64
Checking pubkeys:
Tags Public Key Fingerprint: 57815BA2 7E54DC31 7ECC7CC5 573090D0  87719BA6 8F3BB723 4E5D42D0 84A14642
Dev Public Key Fingerprint: 4AC45767 E5EC2265 2F0C1167 CBBB8A2B  0C708369 153E328C AD90147D AFE50952
OK
Checking Composer version: OK
Composer version: 2.10.3
Checking Composer and its dependencies for vulnerabilities: OK
PHP version: 8.5.11
PHP binary path: /usr/local/php8.5/bin/php
OpenSSL version: OpenSSL 3.5.9 29 Sep 2026
curl version: 8.22.0 libz 1.3.2 brotli brotli/1.2.0 zstd supported ssl OpenSSL/3.5.9 HTTP 1.0, 1.1, 2
zip: extension present, unzip present, 7-Zip present (7z)
Checking platform settings: OK
Checking git settings: OK git version 2.51.0
Checking http connectivity to packagist: OK
Checking https connectivity to packagist: OK
Checking github.com rate limit: OK
Checking disk free space: OK
```

```
---
