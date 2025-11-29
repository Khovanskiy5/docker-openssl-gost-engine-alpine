# Минимальная инструкция по работе с ГОСТ сертификатами

Эта инструкция содержит минимальный набор команд для проверки работоспособности извлечения ключей и сертификатов.

## 🛠️ Извлечение из папки контейнера CryptoPro

Используйте папку `0264ce4f.000`. Пароль: `12345678`.

```bash
# Извлечение сертификата и ключа в один файл
# ВАЖНО: используйте $(pwd)/ для указания полного пути к папке на хосте
docker compose run --rm -v $(pwd)/0264ce4f.000:/container openssl-gost \
  get-cpcert /container 12345678 > ./0264ce4f.pem

# Разделение на отдельные файлы (для удобства)
sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' 0264ce4f.pem > 0264ce4f.crt
sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' 0264ce4f.pem > 0264ce4f.key
```

## 🛠️ Извлечение из PFX-контейнера

Используйте файл `cryptocontainer.pfx`. Пароль: `12345678`.
Для ГОСТ PFX обязателен флаг `-legacy`.

```bash
# Извлечение сертификатов (Работает с -legacy)
docker compose run --rm -v $(pwd):/work openssl-gost \
  openssl pkcs12 -in /work/cryptocontainer.pfx -passin pass:12345678 -legacy -nokeys -nodes -out /work/pfx_certs.pem

# Попытка извлечения всего содержимого (включая ключ)
# Внимание: для данного PFX выдаст ошибку "unknown pbe algorithm" из-за ограничений OpenSSL
docker compose run --rm -v $(pwd):/work openssl-gost \
  openssl pkcs12 -in /work/cryptocontainer.pfx -passin pass:12345678 -legacy -nodes -out /work/pfx_full.pem
```

*Примечание: Прямой экспорт закрытого ключа из ГОСТ PFX через OpenSSL часто невозможен из-за проприетарного шифрования CryptoPro (ошибка "unknown pbe algorithm"). Это ограничение OpenSSL, а не обязательно флаг "неэкспортируемости" ключа.*

## ✅ Проверка работоспособности (Подпись и Верификация)

Используем извлеченные файлы `0264ce4f.crt` и `0264ce4f.key`.

```bash
# Создание тестового файла
echo "test data" > test.txt

# Подпись файла (CMS DER)
docker compose run --rm -v $(pwd):/work openssl-gost \
  openssl smime -sign -engine gost -binary -noattr \
  -in /work/test.txt \
  -signer /work/0264ce4f.crt \
  -inkey /work/0264ce4f.key \
  -out /work/test.txt.sig -outform DER

# Проверка подписи
docker compose run --rm -v $(pwd):/work openssl-gost \
  openssl smime -verify -engine gost -inform DER -noverify \
  -certfile /work/0264ce4f.crt \
  -content /work/test.txt \
  -in /work/test.txt.sig
```

**Ожидаемый результат:**
```
test data
Verification successful
```
