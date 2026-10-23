import SwiftUI

struct QuickGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Как пользоваться FrameTrail").font(.title2.bold())
                Text("Сохраняй фильмы и сериалы, отмечай просмотренное и ставь оценки. Отзывы и вопросы необязательны.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                step("1", symbol: "magnifyingglass", title: "Найди и сохрани", text: "Ищи фильм или сериал в «Обзоре». Личный TMDB API Read Access Token в настройках расширяет каталог. Это отдельно от аккаунта FrameTrail.")
                step("2", symbol: "checkmark.circle", title: "Отметь просмотренное", text: "Для фильма — «Досмотрел», для сериала — конкретные серии. Названия и аннотации непросмотренных серий скрыты. Вопросы и варианты при оценке серии не используют материалы остальных.")
                step("3", symbol: "text.book.closed", title: "Добавь глубину разговору", text: "Аннотация — только начало. После просмотра можно загрузить подробный сюжет Wikipedia или добавить текст/субтитры. Для разбора впечатлений приложение попробует найти пересказ само; если его нет, сообщит об этом.")
                step("4", symbol: "star.bubble", title: "Оцени и сохрани важное", text: "Выбери звёзды тапом или движением пальца. Для серии открой её меню. Выбирай несколько сюжетных вариантов, пиши своё или пропускай вопросы. Оценки и впечатления остаются в дневнике; их можно изменить.")
                step("5", symbol: "sparkles.rectangle.stack", title: "Собери отзывы о сериях", text: "Сохраняй впечатления о сериях, затем открой «Итог по сериям». Apple обработает записи локально. Сводку можно остановить, отредактировать, сохранить и отправить через системный общий доступ.")
                DisclosureGroup("Помощник, аккаунт и память") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Модель Apple и язык подготавливаются в настройках. Для русского может понадобиться локальный перевод и загрузка системных пакетов. Если генерация недоступна, библиотека, оценки и свои заметки продолжают работать.")
                        Text("Аккаунт FrameTrail синхронизирует библиотеку, прогресс и сохранённые впечатления. Гостевая библиотека отдельная: перенести её можно через экспорт и импорт. Диалоги и полные источники остаются на устройстве.")
                        Text("«Настройки → Память» очищает изображения отдельно от материалов. Оценки, заметки и прогресс остаются. При удалении материалов исчезают и импортированные тексты — сохрани свои исходные файлы отдельно.")
                    }.font(.footnote).foregroundStyle(Theme.muted).padding(.top, 10)
                }.font(.subheadline)
                Button("Открыть обзор") { dismiss(); model.selectedTab = 0 }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("guideOpenDiscover")
            }.padding(24)
        }
        .background(Theme.background).navigationTitle("Краткий гид").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("quickGuide")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.accessibilityIdentifier("closeGuide") } }
    }

    private func step(_ number: String, symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.headline).foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32).background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
