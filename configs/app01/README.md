# APP01 — Ubuntu Server в домене, Docker, GLPI

Копии конфигурации сервера приложений APP01 (Ubuntu Server 26.04.1 LTS, 192.168.100.40). Подробности этапов и проверок — в [журнале](../../docs/journal.md).

| Папка на сервере | Здесь | Что это |
| --- | --- | --- |
| `/opt/glpi` | [glpi/](glpi) | GLPI 12.0.1 и MariaDB 11.4 в Docker Compose. Корень Kurogane-Root-CA передаётся в контейнер для LDAPS (`ldap.conf`, `TLS_REQCERT demand`), `apache/remoteip.conf` возвращает реальный IP клиента за обратным прокси |
| `/opt/proxy` | [proxy/](proxy) | Обратный прокси nginx: HTTP → HTTPS, отказ на запросы по IP и неизвестным именам, `helpdesk.kurogane-digital.ru` → контейнер GLPI |
| `/etc/...` | [system/](system) | `sssd.conf` (вход только для группы GG_IT), `kurogane.sources` (chrony на DC01 и DC02), `gg-it` (sudo для GG_IT), `daemon.json` (ротация логов Docker), netplan со статическим адресом |

Не входят в репозиторий: настоящий `.env` с паролем базы (вместо него [.env.example](glpi/.env.example)), закрытый ключ и сертификат nginx (`/opt/proxy/certs`), данные контейнеров (тома Docker).

Сети: стек GLPI использует свою сеть для базы и внешнюю сеть `proxy`, общую с nginx. Её создают один раз: `docker network create proxy`.
