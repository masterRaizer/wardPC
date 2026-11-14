---
name: ci-release-packager
description: Сборка проекта в GitHub Actions (.exe, .msi, .apk, portable zip), публикация GitHub Release и комплект сдачи — весь код одним .txt, zip с исходниками и README_RU с инструкцией. Использовать при словах «собери», «выпусти релиз», «одним txt», «архивом», «GitHub Actions», «APK», «exe».
---

# Сборка, релиз и комплект сдачи

## 1. Workflow
Проверь `.github/workflows/*.yml`. Если нужного нет — создай под стек репозитория:
- **C# WinForms (.NET Framework 4.7.2/4.8):** `runs-on: windows-latest`, `microsoft/setup-msbuild`,
  `msbuild <sln> /p:Configuration=Release`, тесты (`vstest`/`dotnet test`), артефакт `bin/Release`.
- **.NET 8:** `dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true`.
- **Android (Kotlin/Java):** `ubuntu-latest`, JDK 17/21, `./gradlew test assembleRelease`;
  ключи подписи — только из GitHub Secrets, не из репозитория.
- **C++ (CMake):** матрица `ubuntu-latest` + `windows-latest` (MSVC), `ctest`.
- **Windows-установщики (.msi/.exe):** в CI проверить сигнатуру файла и размер перед загрузкой.
- Коммиты, которые не должны запускать сборку (например большие медиа в Git LFS) — с `[skip ci]`.

## 2. Релиз
- Дождаться зелёного CI: `gh run watch` или `gh run list -L 3`. Упал — `gh run view <id> --log-failed`.
- Тег `vX.Y.Z` (или `<имя>-vX.Y`), `gh release create <tag> <файлы> --notes "<изменения на русском>"`.
- GitHub режет кириллицу в именах файлов релиза — для ассетов использовать латинские имена,
  внутри архива можно русские.
- Указать в описании, что проверено реально, а что нет (например «на Windows не запускалось»,
  «не подписано — возможно предупреждение SmartScreen»), и SHA-256 файлов.

## 3. Комплект сдачи
Упаковку можно поручить субагенту **release-builder** (если он установлен).
1. `ALL_CODE_<Repo>.txt`: оглавление, затем файлы с разделителем `=== FILE: путь ===`;
   без `.git/ bin/ obj/ .vs/ .gradle/ build/ node_modules/`, бинарников и картинок.
2. `<Repo>_source.zip` — исходники без мусора сборки.
3. `README_RU.md` — требования, сборка, запуск.
4. Проверить, что zip распаковывается и собирается; выдать хеши.
Папку назначения называет пользователь (часто это папка на диске его ПК). Облачная сессия
туда писать не может — тогда отдать файлы ссылкой на релиз и сказать об этом.

## 4. Не публиковать
`.env`, `keystore.properties`, `*.jks`, `*.keystore`, токены, `cookies.txt`, приватные ключи,
адреса и пароли серверов.

## Отчёт
Сделано · CI (ссылка на run) · Релиз (ссылка, хеши) · Что не проверено.
