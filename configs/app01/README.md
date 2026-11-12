# APP01 — Ubuntu Server в домене, Docker, GLPI, портал, мониторинг, Zabbix

Копии конфигурации сервера приложений APP01 (Ubuntu Server 26.04.1 LTS, 192.168.100.40). Подробности этапов и проверок — в [журнале](../../docs/journal.md).

| Папка на сервере | Здесь | Что это |
| --- | --- | --- |
| `/opt/glpi` | [glpi/](glpi) | GLPI 12.0.1 и MariaDB 11.4 в Docker Compose. Корень Kurogane-Root-CA передаётся в контейнер для LDAPS (`ldap.conf`, `TLS_REQCERT demand`), `apache/remoteip.conf` возвращает реальный IP клиента за обратным прокси |
| `/opt/intranet` | [intranet/](intranet) | Портал сотрудников: статический сайт в контейнере nginx, порты наружу не опубликованы — доступ только через обратный прокси |
| `/opt/monitoring` | [monitoring/](monitoring) | Prometheus 3.13.5, Alertmanager 0.31.1, node_exporter 1.11.1, Grafana 13.3.0. Цели и правила тревог — `prometheus/`, маршрут писем через Exchange — `alertmanager/alertmanager.yml`, источник данных Grafana — `grafana/provisioning` |
| `/opt/zabbix` | [zabbix/](zabbix) | Zabbix 8.0.0 LTS (сервер и веб, образы `alpine-8.0.0`) и PostgreSQL 17.11. Порт 10051 для агентов опубликован только на 192.168.100.40; в контейнер сервера передаются хранилище сертификатов (проверка STARTTLS при отправке почты) и `/etc/localtime` (время в письмах). Выгрузка своих шаблонов — `templates/kurogane-templates.yaml` |
| `/etc/zabbix/zabbix_agent2.d` | [zabbix/agent/](zabbix/agent) | Свои параметры агента 2 на APP01 (`kurogane.conf`): пассивные проверки только из подсети Docker-сети `zabbix`, активные — на 192.168.100.40, метаданные `linux` |
| `/opt/proxy` | [proxy/](proxy) | Обратный прокси nginx: HTTP → HTTPS, отказ на запросы по IP и неизвестным именам; `helpdesk`, `intranet`, `grafana` и `zabbix.kurogane-digital.ru` → свои контейнеры (для Grafana — WebSocket) |
| `/etc/...` | [system/](system) | `sssd.conf` (вход только для группы GG_IT), `kurogane.sources` (chrony на DC01 и DC02), `gg-it` (sudo для GG_IT), `daemon.json` (ротация логов Docker), netplan со статическим адресом |

## Мониторинг: как устроен

- Prometheus опрашивает windows_exporter на DC01, DC02, FS01 и EX01 (TCP 9182) и node_exporter самого APP01 каждые 30 секунд. Метка `role` задаёт, какие службы проверять на сервере, а `instance` переписывается в короткое имя (`dc01`).
- windows_exporter ставится на серверы GPO `C_SRV_Monitoring` сценарием [Install-WindowsExporter.ps1](../../scripts/monitoring/Install-WindowsExporter.ps1); правило брандмауэра в той же GPO открывает порт только для 192.168.100.40.
- Наружу через прокси видна только Grafana. Prometheus и Alertmanager доступны лишь внутри сети Docker `monitoring`.
- node_exporter работает в сети хоста, но слушает только адрес моста Docker 172.17.0.1, поэтому из сети лабы недоступен.
- Alertmanager отправляет письма через EX01: порт 587, STARTTLS обязателен, вход под служебной учёткой. Пароль лежит в отдельном файле `alertmanager/smtp_password` (владелец 65534 — пользователь контейнера, права 400) и подключается через `smtp_auth_password_file`.
- Кластерный режим Alertmanager выключен (`--cluster.listen-address=`): экземпляр один.
- После правки `prometheus.yml` или правил: `curl -X POST http://<IP контейнера prometheus>:9090/-/reload` (включено флагом `--web.enable-lifecycle`).

## Zabbix: как устроен

- Сервер Zabbix стартует только после того, как PostgreSQL ответил на `pg_isready` (healthcheck и `depends_on: condition: service_healthy`). Наружу через прокси виден только веб-интерфейс; база доступна лишь внутри сети Docker `zabbix`.
- На серверы Windows агент 2 ставит GPO `C_SRV_Monitoring` сценарием [Install-ZabbixAgent.ps1](../../scripts/monitoring/Install-ZabbixAgent.ps1). Сценарий определяет роль сервера и пишет её в `HostMetadata` (`windows-dc`, `windows-fs`, `windows-exchange`); правило брандмауэра той же GPO открывает TCP 10050 только для APP01.
- Действия авторегистрации по метаданным создают узел, добавляют его в группы (Kurogane/Windows плюс группа роли) и подключают шаблоны: всем — Kurogane Windows server, контроллерам домена — ещё Kurogane AD DC, Exchange — пассивный Microsoft Exchange Server 2016 by Zabbix agent (активный конфликтует с Windows по ключу `zabbix[host,active_agent,available]`).
- **Kurogane Windows server** — обёртка над стандартным Windows by Zabbix agent active: переопределены `{$AGENT.NODATA_TIMEOUT}` = 5m (по умолчанию 30m) и `{$SERVICE.NAME.NOT_MATCHES}` (+ `InventorySvc`, которую Server 2025 останавливает сам). Стандартный шаблон не изменён, поэтому правки переживут обновление Zabbix.
- **Kurogane AD DC** — проверки, которых нет в стандартном шаблоне: SOA зоны домена и SRV-запись `_ldap._tcp.dc._msdcs`, LDAP 389, Kerberos 88, расхождение времени (счётчик в микросекундах пересчитан в секунды), очередь репликации AD. Пороги — в макросах `{$DC.TIME.OFFSET.MAX}` и `{$DC.REPL.PENDING.MAX}`.
- Импорт шаблонов: Data collection → Templates → Import → `kurogane-templates.yaml`.
- Почта: способ оповещения Email через EX01 (587, STARTTLS с проверкой сертификата и имени, служебная учётка), действие Report problems to Zabbix administrators с условием Trigger severity ≥ Average.

## Чего здесь нет

Настоящие `.env` с паролями баз GLPI и Zabbix и администратора Grafana (вместо них `.env.example`), файл `smtp_password`, закрытые ключи и сертификаты nginx (`/opt/proxy/certs`), данные контейнеров (тома Docker).

Сети: стеки используют внешнюю сеть `proxy`, общую с nginx. Её создают один раз: `docker network create proxy`.
