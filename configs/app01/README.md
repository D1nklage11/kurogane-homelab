# APP01 — Ubuntu Server в домене, Docker, GLPI, портал, мониторинг

Копии конфигурации сервера приложений APP01 (Ubuntu Server 26.04.1 LTS, 192.168.100.40). Подробности этапов и проверок — в [журнале](../../docs/journal.md).

| Папка на сервере | Здесь | Что это |
| --- | --- | --- |
| `/opt/glpi` | [glpi/](glpi) | GLPI 12.0.1 и MariaDB 11.4 в Docker Compose. Корень Kurogane-Root-CA передаётся в контейнер для LDAPS (`ldap.conf`, `TLS_REQCERT demand`), `apache/remoteip.conf` возвращает реальный IP клиента за обратным прокси |
| `/opt/intranet` | [intranet/](intranet) | Портал сотрудников: статический сайт в контейнере nginx, порты наружу не опубликованы — доступ только через обратный прокси |
| `/opt/monitoring` | [monitoring/](monitoring) | Prometheus 3.13.5, Alertmanager 0.31.1, node_exporter 1.11.1, Grafana 13.3.0. Цели и правила тревог — `prometheus/`, маршрут писем через Exchange — `alertmanager/alertmanager.yml`, источник данных Grafana — `grafana/provisioning` |
| `/opt/proxy` | [proxy/](proxy) | Обратный прокси nginx: HTTP → HTTPS, отказ на запросы по IP и неизвестным именам; `helpdesk`, `intranet` и `grafana.kurogane-digital.ru` → свои контейнеры (для Grafana — WebSocket) |
| `/etc/...` | [system/](system) | `sssd.conf` (вход только для группы GG_IT), `kurogane.sources` (chrony на DC01 и DC02), `gg-it` (sudo для GG_IT), `daemon.json` (ротация логов Docker), netplan со статическим адресом |

## Мониторинг: как устроен

- Prometheus опрашивает windows_exporter на DC01, DC02, FS01 и EX01 (TCP 9182) и node_exporter самого APP01 каждые 30 секунд. Метка `role` задаёт, какие службы проверять на сервере, а `instance` переписывается в короткое имя (`dc01`).
- windows_exporter ставится на серверы GPO `C_SRV_Monitoring` сценарием [Install-WindowsExporter.ps1](../../scripts/monitoring/Install-WindowsExporter.ps1); правило брандмауэра в той же GPO открывает порт только для 192.168.100.40.
- Наружу через прокси видна только Grafana. Prometheus и Alertmanager доступны лишь внутри сети Docker `monitoring`.
- node_exporter работает в сети хоста, но слушает только адрес моста Docker 172.17.0.1, поэтому из сети лабы недоступен.
- Alertmanager отправляет письма через EX01: порт 587, STARTTLS обязателен, вход под служебной учёткой. Пароль лежит в отдельном файле `alertmanager/smtp_password` (владелец 65534 — пользователь контейнера, права 400) и подключается через `smtp_auth_password_file`.
- Кластерный режим Alertmanager выключен (`--cluster.listen-address=`): экземпляр один.
- После правки `prometheus.yml` или правил: `curl -X POST http://<IP контейнера prometheus>:9090/-/reload` (включено флагом `--web.enable-lifecycle`).

## Чего здесь нет

Настоящие `.env` с паролями базы GLPI и администратора Grafana (вместо них `.env.example`), файл `smtp_password`, закрытые ключи и сертификаты nginx (`/opt/proxy/certs`), данные контейнеров (тома Docker).

Сети: стеки используют внешнюю сеть `proxy`, общую с nginx. Её создают один раз: `docker network create proxy`.
