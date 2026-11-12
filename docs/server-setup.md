# Настройка сервера devops-vm

## Исходная система

Практическая работа выполнена на Ubuntu Server 26.10 в VirtualBox 7.2.22. Имя виртуальной машины — ubunta, имя гостевой системы после настройки — devops-vm. Исходный снимок состояния — 01-clean-install.

## Сеть

| Интерфейс | Режим | Адрес | Назначение |
| --- | --- | --- | --- |
| enp0s3 | NAT | 10.0.2.15/24 | Доступ к репозиториям пакетов |
| enp0s8 | Host-only | 192.168.56.101/24 | Доступ с хоста |

Для NAT настроен проброс TCP с 127.0.0.1:2222 хоста на порт 2222 гостя. AmneziaVPN на хосте перехватывает подсеть 192.168.56.0/24; после отключения VPN доступ по Host-only следует повторно проверить.

## Пользователи и ключи

Пользователь devops входит в группу sudo. Ключ ED25519 находится на хосте в ~/.ssh/devops_vm; открытый ключ добавлен в /home/devops/.ssh/authorized_keys. Права на каталог .ssh — 700, на authorized_keys — 600. Закрытый ключ не копируется на сервер и не включается в репозиторий.

## SSH

Файл config/99-hardening.conf репозитория установлен в /etc/ssh/sshd_config.d/99-hardening.conf. Используется порт 2222, вход только по ключу для devops, запрет входа root и пароля, MaxAuthTries 3 и LoginGraceTime 30. Сокет ssh.socket отключён; работает ssh.service. Перед перезапуском выполнена проверка sudo sshd -t. Эффективные значения проверены через sudo sshd -T.

На хосте в ~/.ssh/config созданы алиасы devops и devops.local с адресом 127.0.0.1, портом 2222, пользователем devops и ключом ~/.ssh/devops_vm. Оба алиаса проверены командой ssh. Имя devops.local здесь обрабатывается клиентом SSH, а не системным DNS.

## Межсетевой экран

UFW активен: входящие соединения по умолчанию запрещены, исходящие разрешены. Для 2222/tcp действует LIMIT; 80/tcp и 443/tcp разрешены. Уровень журналирования — medium. Проверка: sudo ufw status verbose.

## Локальные имена

В гостевой системе запись 127.0.1.1 связывает devops-vm.devops.local и devops-vm. Команда hostname -f возвращает devops-vm.devops.local. На хосте имя devops.local должно указывать на 192.168.56.101 после устранения конфликта с VPN.

## Проверка и восстановление

Скрипт scripts/audit.sh проверяет SSH, UFW и обычные учётные записи. Запуск: sudo -v, затем bash scripts/audit.sh. Код возврата 0 означает успешное прохождение всех проверок.

Созданы три снимка: 01-clean-install, 02-keys-configured и 03-ssh-hardened. Снимок 02 сделан после настройки SSH и UFW, поэтому уже содержит защиту SSH. Снимок 03 дополнительно содержит локальный репозиторий с документацией и скриптом проверки. Для восстановления исходного состояния использовать снимок 01-clean-install.

## 8. Веб-сервер

Пакет `nginx` обслуживает ресурс `devops.local`. Конфигурация находится в `/etc/nginx/sites-available/devops-site`; ссылка в `/etc/nginx/sites-enabled/devops-site` активирует ресурс. Стандартный ресурс отключён удалением ссылки `sites-enabled/default`. После изменения конфигурации выполнять `sudo nginx -t && sudo systemctl reload nginx`.

Каталог публикации — `/var/www/devops-site`, владелец `devops:devops`, права каталога 755, файлов 644. Рабочие процессы Nginx выполняются от имени `www-data` и имеют право читать содержимое, но не изменять его. `site/index.html` и `site/404.html` доставляются из репозитория сценарием `scripts/deploy.sh` через `rsync --delete --chmod=D755,F644`.

HTTP на порту 80 перенаправляется кодом 301 на HTTPS. TLS работает на порту 443 с TLS 1.2 и 1.3. Самоподписанный сертификат `/etc/ssl/certs/devops.crt` имеет права 644 и SAN `DNS:devops.local`; закрытый ключ `/etc/ssl/private/devops.key` принадлежит `root:root` и имеет права 600. Ключ не копируется на хост и не включается в Git. Срок сертификата — 365 дней от выпуска. Команда выпуска:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' \
  -addext 'subjectAltName=DNS:devops.local'
```

Для клиента сертификат копируется по SSH и передаётся `curl --cacert`. Прямой доступ по Host-only ограничен AmneziaVPN. На текущем хосте NAT пробрасывает порты 80 и 443 на одноимённые порты гостя; также сохранены вспомогательные пробросы 8080 и 8443. В сценарии `curl --resolve devops.local:443:127.0.0.1` задаёт адрес без изменения системного DNS. Для браузера в Windows hosts требуется запись `127.0.0.1 devops.local`. Это обеспечивает доступ по адресу задания при включённом VPN, хотя маршрут Host-only по-прежнему не используется.

## 9. Контейнеризация

Docker Engine 29.9.3 и плагин Docker Compose 5.7.1 установлены из официального репозитория Docker для Ubuntu 26.10 (`stonking`). Ключ репозитория находится в `/etc/apt/keyrings/docker.asc`, описание — в `/etc/apt/sources.list.d/docker.sources`. Установлены `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` и `docker-compose-plugin`. Служба `docker` включена и активна. После установки учётная запись `devops` добавлена в группу `docker`; новую группу применяет следующая SSH-сессия. Членство в группе `docker` фактически даёт полномочия root, поэтому посторонние учётные записи в неё не добавляются. Проверка: `docker version`, `docker compose version`, `docker run --rm hello-world`.

Проект находится в `/home/devops/app`. Исходники — в каталоге `app/` репозитория; доставка выполняется с хоста командой `rsync -avz --delete --exclude=.env --chmod=D755,F644 app/ devops:app/`. Сначала следует добавить `--dry-run`. Исключение `.env` обязательно при `--delete`: секрет существует только в ВМ. В репозитории имеются лишь `.env.example` с заглушкой и правило `app/.env` в `.gitignore`; `.dockerignore` также исключает `.env` из контекста сборки. Файл `/home/devops/app/.env` принадлежит `devops:devops`, имеет права 600; пароль для PostgreSQL создаётся `openssl rand -hex 16` на ВМ. Его значение не выводится в журнал и не копируется на хост.

`app/Dockerfile` использует `python:3.12-slim`, отдельно копирует зависимости до `app.py`, устанавливает их и запускает Gunicorn от непривилегированного пользователя `app`. Собрать образ: `cd ~/app && docker build -t devops-app:1.0 .`. Файл `app/docker-compose.yml` определяет сервисы `app` и `db`, сеть `app_backend`, именованный том `app_db_data`, образ `postgres:16-alpine` и проверку готовности `pg_isready`. Приложение подключается к БД по имени сервиса `db` в DNS сети Compose. `depends_on: condition: service_healthy` задерживает запуск приложения до готовности БД.

Запуск: `cd ~/app && docker compose up -d --build`; проверка: `docker compose ps`, `docker compose exec app id`, `docker compose exec app getent hosts db`, `ss -tln`. Порт приложения опубликован только на `127.0.0.1:5000`; порт 5432 на хосте не опубликован. Для остановки с сохранением данных используйте `docker compose down`, затем `docker compose up -d`. Команда `docker compose down -v` удаляет том с базой данных и применяется только для учебного сброса данных.

Конфигурация ресурса хранится в `config/nginx-devops-site.conf` и устанавливается в `/etc/nginx/sites-available/devops-site`. В блоке HTTPS `location /app/` передаёт запросы на `http://127.0.0.1:5000/`, а завершающий `/` в `proxy_pass` заменяет префикс `/app/` на `/`. Заголовки `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto` передают приложению сведения об исходном запросе. Статический ресурс по `/` сохранён. Перед применением выполняйте `sudo nginx -t && sudo systemctl reload nginx`. С хоста проверяйте `curl --cacert ~/devops.crt https://devops.local/app/` и `/app/health`, а также `curl --cacert ~/devops.crt -I https://devops.local/`.

При 502 проверьте `docker compose ps`, локальный ответ `curl http://127.0.0.1:5000/health`, затем `/var/log/nginx/devops-site.error.log`. Запись `connect() failed (111: Connection refused) while connecting to upstream` означает, что Nginx не смог соединиться с приложением. Сценарий `scripts/audit.sh` дополнительно проверяет службу Docker, здоровье БД, привязку порта 5000 только к loopback, отсутствие публикации 5432 и права `.env`. Для полной проверки запускайте сценарий с полномочиями sudo; код 0 означает отсутствие ошибок. Итоговое состояние сохраняется снимком VirtualBox `05-docker-compose`.
