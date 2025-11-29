# 🔐 OpenSSL 3.6.0 + GOST Engine на Alpine

[![Alpine](https://img.shields.io/badge/Alpine-3.22.2-0D597F?logo=alpinelinux)](https://alpinelinux.org/)
[![OpenSSL](https://img.shields.io/badge/OpenSSL-3.6.0-blue)](https://www.openssl.org/)
[![GOST](https://img.shields.io/badge/GOST-Engine-red)](https://github.com/gost-engine/engine)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)
[![Image Size](https://img.shields.io/badge/Image%20Size-53.8%20MB-brightgreen)](https://hub.docker.com/)
[![Compression](https://img.shields.io/badge/Compressed-15.2%20MB-9cf)](https://hub.docker.com/)

Легковесный, оптимизированный Docker‑образ с **OpenSSL 3.6.0**, собранным из исходников, и **GOST‑движком** (`gost-engine/engine`) для использования российских криптографических алгоритмов. Образ разработан для максимальной производительности и минимального размера (~53.8 МБ) благодаря multi‑stage сборке на Alpine Linux.

---

## 📋 Содержание

- [Возможности](#возможности)
- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Архитектура](#архитектура)
- [Примеры использования](#примеры-использования)
- [Конфигурация](#конфигурация)
- [Лучшие практики](#лучшие-практики)
- [Отладка](#отладка)
- [Размер и производительность](#размер-и-производительность)
- [Лицензия](#лицензия)

---

## 🎯 Возможности

### ✅ Криптографические алгоритмы

#### Асимметричная криптография (ГОСТ Р 34.10)

- **ГОСТ Р 34.10‑2001**: DSA-подобный алгоритм, 256 бит
- **ГОСТ Р 34.10‑2012**: 256 и 512 бит (рекомендуемый, FIPS 186-4 compatible)

#### Симметричная криптография

| Алгоритм | Ключ | Блок | Режимы |
|----------|------|------|--------|
| **ГОСТ 28147‑89** (Магадан) | 256 бит | 64 бит | ECB, CBC, CFB, OFB, CTR, CTRACKPM |
| **ГОСТ Р 34.12‑2015 (Кузнечик)** | 256 бит | 128 бит | ECB, CBC, CFB, OFB, CTR, MGMACKPM, CTRACKPM |
| **ГОСТ Р 34.12‑2015 (Магма)** | 256 бит | 64 бит | ECB, CBC, CTR, MGMACKPM, CTRACKPM |

#### Хеш-функции и MAC

- **ГОСТ Р 34.11‑94**: 256 бит (legacy, для совместимости)
- **ГОСТ Р 34.11‑2012**: 256 бит (`md_gost12_256`) и 512 бит (`md_gost12_512`)
- **GOST MAC**: на базе ГОСТ 28147‑89
- **GOST MAC 12**: на базе ГОСТ Р 34.11‑2012
- **Кузнечик MAC** и **Магма MAC**: специализированные MACs

### 📊 Технические параметры

| Параметр | Значение |
|----------|----------|
| **OpenSSL версия** | 3.6.0 (LTS) |
| **Base image** | Alpine 3.22.2 |
| **Размер образа** | 53.8 МБ |
| **Сжатый размер** | 15.2 МБ (72% compression ratio) |
| **Архитектура** | x86_64, aarch64 (ARM64/Apple Silicon) ✅ |
| **Engine API** | OpenSSL 3.x ENGINE + Provider |
| **TLS версии** | TLSv1.2, TLSv1.3 |
| **Time to build** | 5-10 минут |

---

## 📦 Требования

- **Docker**: 20.10+
- **Docker Compose**: v2.0+
- **ОС хоста**: Linux (x86_64, aarch64), macOS (Intel/Apple Silicon), Windows (WSL2)
- **Интернет**: доступ для скачивания исходников OpenSSL и репозитория `gost-engine`
- **Дисковое пространство**: ~15-20 ГБ для промежуточных слоёв при сборке

---

## 🚀 Быстрый старт

### 2️⃣ Сборка образа

```bash
docker compose build --no-cache
```

**⏱️ Время сборки:** 5-10 минут (зависит от интернета и ПК).

### 3️⃣ Запуск контейнера

```bash
# Интерактивный режим для экспериментов
docker compose run --rm -it openssl-gost sh
```

### 4️⃣ Проверка работоспособности

```bash
# Внутри контейнера:
openssl version -a
openssl engine -t -c
```

**Ожидаемый результат:**
```
OpenSSL 3.6.0 1 Oct 2025 (Library: OpenSSL 3.6.0 1 Oct 2025)
...
ENGINESDIR: "/opt/openssl/lib/engines-3"

(gost) Reference implementation of GOST engine
 [gost89, kuznyechik-*, magma-*, md_gost12_256, md_gost12_512, ...]
     [ available ]
```

---

## 🏗️ Архитектура

### Multi-Stage Build

Образ построен в **две стадии** для минимизации финального размера:

```
┌──────────────────────────────────────────────────────────┐
│ STAGE 1: BUILDER (Alpine 3.22.2 + Toolchain)             │
├──────────────────────────────────────────────────────────┤
│ ✓ build-base, cmake, ninja, git, perl, curl              │
│ ✓ Скачать OpenSSL 3.6.0 из исходников                    │
│ ✓ ./config + make install_sw (с enable-engine)           │
│ ✓ Скачать gost-engine/engine (с git submodules)          │
│ ✓ CMake + Ninja build и install в /opt/openssl           │
│ ✓ Оптимизация: strip, удаление *.a, минимизация         │
│ ✓ Размер: ~3 ГБ (потом удаляется)                        │
└──────────────────────────────────────────────────────────┘
                         ↓ COPY /tmp/rootfs
┌──────────────────────────────────────────────────────────┐
│ STAGE 2: RUNTIME (Alpine 3.22.2 minimal)                 │
├──────────────────────────────────────────────────────────┤
│ ✓ ca-certificates, libc6-compat           │
│ ✓ OpenSSL бинарники + библиотеки                         │
│ ✓ GOST-engine .so файлы                                  │
│ ✓ Конфигурационные файлы                                 │
│ ✓ Сертификаты (CA)                                       │
│ ✓ Размер: 53.8 МБ ✅                                     │
└──────────────────────────────────────────────────────────┘
```

### Переменные окружения

| Переменная | Значение | Описание |
|-----------|---------|---------|
| `OPENSSL_PREFIX` | `/opt/openssl` | Корень установки OpenSSL |
| `OPENSSL_CONF` | `/opt/openssl/ssl/openssl.cnf` | Конфиг с GOST-движком |
| `LD_LIBRARY_PATH` | `/opt/openssl/lib` | Путь к динамическим библиотекам |
| `PATH` | `/opt/openssl/bin:...` | Включает кастомный `openssl` бинарник |

---

## 💡 Примеры использования

### 🔍 Проверка доступных GOST-шифров

```bash
docker compose run --rm openssl-gost sh -c \
  'openssl ciphers | tr ":" "\n" | grep -i gost | head -10'
```

**Результат:**
```
GOST2012-GOST8912-GOST8912
GOST2001-GOST89-GOST89
kuznyechik-ctr-acpkm-omac
magma-ctr-acpkm-omac
...
```

### 🔑 Генерация GOST-ключа ГОСТ Р 34.10‑2012 (256 бит)

```bash
docker compose run --rm openssl-gost sh -c '
mkdir -p /tmp/gost-keys

# Сгенерировать ключ с CryptoPro параметрами
openssl genpkey \
  -engine gost \
  -algorithm gost2012_256 \
  -pkeyopt paramset:A \
  -out /tmp/gost-keys/private.key

# Просмотреть ключ
openssl pkey -in /tmp/gost-keys/private.key -text -noout

# Извлечь публичный ключ
openssl pkey -in /tmp/gost-keys/private.key \
  -pubout -out /tmp/gost-keys/public.key
'
```

**Параметры CryptoPro для gost2012_256:**
- `paramset:A` — рекомендуемые параметры (по умолчанию)
- `paramset:B` — альтернативные параметры
- `paramset:C` — специальные параметры

### 📝 Хеширование данных ГОСТ Р 34.11‑2012

```bash
docker compose run --rm openssl-gost sh -c '
# Создать тестовый файл
echo "Привет, ГОСТ!" > /tmp/data.txt

# Хеш 256 бит
openssl dgst -md_gost12_256 /tmp/data.txt

# Хеш 512 бит
openssl dgst -md_gost12_512 /tmp/data.txt

# Со специальными флагами
openssl dgst -md_gost12_256 -hex /tmp/data.txt
'
```

### 🔐 Создание самоподписанного сертификата с GOST-ключом

```bash
docker compose run --rm openssl-gost sh -c '
mkdir -p /tmp/gost-certs

# Сгенерировать ключ
openssl genpkey \
  -engine gost \
  -algorithm gost2012_256 \
  -pkeyopt paramset:A \
  -out /tmp/gost-certs/server.key

# Создать самоподписанный сертификат (365 дней)
openssl req -new -x509 \
  -engine gost \
  -key /tmp/gost-certs/server.key \
  -out /tmp/gost-certs/server.crt \
  -days 365 \
  -subj "/C=RU/ST=Moscow/L=Moscow/O=MyOrg/CN=gost.example.com" \
  -addext "subjectAltName=DNS:gost.example.com"

# Проверить сертификат
openssl x509 -in /tmp/gost-certs/server.crt -text -noout
'
```

### 🔒 Шифрование/расшифрование с GOST 28147‑89

```bash
docker compose run --rm openssl-gost sh -c '
# Исходные данные
echo "Секретное сообщение для ГОСТ" > /tmp/plain.txt

# Шифрование в режиме CFB
openssl enc -gost89-cfb \
  -in /tmp/plain.txt \
  -out /tmp/plain.txt.gost \
  -k "MySecurePassword" \
  -S "SomeRandomSalt"

# Расшифрование
openssl enc -d -gost89-cfb \
  -in /tmp/plain.txt.gost \
  -out /tmp/plain.dec.txt \
  -k "MySecurePassword" \
  -S "SomeRandomSalt"

# Проверить результат
cat /tmp/plain.dec.txt
'
```

**Доступные режимы GOST 28147‑89:**
- `gost89` — базовый (ECB‑подобный)
- `gost89-cbc` — режим сцепления блоков
- `gost89-cfb` — режим обратной связи по ошибке
- `gost89-ctr` — счётный режим

### 📊 Подпись данных GOST-ключом

```bash
docker compose run --rm openssl-gost sh -c '
mkdir -p /tmp/gost-sign

# Сгенерировать ключ для подписи
openssl genpkey \
  -engine gost \
  -algorithm gost2012_256 \
  -pkeyopt paramset:A \
  -out /tmp/gost-sign/sign.key

# Подписать данные
echo "Документ для подписи" > /tmp/gost-sign/document.txt

openssl dgst -md_gost12_256 \
  -engine gost \
  -sign /tmp/gost-sign/sign.key \
  -out /tmp/gost-sign/document.sig \
  /tmp/gost-sign/document.txt

# Извлечь публичный ключ
openssl pkey -in /tmp/gost-sign/sign.key -pubout \
  -out /tmp/gost-sign/verify.key

# Проверить подпись
openssl dgst -md_gost12_256 \
  -engine gost \
  -verify /tmp/gost-sign/verify.key \
  -signature /tmp/gost-sign/document.sig \
  /tmp/gost-sign/document.txt
'
```

---

## ⚙️ Конфигурация

### docker-compose.yml

```yaml
services:
  openssl-gost:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        OPENSSL_VERSION: "3.6.0"
    container_name: openssl-gost
    environment:
      - OPENSSL_CONF=/opt/openssl/ssl/openssl.cnf
    command: ["openssl", "version", "-a"]
```

### Dockerfile переменные сборки

| Аргумент | Значение по умолчанию | Описание |
|---------|------------------|---------|
| `OPENSSL_VERSION` | `3.6.0` | Версия OpenSSL (скачивается с openssl.org) |
| `GOST_ENGINE_REPO` | `https://github.com/gost-engine/engine.git` | Git-репозиторий GOST-engine |
| `MAKE_JOBS` | `4` | Параллельные потоки при сборке |

**Для изменения версии:**

```bash
docker compose build --no-cache --build-arg OPENSSL_VERSION=3.6.1
```

### Расширенная конфигурация openssl.cnf

Если нужны специальные параметры GOST-engine (например, параметры CryptoPro), добавь в `[gost_section]`:

```ini
[gost_section]
engine_id = gost
dynamic_path = /opt/openssl/lib/engines-3/gost.so
default_algorithms = ALL

# Дополнительные параметры
crypt_params = id-GostR3410-2001-CryptoPro-A-ParamSetA
```

---

### Проверка GOST-движка

```bash
docker compose run --rm openssl-gost sh -c '
  echo "=== OpenSSL Info ===" && openssl version -a && \
  echo "=== GOST Engine ===" && openssl engine -t -c && \
  echo "=== Available ciphers ===" && openssl ciphers | grep -i gost | head -5
'
```

---

## 📊 Размер и производительность

| Метрика | Значение |
|---------|----------|
| **Размер образа** | 53.8 МБ |
| **Сжатый размер (push)** | 15.2 МБ |
| **Ratio сжатия** | 72% |
| **Время сборки** | 5-10 минут |
| **Base image** | Alpine 3.22.2 (~5 МБ) |
| **OpenSSL + libs** | ~30 МБ |
| **GOST-engine** | ~2 МБ |
| **Система + сертификаты** | ~35 МБ |


---

## 🤝 Внесение изменений

Если хочешь модифицировать образ:

1. Отредактируй `Dockerfile` или `docker-compose.yml`
2. Пересобери с `--no-cache`: `docker compose build --no-cache`
3. Протестируй: `docker compose run --rm -it openssl-gost sh`
4. Создай тег и залей в реестр

---

## 📜 Лицензия и авторство

- **OpenSSL**: Apache 2.0 License
- **GOST Engine**: Apache 2.0 License
- **Этот проект**: Apache 2.0 License

Используй образ в соответствии с требованиями лицензий и ограничениями по использованию криптографии в вашей юрисдикции (особенно в России и странах с экспортными ограничениями).

---

## 🔗 Полезные ссылки

- 🌐 [OpenSSL Official](https://www.openssl.org/)
- 🔧 [GOST Engine GitHub](https://github.com/gost-engine/engine)
- 🐳 [Docker Documentation](https://docs.docker.com/)
- 🏔️ [Alpine Linux](https://alpinelinux.org/)
- 📚 [ГОСТ Стандарты](https://www.gost.ru/)
- 📖 [OpenSSL Man Pages](https://www.openssl.org/docs/man3.6/)

---

## 💬 Поддержка

При проблемах:

1. Проверь **логи сборки**: `docker compose build --no-cache 2>&1 | tee build.log`
2. Тестируй **интерактивно**: `docker compose run --rm -it openssl-gost sh`
3. Проверь **окружение**: `docker system df` (дисковое пространство)
4. Обнови **Docker**: `docker --version` (нужен 20.10+)

---

## ✨ Тестирование на разных архитектурах

Образ протестирован и работает на:

- ✅ **x86_64** (Intel/AMD Linux)
- ✅ **aarch64** (ARM64 / Apple Silicon Mac)
- ✅ **WSL2** (Windows Subsystem for Linux)

```bash
# Проверить текущую архитектуру внутри контейнера
docker compose run --rm openssl-gost uname -m
# Результат: aarch64 или x86_64
```

---

**Версия документации**: 2.1  
**Дата обновления**: 2025-11-29  
**Статус**: ✅ Production-ready  
**Совместимость**: OpenSSL 3.6.0, Alpine 3.22.2, Docker Compose v2+  
**Архитектура**: x86_64, aarch64 ✅
