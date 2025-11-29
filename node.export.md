# 🟢 Работа с ГОСТ в Node.js

Эта инструкция содержит примеры использования библиотеки `nodejs-gost-crypto` (уже установлена в образе) и экспорта ключей.

## 🛠️ Извлечение ключа КриптоПро через Node.js

В образе установлена утилита `gost-export-cryptopro-key`. Она доступна глобально, поэтому ее не нужно запускать через `node path/to/script.js`.

```bash
# Извлечение из папки контейнера (в формат PEM)
docker compose run --rm -v $(pwd):/work openssl-gost \
  gost-export-cryptopro-key --container /work/0264ce4f.000/ --format PEM --password 12345678 > 0264ce4f.key
```

*Примечание: Если утилита выдает ошибку "Incorrect fp", проверьте целостность файлов контейнера или используйте `get-cpcert` (см. export.md).*

## 💻 Использование в коде (JavaScript)

Библиотека доступна по пути `/usr/local/lib/node_modules/gostcrypto`.

### 1. Вычисление хеша (Стрибог 256)

```bash
docker compose run --rm openssl-gost node -e "
const engine = require('/usr/local/lib/node_modules/gostcrypto/lib/gostEngine.js');
const digest = engine.getGostDigest({name: 'GOST R 34.11', length: 256});
const result = digest.digest('test data');
console.log('Hash:', Buffer.from(result).toString('hex'));
"
```

### 2. Создание CMS подписи (в разработке)

Для полноценной работы с ключами в Node.js рекомендуется использовать библиотеку вместе с загруженными ключами в формате PEM или DER.

```javascript
const gostcrypto = require('gostcrypto');
// Примеры использования доступны в документации библиотеки:
// https://github.com/garex/nodejs-gost-crypto
```

## ✅ Проверка через CLI

```bash
# Проверка доступности алгоритмов
docker compose run --rm openssl-gost node -e "console.log(Object.keys(require('/usr/local/lib/node_modules/gostcrypto/lib/gostEngine.js')))"
```
