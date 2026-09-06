# СИМПАС · подключение к VPN

Единый способ подключения для всех агентов. Один контракт, два профиля, одна
команда на установку.

Российский трафик через туннель **не идёт**: зоны `.ru/.su/.рф`, российские
сервисы на других доменах и все российские IP-диапазоны обслуживаются напрямую.
Госуслуги, MAX, банковские приложения и российские сайты работают так, как будто
VPN выключен. Всё остальное идёт через сервер.

---

## 1. Контракт

Всё подключение описывается пятью переменными окружения. Больше знать не нужно.

| Переменная         | Обязательна | Значение по умолчанию | Что это                                  |
|--------------------|-------------|-----------------------|------------------------------------------|
| `VPN_HOST`         | да          | —                     | адрес сервера (IP или домен)             |
| `VPN_PORT`         | да          | —                     | UDP-порт hysteria2                       |
| `VPN_PASSWORD`     | да          | —                     | пароль hysteria2                         |
| `VPN_SNI`          | нет         | `www.bing.com`        | имя в TLS SNI                            |
| `VPN_INSECURE`     | нет         | `true`                | сертификат самоподписанный               |

Дополнительно, только для профиля `agent`:

| Переменная         | По умолчанию | Что это                             |
|--------------------|--------------|-------------------------------------|
| `VPN_LISTEN_ADDR`  | `127.0.0.1`  | адрес локального прокси             |
| `VPN_LISTEN_PORT`  | `11080`      | порт локального прокси              |
| `VPN_PROFILE`      | `agent`      | `agent` или `karing`                |
| `VPN_OUT`          | `./vpn-config.json` | куда записать конфиг         |

Значения `VPN_HOST`, `VPN_PORT`, `VPN_PASSWORD` выдаёт владелец сервера. Они
одинаковы для всех агентов — см. раздел «Безопасность».

---

## 2. Какой профиль брать

| | `agent` | `karing` |
|---|---|---|
| Кому | скрипты, боты, CI, серверы, контейнеры | людям на ноутбуке и телефоне |
| Как работает | локальный SOCKS5/HTTP-прокси | системный VPN-туннель (TUN) |
| Права | обычный пользователь | администратор / разрешение на VPN |
| Область действия | только процессы, которым указали прокси | весь трафик устройства |
| Клиент | `sing-box` | Karing |

Правило простое: **человеку — `karing`, программе — `agent`.** Профиль `agent`
не трогает маршрутизацию машины, поэтому его безопасно поднимать на сервере, где
уже что-то работает.

---

## 3. Профиль `agent` — Linux и macOS

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
export VPN_PASSWORD='пароль'

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

## 4. Профиль `agent` — Windows

```powershell
$env:VPN_HOST='адрес'; $env:VPN_PORT='порт'; $env:VPN_PASSWORD='пароль'
irm https://raw.githubusercontent.com/compas-psy/vpn/claude/vpn-server-karing-config-4hjw9e/agent/bootstrap.ps1 | iex
sing-box run -c .\vpn-config.json
```

Использование:

```powershell
$env:ALL_PROXY  = 'socks5h://127.0.0.1:11080'
$env:HTTPS_PROXY = 'http://127.0.0.1:11080'
```

---

## 5. Профиль `agent` — Docker

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

## 6. Профиль `karing` — человеку

1. Установить Karing: <https://karing.app> (Windows, macOS, iOS, Android).
2. Собрать конфиг тем же bootstrap с `VPN_PROFILE=karing`:

   ```powershell
   $env:VPN_HOST='адрес'; $env:VPN_PORT='порт'; $env:VPN_PASSWORD='пароль'
   $env:VPN_PROFILE='karing'
   irm https://raw.githubusercontent.com/compas-psy/vpn/claude/vpn-server-karing-config-4hjw9e/agent/bootstrap.ps1 | iex
   ```

3. Karing → **Профили** → **+** → **Импорт из файла** → выбрать `vpn-config.json`.
4. Включить VPN.

Файл один и тот же для всех платформ. На телефон его достаточно переслать себе
любым способом и сохранить в «Файлы».

---

## 7. Что идёт мимо туннеля

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

## 8. Проверка

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

## 9. Если не работает

| Симптом | Причина | Что делать |
|---|---|---|
| `DNS_PROBE_FINISHED_NO_INTERNET` на российском сайте | Chrome резолвит через свой Secure DNS мимо туннеля | `chrome://settings/security` → выключить «Использовать безопасный DNS», затем `ipconfig /flushdns` |
| Российский сайт открывается через сервер | клиент резолвит имя сам | использовать `socks5h://`, не `socks5://` |
| MAX висит на «Ожидание сети» | трафик MAX ушёл в туннель | обновить конфиг: в нём есть правила по процессу и пакету |
| `connection refused` на 11080 | sing-box не запущен | `sing-box run -c vpn-config.json`, смотреть вывод |
| Конфиг не читается клиентом | версия sing-box старше 1.11 | обновить: профиль рассчитан на 1.11–1.13 |
| Всё встало разом | сервер или порт недоступны | проверить UDP-порт: `nc -zvu VPN_HOST VPN_PORT` |

---

## 10. Безопасность

**Пароль общий для всех агентов.** Сейчас на сервере один пароль hysteria2, а не
отдельный на каждого. Из этого следует:

- отозвать доступ одного агента, не задев остальных, нельзя — смена пароля
  отключает всех сразу;
- пароль нельзя публиковать: ни в публичном репозитории, ни в CI-логах, ни в
  общих чатах;
- собранный `vpn-config.json` содержит пароль. Права `600`, в git не коммитить —
  корневой `.gitignore` уже блокирует `*-filled.json` и `*-real.json`, но файл с
  произвольным именем он не поймает.

Если агентов больше двух-трёх, стоит перейти на индивидуальные учётные данные:
hysteria2 умеет внешнюю аутентификацию (`auth.type: command`), и тогда у каждого
агента свой токен, который отзывается отдельно. Это изменение конфигурации
работающего сервера, поэтому делается отдельно и осознанно.

Профиль `agent` слушает `127.0.0.1` намеренно. Меняя `VPN_LISTEN_ADDR` на
`0.0.0.0`, вы открываете SOCKS-прокси без пароля всем, кто дотянется до порта.

---

## 11. Что где лежит

| Путь | Что это |
|---|---|
| `agent/singbox-agent-proxy.json` | шаблон профиля `agent` |
| `agent/bootstrap.sh` / `bootstrap.ps1` | сборка конфига из переменных окружения |
| `karing/karing-hysteria2-ru-direct.json` | шаблон профиля `karing` |
| `karing/README.md` | подробности по клиентскому конфигу |
| `server/` | обезличенный слепок конфигурации сервера |
