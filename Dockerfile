# ---------- Стадия сборки ----------
FROM alpine:3.22.2 AS builder

ARG OPENSSL_VERSION=3.6.0
ARG GOST_ENGINE_REPO=https://github.com/gost-engine/engine.git
ARG CURL_VERSION=8.17.0
ARG STUNNEL_VERSION=5.76
ARG MAKE_JOBS=4

ENV OPENSSL_PREFIX=/opt/openssl

# Билд-зависимости
RUN apk add --no-cache \
      build-base \
      git \
      perl \
      linux-headers \
      coreutils \
      bash \
      ca-certificates \
      curl \
      cmake \
      ninja \
      pkgconfig \
      libpsl-dev \
      libidn2-dev

# --- OpenSSL 3.6.0 с поддержкой ENGINE ---
WORKDIR /tmp/openssl
RUN curl -fsSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    | tar xz --strip 1

RUN ./config \
      shared \
      enable-engine \
      no-ssl3 no-ssl3-method no-zlib \
      --prefix=${OPENSSL_PREFIX} \
      --openssldir=${OPENSSL_PREFIX}/ssl \
    && make -j${MAKE_JOBS} \
    && make install_sw

# Сборка GOST engine (CMake + submodules)
WORKDIR /tmp/gost-engine
RUN git clone --recurse-submodules --depth 1 ${GOST_ENGINE_REPO} .

RUN cmake -S . -B build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=${OPENSSL_PREFIX} \
      -DOPENSSL_ROOT_DIR=${OPENSSL_PREFIX} \
      -DOPENSSL_ENGINES_DIR=${OPENSSL_PREFIX}/lib/engines-3 \
    && ninja -C build -j${MAKE_JOBS} \
    && ninja -C build install

# --- curl 8.5.0 с поддержкой OpenSSL/GOST ---
WORKDIR /tmp/curl
RUN curl -fsSL https://curl.se/download/curl-${CURL_VERSION}.tar.gz \
    | tar xz --strip 1

RUN CPPFLAGS="-I${OPENSSL_PREFIX}/include" \
    LDFLAGS="-L${OPENSSL_PREFIX}/lib -Wl,-rpath,${OPENSSL_PREFIX}/lib" \
    LD_LIBRARY_PATH=${OPENSSL_PREFIX}/lib \
    PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/pkgconfig" \
    ./configure \
      --prefix=${OPENSSL_PREFIX} \
      --with-openssl=${OPENSSL_PREFIX} \
      --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
      --disable-manual \
      --disable-docs \
    && make -j${MAKE_JOBS} \
    && make install

# --- stunnel 5.76 с поддержкой OpenSSL 3.6.0 ---
# 5.76 доступен в основном downloads/ каталоге, старые версии лежат в archive/5.x.
WORKDIR /tmp/stunnel
RUN curl -fsSL https://www.stunnel.org/downloads/archive/5.x/stunnel-${STUNNEL_VERSION}.tar.gz \
    | tar xz --strip 1

RUN CPPFLAGS="-I${OPENSSL_PREFIX}/include" \
    LDFLAGS="-L${OPENSSL_PREFIX}/lib -Wl,-rpath,${OPENSSL_PREFIX}/lib" \
    LD_LIBRARY_PATH=${OPENSSL_PREFIX}/lib \
    ./configure \
      --prefix=${OPENSSL_PREFIX} \
      --with-openssl=${OPENSSL_PREFIX} \
      --with-ssl=${OPENSSL_PREFIX} \
    && make -j${MAKE_JOBS} \
    && make install

# --- Подготовка минимального rootfs для рантайма ---
RUN mkdir -p /tmp/rootfs${OPENSSL_PREFIX} /tmp/rootfs/etc/ssl \
    && cp -a ${OPENSSL_PREFIX}/bin ${OPENSSL_PREFIX}/lib ${OPENSSL_PREFIX}/ssl /tmp/rootfs${OPENSSL_PREFIX}/ \
    && cp -a /etc/ssl/certs /tmp/rootfs/etc/ssl/ \
    && find /tmp/rootfs${OPENSSL_PREFIX}/lib -name '*.a' -delete \
    && strip /tmp/rootfs${OPENSSL_PREFIX}/bin/* || true \
    && find /tmp/rootfs${OPENSSL_PREFIX}/lib -name '*.so*' -exec strip {} \; || true

# ---------- Стадия рантайма ----------
FROM alpine:3.22.2

ENV OPENSSL_PREFIX=/opt/openssl \
    PATH=/opt/openssl/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/openssl/lib

RUN apk add --no-cache \
      ca-certificates \
      libc6-compat \
      libidn2 \
      libpsl

# Удаляем системный openssl, если он вдруг есть (в alpine его обычно нет в базе, но на всякий случай)
RUN apk del openssl || true

COPY --from=builder /opt/openssl /opt/openssl

# Удаляем любые системные libcrypto.so.3 и libssl.so.3, которые могут мешать
RUN rm -f /usr/lib/libcrypto.so.3 /usr/lib/libssl.so.3

# Конфиг OpenSSL с подключённым GOST-движком
RUN mkdir -p ${OPENSSL_PREFIX}/ssl
RUN cat > ${OPENSSL_PREFIX}/ssl/openssl.cnf <<'EOF'
openssl_conf = openssl_init

[openssl_init]
engines = engine_section

[engine_section]
gost = gost_section

[gost_section]
engine_id = gost
dynamic_path = /opt/openssl/lib/engines-3/gost.so
default_algorithms = ALL
EOF

# Для отладки во время сборки образа
RUN openssl version -a || true
RUN openssl ciphers | tr ':' '\n' | grep -i gost || true

CMD ["openssl", "version", "-a"]
