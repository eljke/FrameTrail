import SwiftUI
import FrameTrailCore

enum Theme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.075)
    static let card = Color(red: 0.085, green: 0.10, blue: 0.15)
    static let accent = Color(red: 0.95, green: 0.72, blue: 0.35)
    static let muted = Color(red: 0.57, green: 0.62, blue: 0.72)
}

struct PosterView: View {
    let title: MediaTitle
    var width: CGFloat = 112

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.indigo.opacity(0.8), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: title.kind == .movie ? "film.stack" : "tv")
                .font(.system(size: width * 0.28, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.4))
            if let url = title.posterURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .frame(width: width, height: width * 1.46)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
    }
}

struct TitleCard: View {
    let title: MediaTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            PosterView(title: title, width: 140)
            Text(title.title).font(.subheadline.weight(.semibold)).lineLimit(2).frame(width: 140, alignment: .leading)
            Text([title.kind == .movie ? L10n.text("Фильм") : L10n.text("Сериал"), title.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

struct SectionCaption: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased()).font(.caption2.weight(.bold)).tracking(2).foregroundStyle(Theme.accent)
            Text(title).font(.title2.bold()).foregroundStyle(.white)
        }
    }
}

struct InfoCard: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).font(.title3).frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(text).font(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: symbol).font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Theme.accent)
            Text(title).font(.title3.bold())
            Text(text).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 24)
    }
}

struct ErrorNotice: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote).foregroundStyle(.orange).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("errorNotice")
    }
}
