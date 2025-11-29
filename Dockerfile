# ---------- Стадия сборки ----------
FROM alpine:3.22.2 AS builder

ARG OPENSSL_VERSION=3.6.0
ARG GOST_ENGINE_REPO=https://github.com/gost-engine/engine.git
ARG MAKE_JOBS=4

ENV OPENSSL_PREFIX=/opt/openssl

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
      pkgconfig

# Сборка OpenSSL 3.4.x с поддержкой движков
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
# Важно: тянем сабмодули, чтобы libprov/ имел CMakeLists.txt.[web:99]
RUN git clone --recurse-submodules --depth 1 ${GOST_ENGINE_REPO} .

RUN cmake -S . -B build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=${OPENSSL_PREFIX} \
      -DOPENSSL_ROOT_DIR=${OPENSSL_PREFIX} \
      -DOPENSSL_INCLUDE_DIR=${OPENSSL_PREFIX}/include \
      -DOPENSSL_CRYPTO_LIBRARY=${OPENSSL_PREFIX}/lib/libcrypto.so \
      -DOPENSSL_SSL_LIBRARY=${OPENSSL_PREFIX}/lib/libssl.so \
      -DOPENSSL_ENGINES_DIR=${OPENSSL_PREFIX}/lib/engines-3 \
    && ninja -C build -j${MAKE_JOBS} \
    && ninja -C build install

# Подготовка минимального рантайм-набора
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
      libc6-compat

COPY --from=builder /tmp/rootfs/ /

# Конфиг OpenSSL с подключением GOST-движка
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
