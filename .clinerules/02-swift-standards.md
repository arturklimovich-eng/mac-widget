# Project Standards: Swift

Этот проект — только Swift (macOS-приложение NotchClaude). Python- и
TypeScript-стандартов здесь нет и они не применяются.

- Стандарт кода: [docs/standards/swift.md](../docs/standards/swift.md) — таблица
  правил с уровнями FAIL/WARN/INFO и чеклист ревьюера.
- Кратко: Swift 6 strict concurrency; `@MainActor` на всём, что трогает UI;
  никаких force-unwrap без обоснования; значения по умолчанию при парсинге
  внешних данных; никаких сторонних зависимостей без обоснования в
  `docs/architecture.md`; новая нетривиальная логика добавляет проверку в
  `selfTest()`; 4 пробела, 120 колонок, комментарии по-русски; осознанные
  упрощения помечаются комментарием `ponytail:`.
- Проверки перед PR: `swift build -c release` и
  `swift run NotchClaude --selftest`.
