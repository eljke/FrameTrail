# Работа над FrameTrail / Contributing

## Баги и изменения

Каждый обнаруженный баг фиксируется в [GitHub Issues](https://github.com/eljke/FrameTrail/issues) **до исправления**, включая ошибки, найденные во время разработки и тестирования. Сначала проверь существующие issues: дополни подходящую, не создавай дубликат. Новые функции и заметные улучшения также получают отдельную issue с ожидаемым поведением.

В баге укажи версию, шаги, фактический и ожидаемый результат, влияние и критерии проверки. Приложи безопасный пример или скриншот. Не публикуй email, пароли, токены, личные записи или полные журналы с персональными данными. Различай подтверждённую причину и предположение.

Используй метки по смыслу: `bug` — дефект существующего поведения, `enhancement` — новая функция или улучшение. Добавляй подходящую область `area: auth`, `area: localization`, `area: sources`, `area: ratings` или `area: ux`. Не помечай каждую задачу как ошибку и не назначай высокий приоритет без оценки влияния.

Одна смысловая правка — один Conventional Commit. Связывай коммит и PR с issue. Закрывай баг после проверки исправления, указывая тесты и версию; обходное решение само по себе не означает исправление. Непроверенное на устройстве поведение обозначай явно.

Пользовательские изменения проходят через `release/<major.minor.patch>` и проверяемый PR. Веди версии по SemVer. Опубликуй и проверь IPA из релизной ветки перед слиянием в `main`; сохраняй релизную ветку. Изменения только документации не требуют выпуска нового IPA.

## English

Record every bug in [GitHub Issues](https://github.com/eljke/FrameTrail/issues) before fixing it, including defects found during implementation or testing. Search for duplicates first. Track substantial features and improvements separately with expected behavior and acceptance criteria.

Include the version, reproduction steps, actual and expected behavior, impact and verification criteria. Keep credentials and personal information out of public issues. Distinguish evidence from hypotheses. Use one Conventional Commit per meaningful change and link commits and pull requests to their issues. Close a bug only after verification, with tests and the fixed version; a workaround is not a fix.

Use `bug` for defects and `enhancement` for new capabilities or improvements, together with the relevant `area:` label. Classify issues by their behavior rather than marking all work as bugs. Assign priority according to impact.

Use SemVer and release branches. Publish and verify the IPA before merging its release pull request into `main`, and retain the release branch. Documentation-only changes do not require a new IPA.
