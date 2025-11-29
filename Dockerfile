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
      libidn2-dev \
      unzip

# --- OpenSSL 3.6.0 с поддержкой ENGINE ---
WORKDIR /tmp/openssl
RUN curl -fsSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    | tar xz --strip 1

# Важно: --libdir=lib, чтобы библиотеки не улетали в lib64
RUN ./config \
      shared \
      enable-engine \
      no-ssl3 no-ssl3-method no-zlib \
      --prefix=${OPENSSL_PREFIX} \
      --libdir=lib \
      --openssldir=${OPENSSL_PREFIX}/ssl \
    && make -j${MAKE_JOBS} \
    && make install_sw

# Сборка GOST engine (CMake + submodules)
WORKDIR /tmp/gost-engine
RUN git clone --recurse-submodules --depth 1 ${GOST_ENGINE_REPO} .

# Используем CMAKE_PREFIX_PATH для корректного поиска OpenSSL
RUN cmake -S . -B build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=${OPENSSL_PREFIX} \
      -DCMAKE_PREFIX_PATH=${OPENSSL_PREFIX} \
      -DOPENSSL_ROOT_DIR=${OPENSSL_PREFIX} \
      -DOPENSSL_ENGINES_DIR=${OPENSSL_PREFIX}/lib/engines-3 \
    && ninja -C build -j${MAKE_JOBS} \
    && ninja -C build install

# --- curl с поддержкой OpenSSL/GOST ---
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

# --- Сборка gostsum и других утилит из gost-engine ---
RUN cd /tmp/gost-engine/build && ninja -C . gostsum \
    && cp bin/gostsum ${OPENSSL_PREFIX}/bin/

# --- get-cpcert: утилита для извлечения сертификатов из контейнеров КриптоПро ---
WORKDIR /tmp/get-cpcert
RUN git clone --depth 1 https://github.com/kov-serg/get-cpcert.git . \
    && gcc -o ${OPENSSL_PREFIX}/bin/get-cpcert \
       -I/tmp/gost-engine \
       -I${OPENSSL_PREFIX}/include \
       get-cpcert.c \
       /tmp/gost-engine/build/libgost_core.a \
       /tmp/gost-engine/build/libgost_err.a \
       -L${OPENSSL_PREFIX}/lib \
       -lssl -lcrypto -lpthread -ldl \
    && chmod +x ${OPENSSL_PREFIX}/bin/get-cpcert

# --- Подготовка минимального rootfs для рантайма ---
RUN mkdir -p /usr/local/share/ca-certificates \
    && curl -fsSL -A "Mozilla/5.0" https://gu-st.ru/content/lending/linux_russian_trusted_root_ca_pem.zip -o /tmp/root.zip \
    && curl -fsSL -A "Mozilla/5.0" https://gu-st.ru/content/lending/russian_trusted_sub_ca_pem.zip -o /tmp/sub.zip \
    && unzip -o /tmp/root.zip -d /usr/local/share/ca-certificates/ \
    && unzip -o /tmp/sub.zip -d /usr/local/share/ca-certificates/ \
    && rm /tmp/root.zip /tmp/sub.zip

RUN mkdir -p /tmp/rootfs${OPENSSL_PREFIX} /tmp/rootfs/etc/ssl/certs \
    && cp -a ${OPENSSL_PREFIX}/bin ${OPENSSL_PREFIX}/lib ${OPENSSL_PREFIX}/ssl /tmp/rootfs${OPENSSL_PREFIX}/ \
    && cp -a /etc/ssl/certs/* /tmp/rootfs/etc/ssl/certs/ \
    && ln -s ${OPENSSL_PREFIX}/ssl/openssl.cnf /tmp/rootfs/etc/ssl/openssl.cnf \
    && find /tmp/rootfs${OPENSSL_PREFIX}/lib -name '*.a' -delete \
    && strip /tmp/rootfs${OPENSSL_PREFIX}/bin/* || true \
    && find /tmp/rootfs${OPENSSL_PREFIX}/lib -name '*.so*' -exec strip {} \; || true

# ---------- Стадия рантайма ----------
FROM alpine:3.22.2

ENV OPENSSL_PREFIX=/opt/openssl \
    PATH=/opt/openssl/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/openssl/lib \
    NODE_PATH=/usr/local/lib/node_modules \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apk add --no-cache \
      git \
      jq \
      vim \
      nano \
      python3 \
      py3-pip \
      py3-cryptography \
      py3-certifi \
      nodejs \
      npm \
      ca-certificates \
      libc6-compat \
      libidn2 \
      libpsl \
      p7zip \
      zsh \
      coreutils \
      musl-locales \
      git

# Копируем сертификаты Минцифры и обновляем хранилище
COPY --from=builder /usr/local/share/ca-certificates/*.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Удаляем системный openssl, если он вдруг есть (в alpine его обычно нет в базе, но на всякий случай)
RUN apk del openssl || true

# ВАЖНО: сначала копируем файлы из builder
COPY --from=builder /opt/openssl /opt/openssl

# Затем применяем изменения к скопированным файлам
RUN mv /opt/openssl/bin/stunnel /opt/openssl/bin/stunnel.real \
    && printf '#!/bin/sh\nfor arg do\n  if [ "$arg" = "--version" ]; then\n    set -- "$@" "-version"\n  else\n    set -- "$@" "$arg"\n  fi\n  shift\ndone\nexec /opt/openssl/bin/stunnel.real "$@"\n' > /opt/openssl/bin/stunnel \
    && chmod +x /opt/openssl/bin/stunnel

# Удаляем любые системные libcrypto.so.3 и libssl.so.3, которые могут мешать
RUN rm -f /usr/lib/libcrypto.so.3 /usr/lib/libssl.so.3 \
    && ln -s /opt/openssl/lib/libcrypto.so.3 /usr/lib/libcrypto.so.3 \
    && ln -s /opt/openssl/lib/libssl.so.3 /usr/lib/libssl.so.3

# Конфиг OpenSSL с подключённым GOST-движком
RUN mkdir -p ${OPENSSL_PREFIX}/ssl/certs
RUN ln -sf /etc/ssl/certs/* ${OPENSSL_PREFIX}/ssl/certs/
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

[v3_ca]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = critical,CA:true
EOF

RUN ln -sf ${OPENSSL_PREFIX}/ssl/openssl.cnf /etc/ssl/openssl.cnf

# Установка Oh My Zsh (неинтерактивно)
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Установка gostcrypto для Python
RUN pip3 install --no-cache-dir --break-system-packages gostcrypto

# Установка gostcrypto для Node.js (nodejs-gost-crypto)
RUN npm install -g https://github.com/garex/nodejs-gost-crypto.git

# Создание директории для хелперов
RUN mkdir -p /opt/helpers
COPY <<'EOF' /opt/helpers/gost-cms-sign.sh
#!/bin/sh
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <cert.pem> <key.pem> <file_to_sign>"
    exit 1
fi
openssl cms -sign -engine gost -nodetach -signer "$1" -inkey "$2" -binary -in "$3" -out "$3.sig" -outform DER
EOF

COPY <<'EOF' /opt/helpers/gost-cms-verify.sh
#!/bin/sh
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <cert.pem> <signed_file.sig>"
    exit 1
fi
openssl cms -verify -engine gost -inform DER -in "$2" -CAfile "$1" -out "$2.original"
EOF

RUN chmod +x /opt/helpers/*.sh \
    && ln -s /opt/helpers/gost-cms-sign.sh /usr/local/bin/gost-cms-sign \
    && ln -s /opt/helpers/gost-cms-verify.sh /usr/local/bin/gost-cms-verify

# Для отладки во время сборки образа
RUN openssl version -a
RUN openssl engine gost -t -c
RUN gostsum --version || true
RUN python3 --version
RUN node --version
RUN npm --version
RUN gost-export-cryptopro-key --help || true
RUN jq --version
RUN curl --version
RUN stunnel -version

CMD ["openssl", "version", "-a"]
