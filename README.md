# NotchClaude

macOS-виджет, живущий в чёлке MacBook. Наводишь курсор на чёлку — панель
раскрывается вниз и показывает, чем занят Claude Code и сколько токенов уже
израсходовано: за скользящее 5-часовое окно лимитов, за сегодня и за текущую
сессию. Убираешь курсор — панель исчезает.

Никакой иконки в Dock, никакой сети, никаких разрешений macOS.

## Требования

- macOS 14 (Sonoma) или новее
- Swift 6 toolchain (Xcode 16+ или отдельный toolchain от swift.org)
- Установленный Claude Code — виджет читает его локальные логи

## Быстрый старт

```bash
./bundle.sh && open build/NotchClaude.app   # собрать и запустить .app
swift run NotchClaude --dump                # напечатать текущий снимок в терминал
swift run NotchClaude --selftest            # самопроверка парсера логов
swift run NotchClaude --show                # запустить с уже раскрытой панелью
```

Приложение не показывается в Dock. Чтобы выйти — навести курсор на чёлку и
нажать «Выход» в раскрытой панели.

## Как это работает

1. Claude Code пишет каждое событие строкой JSON в
   `~/.claude/projects/<project>/<session>.jsonl`.
2. Виджет обходит эти файлы (отбирая по mtime), берёт строки
   `"type":"assistant"` и из них `message.usage`, `timestamp`, `sessionId`,
   `cwd`, `message.model`.
3. Повторные записи одного запроса отбрасываются по `message.id` + `requestId`,
   остальное складывается в три периода: окно 5 ч, сегодня, текущая сессия.
4. Прозрачная `NSPanel` лежит ровно по границам чёлки; наведение отслеживается
   `NSTrackingArea` и раскрывает панель вниз.
5. Пока панель раскрыта, снимок пересчитывается раз в 3 секунды; в свёрнутом
   состоянии приложение не делает ничего.

## Ограничения

- Нет оценки расхода в деньгах — только токены (нужна таблица цен моделей).
- Нет автозапуска при входе в систему.
- Нет настроек и графиков истории.
- Файлы логов перечитываются целиком при каждом обновлении.
- Поддерживается один экран с чёлкой; на экране без чёлки панель рисуется
  полоской по центру верхнего края.
- Подпись ad-hoc: на другой машине Gatekeeper потребует явного разрешения.

## Структура проекта

```
Package.swift                  SPM-манифест (executableTarget, macOS 14+)
bundle.sh                      сборка build/NotchClaude.app
Sources/NotchClaude/
  main.swift                   аргументы CLI, NSApplication (.accessory), AppDelegate
  Usage.swift                  Tokens, Snapshot, UsageReader, selfTest()
  NotchPanel.swift             геометрия чёлки, NSPanel, HoverHostingView, Model
  StatsView.swift              содержимое раскрытой панели
docs/
  PRD.md                       требования, сценарии, эпики
  architecture.md              компоненты, поток данных, решения, риски
  product-brief-*.md           бриф
  standards/swift.md           стандарт кода Swift
  standards/01-git-standards.md стандарт работы с git
.github/workflows/build.yml    CI: сборка release + --selftest
```

## Лицензия

MIT — см. [LICENSE](LICENSE).
