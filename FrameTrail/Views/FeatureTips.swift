import SwiftUI
import TipKit

struct FirstTitleTip: Tip {
    var title: Text { Text("Добавь фильм или сериал") }
    var message: Text? { Text("Найди фильм или сериал поиском и сохрани в библиотеку. Если его нет в каталоге, добавь название вручную.") }
    var image: Image? { Image(systemName: "books.vertical") }
    var actions: [Action] { Action(id: "guide", title: "Краткий гид") }
    var options: [Option] { MaxDisplayCount(1) }
}

struct FirstReviewTip: Tip {
    var title: Text { Text("Поставь оценку или напиши отзыв") }
    var message: Text? { Text("Поставь оценку или запиши мысли. Помощник предложит варианты из сюжета просмотренного; любые вопросы можно пропустить. Оценка отдельной серии — в её меню.") }
    var image: Image? { Image(systemName: "star.bubble") }
    var options: [Option] { MaxDisplayCount(1) }
}

struct SeriesRetrospectiveTip: Tip {
    var title: Text { Text("Заметки о сериях можно объединить") }
    var message: Text? { Text("У тебя уже есть записи о нескольких сериях. Собери из них общую картину на iPhone — результат можно изменить и сохранить в дневник.") }
    var image: Image? { Image(systemName: "sparkles.rectangle.stack") }
    var options: [Option] { MaxDisplayCount(1) }
}
