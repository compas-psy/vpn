# СИМПАС · подключение к VPN

Единый способ подключения для всех агентов. Один контракт, два профиля, одна
команда на установку. У каждого агента своя учётная запись, которая отзывается
отдельно от остальных.

Российский трафик через туннель **не идёт**: зоны `.ru/.su/.рф`, российские
сервисы на других доменах и все российские IP-диапазоны обслуживаются напрямую.
Госуслуги, MAX, банковские приложения и российские сайты работают так, как будто
VPN выключен. Всё остальное идёт через сервер.

---

## 1. Контракт

Всё подключение описывается пятью переменными окружения.

| Переменная         | Обязательна | По умолчанию   | Что это                                  |
|--------------------|-------------|----------------|------------------------------------------|
| `VPN_HOST`         | да          | —              | адрес сервера (IP или домен)             |
| `VPN_PORT`         | да          | —              | UDP-порт hysteria2                       |
| `VPN_PASSWORD`     | да          | —              | учётные данные агента: `имя:токен`       |
| `VPN_SNI`          | нет         | `www.bing.com` | имя в TLS SNI                            |
| `VPN_INSECURE`     | нет         | `true`         | сертификат самоподписанный               |

Дополнительно, только для профиля `agent`:

| Переменная         | По умолчанию        | Что это                        |
|--------------------|---------------------|--------------------------------|
| `VPN_LISTEN_ADDR`  | `127.0.0.1`         | адрес локального прокси        |
| `VPN_LISTEN_PORT`  | `11080`             | порт локального прокси         |
| `VPN_PROFILE`      | `agent`             | `agent` или `karing`           |
| `VPN_OUT`          | `./vpn-config.json` | куда записать конфиг           |

`VPN_PASSWORD` у каждого агента свой и выглядит как `claude-web:3f8a…`. Общего
пароля на всех больше нет.

---

## 2. Выдача и отзыв доступа

Управляет владелец сервера, одной командой по SSH:

```sh
ssh root@СЕРВЕР hysteria-agent add claude-web
# VPN_PASSWORD=claude-web:3f8a9c...
```

| Команда | Что делает |
|---|---|
| `hysteria-agent add <имя>` | выдать доступ; повторный вызов **перевыпускает** токен |
| `hysteria-agent list` | показать всех агентов и их состояние (токены не печатает) |
| `hysteria-agent revoke <имя>` | отозвать доступ, оставив запись в журнале |
| `hysteria-agent enable <имя>` | вернуть отозванный доступ |
| `hysteria-agent legacy status` | принимается ли ещё старый общий пароль |
| `hysteria-agent legacy off` | перестать принимать общий пароль |

Изменения действуют **сразу**: hysteria спрашивает разрешение у внешнего хука на
каждой аутентификации, и тот перечитывает базу заново. Перезапускать сервис не
нужно, живые сессии других агентов не рвутся.

Имя агента попадает в системный журнал сервера при каждом подключении:

```sh
ssh root@СЕРВЕР 'journalctl -t hysteria-auth -n 50'
```

### Миграция со старого пароля

Старый общий пароль пока принимается — чтобы никого не отключить на переходе.
Порядок такой:

1. Выдать каждому агенту свою учётку (`hysteria-agent add …`).
2. Проверить, что все переехали: `journalctl -t hysteria-auth | grep legacy`.
3. Выключить общий пароль: `hysteria-agent legacy off`.

После третьего шага доступ есть только у тех, у кого именная учётка.

---

## 3. Какой профиль брать

| | `agent` | `karing` |
|---|---|---|
| Кому | скрипты, боты, CI, серверы, контейнеры | людям на ноутбуке и телефоне |
| Как работает | локальный SOCKS5/HTTP-прокси | системный VPN-туннель (TUN) |
| Права | обычный пользователь | администратор / разрешение на VPN |
| Область действия | только процессы, которым указали прокси | весь трафик устройства |
| Клиент | `sing-box` | Karing |

Человеку — `karing`, программе — `agent`. Профиль `agent` не трогает
маршрутизацию машины, поэтому его безопасно поднимать на сервере, где уже
что-то работает.

---

## 4. Профиль `agent` — Linux и macOS

**Установить sing-box** (нужна версия 1.11 или новее):

```sh
# Debian / Ubuntu
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

# RHEL / AlmaLinux / Fedora
bash <(curl -fsSL https://sing-box.app/rpm-install.sh)

# macOS
brew install sing-box

# всё остальное — бинарник со страницы релизов
# https://github.com/SagerNet/sing-box/releases
```

**Собрать конфиг:**

```sh
export VPN_HOST='адрес'
export VPN_PORT='порт'
export VPN_PASSWORD='имя:токен'

curl -fsSL https://raw.githubusercontent.com/compas-psy/vpn/claude/vpn-server-karing-config-4hjw9e/agent/bootstrap.sh | sh
```

Получится `./vpn-config.json` с правами `600`.

**Запустить:**

```sh
sing-box run -c ./vpn-config.json
```

**Пользоваться:**

```sh
export ALL_PROXY=socks5h://127.0.0.1:11080
export HTTPS_PROXY=http://127.0.0.1:11080
export HTTP_PROXY=http://127.0.0.1:11080
export NO_PROXY=localhost,127.0.0.1
```

Схема `socks5h`, а не `socks5`: буква `h` означает, что имя резолвит sing-box, а
не клиент. Без неё разделение российского и остального трафика ломается — клиент
сам сходит к своему DNS и придёт уже с готовым IP.

**Как сервис (systemd):**

```sh
sudo mkdir -p /etc/sing-box
sudo cp vpn-config.json /etc/sing-box/config.json
sudo chmod 600 /etc/sing-box/config.json
sudo tee /etc/systemd/system/sing-box-agent.service >/dev/null <<'EOF'
[Unit]
Description=sing-box agent proxy
After=network.target

[Service]
ExecStart=/usr/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5
DynamicUser=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now sing-box-agent
```

---

## 5. Профиль `agent` — Windows

```powershell
$env:VPN_HOST='адрес'; $env:VPN_PORT='порт'; $env:VPN_PASSWORD='имя:токен'
irm https://raw.githubusercontent.com/compas-psy/vpn/claude/vpn-server-karing-config-4hjw9e/agent/bootstrap.ps1 | iex
sing-box run -c .\vpn-config.json
```

Использование:

```powershell
$env:ALL_PROXY   = 'socks5h://127.0.0.1:11080'
$env:HTTPS_PROXY = 'http://127.0.0.1:11080'
```

---

## 6. Профиль `agent` — Docker

```sh
docker run -d --name vpn-agent --restart unless-stopped \
  -p 127.0.0.1:11080:11080 \
  -v "$PWD/vpn-config.json:/etc/sing-box/config.json:ro" \
  ghcr.io/sagernet/sing-box \
  run -c /etc/sing-box/config.json
```

Чтобы прокси был виден другим контейнерам, соберите конфиг с
`VPN_LISTEN_ADDR=0.0.0.0`, подключите контейнеры в общую docker-сеть и ходите на
`socks5h://vpn-agent:11080`. Наружу порт при этом **не публикуйте**: открытый
SOCKS без аутентификации — это открытый релей.

---

## 7. Профиль `karing` — человеку

1. Установить Karing: <https://karing.app> (Windows, macOS, iOS, Android).
2. Собрать конфиг тем же bootstrap с `VPN_PROFILE=karing`:

   ```powershell
   $env:VPN_HOST='адрес'; $env:VPN_PORT='порт'; $env:VPN_PASSWORD='имя:токен'
   $env:VPN_PROFILE='karing'
   irm https://raw.githubusercontent.com/compas-psy/vpn/claude/vpn-server-karing-config-4hjw9e/agent/bootstrap.ps1 | iex
   ```

3. Karing → **Профили** → **+** → **Импорт из файла** → выбрать `vpn-config.json`.
4. Включить VPN.

Файл один и тот же для всех платформ. На телефон его достаточно переслать себе
любым способом и сохранить в «Файлы».

---

## 8. Что идёт мимо туннеля

Правила проверяются сверху вниз, первое совпавшее выигрывает.

| Что | Куда |
|---|---|
| приватные адреса (`10.*`, `192.168.*`, …) | напрямую |
| MAX — по имени процесса и Android-пакету `ru.oneme.app` | напрямую |
| `.ru`, `.su`, `.рф`, `.moscow`, `.tatar`, `.дети` | напрямую |
| российские сервисы не в зоне `.ru`: VK, MAX, Сбер, Т-Банк, Альфа, ВТБ, НСПК/СБП, Ozon, WB, Авито, Яндекс, Кинопоиск, 2ГИС, habr | напрямую |
| geosite `category-ru` — общий список российских доменов | напрямую |
| geoip `ru` — ~5000 российских IP-диапазонов | напрямую |
| всё остальное | через сервер |

Правило по geoip нужно отдельно: банковские приложения и MAX часто ходят на IP
без доменного имени, и опознать их можно только по адресу.

DNS разделён так же. Российские имена резолвит Яндекс DNS напрямую — иначе банк
получил бы зарубежный адрес CDN и мог отказать. Остальное резолвится через
Cloudflare DoH внутри туннеля, так что провайдер не видит, что вы открываете.

Списки geosite и geoip тянутся из
[KaringX/karing-ruleset](https://github.com/KaringX/karing-ruleset) через туннель
раз в неделю. Если скачать не удалось, встроенные списки доменов продолжают
работать.

### Добавить своё исключение

Домен, который должен ходить напрямую, дописывается в **два** места конфига: в
`route.rules` и в такой же блок `domain_suffix` внутри `dns.rules`. Только в
маршрутизации мало — имя всё равно уйдёт на зарубежный DNS и вернёт неподходящий
адрес.

---

## 9. Проверка

```sh
# должен показать адрес сервера
curl -x socks5h://127.0.0.1:11080 https://api.ipify.org; echo

# должен показать ваш российский адрес
curl -x socks5h://127.0.0.1:11080 https://api-ip.2ip.ru/; echo

# российский сайт открывается
curl -x socks5h://127.0.0.1:11080 -o /dev/null -w '%{http_code}\n' https://www.gosuslugi.ru/
```

Первая команда возвращает адрес сервера, вторая — ваш собственный. Если обе
показывают одно и то же, разделение не работает: проверьте, что используете
`socks5h`, а не `socks5`.

Для профиля `karing` то же самое проверяется в браузере: 2ip.ru должен показать
российский адрес, зарубежный сервис проверки IP — адрес сервера.

---

## 10. Если не работает

| Симптом | Причина | Что делать |
|---|---|---|
| Не подключается вообще | учётка отозвана или токен перевыпущен | `ssh root@СЕРВЕР hysteria-agent list`, при необходимости `add` заново |
| `DNS_PROBE_FINISHED_NO_INTERNET` на российском сайте | Chrome резолвит через свой Secure DNS мимо туннеля | `chrome://settings/security` → выключить «Использовать безопасный DNS», затем `ipconfig /flushdns` |
| Российский сайт открывается через сервер | клиент резолвит имя сам | использовать `socks5h://`, не `socks5://` |
| MAX висит на «Ожидание сети» | трафик MAX ушёл в туннель | обновить конфиг: в нём есть правила по процессу и пакету |
| `connection refused` на 11080 | sing-box не запущен | `sing-box run -c vpn-config.json`, смотреть вывод |
| Конфиг не читается клиентом | версия sing-box старше 1.11 | обновить: профиль рассчитан на 1.11–1.13 |
| Всё встало разом | сервер или порт недоступны | проверить UDP-порт: `nc -zvu VPN_HOST VPN_PORT` |

Кто и когда подключался — в журнале сервера:

```sh
ssh root@СЕРВЕР 'journalctl -t hysteria-auth -n 100'
```

---

## 11. Безопасность

- Учётные данные индивидуальные. Отзыв одного агента не задевает остальных и
  применяется мгновенно.
- Токен — 48 шестнадцатеричных знаков из системного генератора случайных чисел.
- `VPN_PASSWORD` и собранный `vpn-config.json` содержат токен: права `600`, не
  публиковать, в git не коммитить. Корневой `.gitignore` блокирует
  `*-filled.json` и `*-real.json`, но файл с произвольным именем не поймает.
- Свой токен агент никому не передаёт. Нужен доступ ещё кому-то — выдаётся новая
  учётка, а не копия чужой.
- При подозрении на утечку: `hysteria-agent revoke <имя>`, затем
  `hysteria-agent add <имя>` — новый токен, старый мёртв.
- Профиль `agent` слушает `127.0.0.1` намеренно. Меняя `VPN_LISTEN_ADDR` на
  `0.0.0.0`, вы открываете SOCKS-прокси без пароля всем, кто дотянется до порта.

---

## 12. Что где лежит

| Путь | Что это |
|---|---|
| `agent/singbox-agent-proxy.json` | шаблон профиля `agent` |
| `agent/bootstrap.sh` / `bootstrap.ps1` | сборка конфига из переменных окружения |
| `karing/karing-hysteria2-ru-direct.json` | шаблон профиля `karing` |
| `karing/README.md` | подробности по клиентскому конфигу |
| `.github/scripts/hysteria-authd.sh` | хук аутентификации на сервере |
| `.github/scripts/hysteria-agent.sh` | CLI выдачи и отзыва учёток |
| `.github/scripts/install-agent-auth.sh` | установщик, с бэкапом и откатом |
| `server/` | обезличенный слепок конфигурации сервера |
