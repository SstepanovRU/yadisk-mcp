# Установка yadisk-mcp на новой машине

Инструкция для установки **из этого репозитория** (форк с исправлениями и режимом `--safe-delete`) и подключения к Claude Code и Codex.

Что получится в итоге:

- сервер стоит в `.venv` внутри папки репозитория;
- токен Яндекс Диска лежит в пользовательской переменной окружения `YANDEX_DISK_TOKEN`, а не в репозитории и не в конфигах клиентов;
- в Claude Code и Codex зарегистрирован MCP-сервер `yadisk`, запущенный с флагом `--safe-delete`.

## Что нужно заранее

| Что | Как поставить (Windows) |
|---|---|
| Git | `winget install Git.Git` |
| Python 3.11 или новее | `winget install Python.Python.3.13` |
| Claude Code и/или Codex | уже установлены |
| Токен Яндекс Диска | см. раздел [Токен](#токен) ниже. Можно взять тот же токен, что на старой машине |

После `winget install` закрой и снова открой терминал, иначе новые команды не найдутся.

## Windows: быстрая установка

```powershell
git clone https://github.com/SstepanovRU/yadisk-mcp.git C:\VibeCoding\yadisk-mcp
cd C:\VibeCoding\yadisk-mcp
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Что делает скрипт `install.ps1`:

1. Находит Python 3.11 или новее.
2. Создаёт `.venv` и ставит пакет (`pip install -e .`).
3. Проверяет переменную `YANDEX_DISK_TOKEN`. Если её нет, просит вставить токен (ввод скрыт) и сохраняет его в переменные окружения пользователя.
4. Проверяет токен запросом к API Яндекс Диска.
5. Регистрирует сервер `yadisk` в Claude Code (`claude mcp add -s user`) и в Codex (`~/.codex/config.toml`).

Папку для клонирования можно выбрать любую: скрипт сам определяет, где лежит репозиторий и кто текущий пользователь. Скрипт можно запускать повторно. Если в Codex уже есть секция `[mcp_servers.yadisk]`, он её не трогает.

Параметры:

```powershell
.\install.ps1 -ServerArgs '--safe-delete','--read-only'   # другие флаги сервера
.\install.ps1 -ServerArgs @()                              # без флагов (удаление работает как обычно)
.\install.ps1 -NoRegister                                  # только установка и проверка токена
```

**После установки перезапусти Claude Code и Codex**, иначе они не увидят новую переменную окружения.

Проверка:

```powershell
claude mcp list      # yadisk должен быть в статусе "Connected"
```

Потом в Claude: «Покажи, сколько места на Яндекс Диске».

## Ручная установка (Windows)

Если скрипт не подходит, сделай те же шаги руками. Все команды запускай из папки репозитория (куда сделал `git clone`).

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python -m pip install -e .

# токен в переменные окружения пользователя (один раз)
[Environment]::SetEnvironmentVariable('YANDEX_DISK_TOKEN', '<токен>', 'User')
```

Полный путь к серверу на этой машине (понадобится ниже):

```powershell
(Resolve-Path .\.venv\Scripts\yadisk-mcp.exe).Path
```

Claude Code:

```powershell
claude mcp add yadisk -s user -- "$PWD\.venv\Scripts\yadisk-mcp.exe" --safe-delete
```

Codex: добавь в `%USERPROFILE%\.codex\config.toml`, подставив путь из команды выше:

```toml
[mcp_servers.yadisk]
command = '<путь к yadisk-mcp.exe>'
args = ["--safe-delete"]
env_vars = ["YANDEX_DISK_TOKEN"]
```

`env_vars` пробрасывает токен из окружения в сервер. Без этой строки Codex запустит сервер без токена.

Claude Desktop: в `%APPDATA%\Claude\claude_desktop_config.json` (тот же путь, но в JSON каждый `\` пишется как `\\`):

```json
{
  "mcpServers": {
    "yadisk": {
      "command": "C:\\path\\to\\yadisk-mcp\\.venv\\Scripts\\yadisk-mcp.exe",
      "args": ["--safe-delete"]
    }
  }
}
```

## macOS / Linux

```bash
git clone https://github.com/SstepanovRU/yadisk-mcp.git ~/yadisk-mcp
cd ~/yadisk-mcp
python3 -m venv .venv
.venv/bin/pip install -e .

# токен: добавь в ~/.zshrc или ~/.bashrc и открой новый терминал
echo 'export YANDEX_DISK_TOKEN=<токен>' >> ~/.zshrc

claude mcp add yadisk -s user -- ~/yadisk-mcp/.venv/bin/yadisk-mcp --safe-delete
```

Для Codex секция в `~/.codex/config.toml` такая же, как для Windows, только в `command` нужен полный путь, который выведет `echo ~/yadisk-mcp/.venv/bin/yadisk-mcp` (`~` в TOML не раскрывается).

## Токен

Токен действует 1 год. Если на старой машине он есть, его можно перенести:

```powershell
# на старой машине: вывести токен (не вставляй вывод в чаты и логи)
[Environment]::GetEnvironmentVariable('YANDEX_DISK_TOKEN', 'User')
```

Новый токен получается так:

1. Создай приложение на [oauth.yandex.ru](https://oauth.yandex.ru) (подробно в [README](README.md#получение-токена)): платформа «Веб-сервисы», Callback URL `https://oauth.yandex.ru/verification_code`, права `cloud_api:disk.read`, `cloud_api:disk.write`, `cloud_api:disk.app_folder`, `cloud_api:disk.info`.
2. Запусти помощник и следуй подсказкам:

   ```powershell
   .\.venv\Scripts\python get_token.py
   ```

3. Сохрани полученный токен в переменную `YANDEX_DISK_TOKEN` (или запусти `install.ps1`, он спросит сам).

Токен нельзя коммитить. Файлы `.env` и `*.token` уже в `.gitignore`.

## Обновление

```powershell
cd <папка репозитория>
git pull
```

Пакет стоит в editable-режиме, поэтому изменения кода подхватываются после перезапуска Claude Code или Codex. Если поменялись зависимости в `pyproject.toml`, закрой клиенты и запусти `.\install.ps1` ещё раз: пока сервер запущен, `yadisk-mcp.exe` занят и pip не может его заменить.

## Если не работает

| Симптом | Причина и что делать |
|---|---|
| `YANDEX_DISK_TOKEN environment variable is not set` | Клиент запущен до того, как появилась переменная. Перезапусти Claude Code или Codex. Для Codex проверь строку `env_vars` |
| `install.ps1` пишет `Token is invalid or expired` | Токен истёк или скопирован с ошибкой. Получи новый (раздел [Токен](#токен)) |
| `running scripts is disabled on this system` | Запускай через `powershell -ExecutionPolicy Bypass -File .\install.ps1` |
| `WinError 32 ... yadisk-mcp.exe` при pip install | Сервер запущен клиентом. Закрой Claude Code и Codex и повтори |
| В `claude mcp list` сервер `Failed` | Запусти `.\.venv\Scripts\yadisk-mcp.exe --safe-delete` вручную и посмотри ошибку (выход: Ctrl+C) |
