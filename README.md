# Ward for PC

**Ward** — Xray-клиент для Windows.
*Ward is an Xray client for Windows.*

## Скачать

Установщик лежит в [Releases](https://github.com/masterRaizer/wardPC/releases/latest):

| Файл | Что это |
|---|---|
| `Ward-1.0.0.exe` | Установщик (рекомендуется) |
| `Ward-1.0.0.msi` | Тот же пакет в виде MSI — для тихой установки или если exe не запускается |
| `SHA256SUMS.txt` | Контрольные суммы |

Проверить файл после скачивания (PowerShell):

```powershell
Get-FileHash .\Ward-1.0.0.exe -Algorithm SHA256
```

| Файл | SHA-256 |
|---|---|
| Ward-1.0.0.exe | `1FBF011F1E80E2A3A35822F7EAAF67ADF8718A5B0A950A58ECE1172150A40EFA` |
| Ward-1.0.0.msi | `FC20685D8A71E6A69D71C528C8E04BDCE4FF4A9CBCA6249D98E063587F75FFBF` |

## Установка

1. Скачай `Ward-1.0.0.exe` и запусти.
2. Пройди мастер установки. Программа ставится в `C:\Program Files\Ward`.

Тихая установка через MSI (от администратора):

```cmd
msiexec /i Ward-1.0.0.msi /qb
```

## Ошибка 1618 «Выполняется другая установка»

Если установка падает с ошибкой **1618 / Another installation is in progress**, а на
самом деле ничего не ставится — виноваты, как правило, **Xbox Gaming Services**.
При каждой загрузке они молча запускают установку `gameinputredist.msi`, она зависает
и держит блокировку Windows Installer, поэтому любые другие MSI не ставятся.

В папке [`install-fix`](install-fix) лежит скрипт, который это чинит:

1. Положи `fix-ward-install.cmd`, `ward-fix.ps1` и `Ward-1.0.0.exe` в **одну папку**.
2. Запусти `fix-ward-install.cmd` и согласись на запрос администратора (UAC).
3. Скрипт:
   - покажет, какой процесс держит установщик;
   - временно отключит автозапуск Gaming Services;
   - если блокировку не снять без перезагрузки — зарегистрирует одноразовую задачу
     и попросит перезагрузиться;
   - после входа в систему сам извлечёт MSI из exe, проверит SHA-256 и установит Ward;
   - вернёт Gaming Services прежний тип запуска, задача удалит сама себя.
4. Не закрывай окно скрипта и не кликай внутри него — клик ставит PowerShell на паузу.

Логи пишутся рядом со скриптом: `ward-diag.txt`, `ward-diag-after-reboot.txt`,
`ward-install.log`.

## Требования

- Windows 10 / 11, x64
