# Как работать над NotchClaude

## Требования

- macOS 14+
- Swift 6 toolchain (Xcode 16+ или toolchain со swift.org)
- Claude Code — для проверки на реальных логах

Сторонних зависимостей нет, ставить нечего.

## Сборка и запуск

```bash
swift build                                 # debug-сборка
swift run NotchClaude                       # запуск из терминала
./bundle.sh && open build/NotchClaude.app   # собрать и запустить .app
```

## Проверки перед PR

```bash
swift build -c release              # должно собраться без предупреждений
swift run NotchClaude --selftest    # самопроверка парсера логов
swift run NotchClaude --dump        # снимок по реальным логам — глазами
swift run NotchClaude --show        # панель раскрыта сразу — проверить отрисовку
```

Отдельного линтера в проекте нет: правила стиля описаны в
[docs/standards/swift.md](../docs/standards/swift.md) и проверяются на ревью.

## Стандарты

- Swift: [docs/standards/swift.md](../docs/standards/swift.md) — таблица правил и
  чеклист ревьюера.
- Git: [docs/standards/01-git-standards.md](../docs/standards/01-git-standards.md)
  — git flow, conventional commits, правила мержа.

Ключевое: Swift 6 strict concurrency, `@MainActor` для UI, никаких force-unwrap
без обоснования, никаких сторонних зависимостей без обоснования, новая
нетривиальная логика добавляет проверку в `selfTest()`.

## Git-процесс

1. Ветка от `develop`: `feature/<issue_id>-<короткое-описание>`.
2. Коммиты по conventional commits, по одному смысловому изменению.
3. Локально проходят сборка и `--selftest`.
4. PR в `develop`, squash merge. CI (`.github/workflows/build.yml`, macos-15)
   должен быть зелёным.

## CI

Единственный воркфлоу — `build.yml`: `swift build -c release`, затем
`.build/release/NotchClaude --selftest`.
