import AppKit
import SwiftUI
import MacBCore

struct NotchView: View {
    @ObservedObject var presentation: NotchPresentation
    @ObservedObject var media: MediaService
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var recentFiles: RecentFileStore
    @ObservedObject var clipboard: ClipboardShelfStore
    @ObservedObject var fileActivity: FileActivityStore
    var open: () -> Void
    var close: () -> Void
    var select: (NotchContent) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if presentation.transition < 1 {
                content(presentation.previousLayout)
                    .opacity(1 - presentation.transition)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            content(presentation.layout)
                .opacity(presentation.transition)
        }
        .frame(width: presentation.width, height: presentation.height, alignment: .top)
        .background(.black)
        .clipShape(shape)
        .overlay(shape.strokeBorder(presentation.isDropTarget ? MacBDesign.accent.opacity(0.6) : .clear, lineWidth: 1.5))
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .onExitCommand(perform: close)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: presentation.cameraHeight > 0 ? 0 : presentation.radius,
            bottomLeadingRadius: presentation.radius, bottomTrailingRadius: presentation.radius,
            topTrailingRadius: presentation.cameraHeight > 0 ? 0 : presentation.radius)
    }

    @ViewBuilder private func content(_ layout: NotchLayout) -> some View {
        Group {
            switch layout.phase {
            case .collapsed: compact
            case .glance:
                VStack(spacing: 0) {
                    Color.clear.frame(height: presentation.cameraHeight)
                    glance.padding(.horizontal, 20).frame(height: 90)
                }
            case .expanded:
                VStack(spacing: 0) {
                    Color.clear.frame(height: presentation.cameraHeight)
                    VStack(spacing: 18) {
                        tabs(layout.content)
                        switch layout.content {
                        case .music: music
                        case .files: files
                        }
                    }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20)
                }
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .top)
        .clipped()
    }

    private var compact: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                if presentation.indicators && (media.isPlaying || !shelf.items.isEmpty || fileActivity.activeCount > 0) {
                    Group {
                        if media.isPlaying { cover(size: 20, radius: 5) }
                        else { Color.clear.frame(width: 20, height: 20) }
                    }.frame(width: 38)
                }
                Color.clear.frame(width: max(24, presentation.cameraWidth))
                if presentation.indicators && (media.isPlaying || !shelf.items.isEmpty || fileActivity.activeCount > 0) {
                    Group {
                        if !shelf.items.isEmpty || fileActivity.activeCount > 0 {
                            Text("\(max(shelf.items.count, fileActivity.activeCount))").font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit().frame(width: 20, height: 20)
                                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                        } else { Color.clear.frame(width: 20, height: 20) }
                    }.frame(width: 38)
                }
            }.frame(maxWidth: .infinity).frame(height: max(28, presentation.cameraHeight)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("MacB panelini aç")
        .accessibilityValue("\(shelf.items.count) dosya. \(media.isPlaying ? "Medya çalıyor" : "Medya duraklatıldı")")
    }

    private var glance: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                HStack(spacing: 13) {
                    cover(size: 48, radius: 10)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.48)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(title), ayrıntıları aç")
            if media.isPlaying {
                playbackButton(media.isPlaying ? "pause.fill" : "play.fill", label: media.isPlaying ? "Duraklat" : "Oynat", size: 36, action: media.playPause)
            } else if media.isRunning && !media.isAuthorized {
                Button("Bağlan", action: media.requestAuthorization)
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.10), in: Capsule())
                    .accessibilityLabel(media.isRunning ? "\(media.source.title) erişimine izin ver" : "\(media.source.title) aç")
            }
        }
    }

    private func tabs(_ section: NotchContent) -> some View {
        HStack(spacing: 6) {
            tab("Medya", symbol: "play.rectangle", section: .music, selected: section)
            tab("Dosyalar", symbol: "tray", section: .files, selected: section)
            Spacer()
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 26, height: 26) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.38)).help("Kapat · Esc").accessibilityLabel("Paneli kapat")
        }
    }
    private func tab(_ title: String, symbol: String, section: NotchContent, selected: NotchContent) -> some View {
        Button { select(section) } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(title).font(.system(size: 11, weight: .medium))
                if section == .files && !shelf.items.isEmpty { Text("\(shelf.items.count)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)) }
            }.padding(.horizontal, 11).frame(height: 28)
                .foregroundStyle(.white.opacity(selected == section ? 0.95 : 0.45))
                .background(selected == section ? .white.opacity(0.10) : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected == section ? .isSelected : [])
    }

    private var music: some View {
        VStack(spacing: 14) {
            mediaHero
            mediaControls
            if let error = media.errorMessage { Text(error).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(2) }
            if preferences.fileActivityEnabled && fileActivity.activeCount > 0 {
                activityPill("\(fileActivity.activeCount) yeni indirme", symbol: "arrow.down.circle")
            }
        }
    }

    private var mediaHero: some View {
        HStack(spacing: 15) {
            cover(size: 76, radius: 18)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: media.source == .none ? "sparkles.rectangle.stack" : media.source.symbol)
                        .font(.system(size: 10, weight: .semibold))
                    Text(media.source == .none ? "Hazır" : media.source.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white.opacity(0.56))
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background {
            ZStack {
                LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(MacBDesign.accent.opacity(media.source == .none ? 0.08 : 0.18))
                    .frame(width: 150, height: 150)
                    .blur(radius: 34)
                    .offset(x: 138, y: -26)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.075)))
    }

    @ViewBuilder private var mediaControls: some View {
        if media.isPlaying {
            HStack(spacing: 18) {
                playbackButton("backward.fill", label: "Önceki parça", size: 36, action: media.previousTrack)
                playbackButton("pause.fill", label: "Duraklat", size: 48, prominent: true, action: media.playPause)
                playbackButton("forward.fill", label: "Sonraki parça", size: 36, action: media.nextTrack)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        } else if media.isRunning && !media.isAuthorized {
            Button("\(media.source.title)’e bağlan", action: media.requestAuthorization)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06)))
        } else {
            emptyMediaState
        }
    }

    private var emptyMediaState: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.075))
                Image(systemName: "play.slash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Şu an çalan medya yok")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                Text("Spotify, Apple Music veya tarayıcıda oynatınca buraya düşer.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.045)))
    }

    private var files: some View {
        VStack(spacing: 12) {
            if shelf.items.isEmpty && recentFiles.items.isEmpty && clipboard.items.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 25, weight: .light)).foregroundStyle(.white.opacity(0.55))
                    Text(presentation.isDropTarget ? "Buraya bırak" : "Dosyalarını buraya bırak").font(.system(size: 13, weight: .medium))
                    Text("Sonra istediğin pencereye sürükle.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.38))
                }.frame(maxWidth: .infinity).frame(height: 90)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !shelf.items.isEmpty {
                            shelfSectionTitle("Raf")
                            ForEach(shelf.items) { item in
                                HStack(spacing: 3) {
                                    NativeFileDragView(item: item).frame(height: 36)
                                    Button { shelf.copy(item: item) } label: { Image(systemName: "doc.on.doc").frame(width: 28, height: 30) }
                                        .disabled(!item.isAvailable).help("Kopyala").accessibilityLabel("\(item.name) dosyasını kopyala")
                                    Button { shelf.remove(id: item.id) } label: { Image(systemName: "xmark").frame(width: 26, height: 30) }
                                        .help("Raftan kaldır").accessibilityLabel("\(item.name) dosyasını raftan kaldır")
                                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                                    .padding(.horizontal, 6).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                        if preferences.recentFilesEnabled && !recentFiles.items.isEmpty {
                            shelfSectionTitle("Son dosyalar")
                            ForEach(recentFiles.items) { item in recentFileRow(item) }
                        }
                        if preferences.clipboardShelfEnabled && !clipboard.items.isEmpty {
                            shelfSectionTitle("Pano")
                            ForEach(clipboard.items) { item in clipboardRow(item) }
                        }
                    }
                }.frame(height: min(292, CGFloat(max(1, shelf.items.count + recentFiles.items.count + clipboard.items.count)) * 42 + 72))
            }
            HStack {
                if let error = shelf.errorMessage { Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1) }
                else if preferences.fileActivityEnabled && fileActivity.activeCount > 0 { Text("\(fileActivity.activeCount) yeni indirme algılandı.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.38)) }
                else { Text("Dosyaların yerinde kalır.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3)) }
                Spacer()
                Button(action: shelf.chooseFiles) { Label("Ekle", systemImage: "plus").font(.system(size: 11, weight: .medium)) }
                    .buttonStyle(.plain).help("Dosya veya klasör ekle")
            }
        }
    }

    private func shelfSectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.36)).padding(.horizontal, 4)
    }

    private func recentFileRow(_ item: RecentFileItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder" : "doc").frame(width: 20)
            Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            Button { shelf.add(urls: [item.url]) } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                .help("Rafa ekle").accessibilityLabel("\(item.name) dosyasını rafa ekle")
        }
        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.68))
        .padding(.horizontal, 8).frame(height: 34)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private func clipboardRow(_ item: ClipboardShelfItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "text.quote").frame(width: 20)
            Text(item.text).font(.system(size: 11)).lineLimit(1)
            Spacer(minLength: 4)
            Button { clipboard.copy(item) } label: { Image(systemName: "doc.on.doc").frame(width: 28, height: 28) }
                .help("Panoya kopyala").accessibilityLabel("Pano metnini kopyala")
        }
        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.62))
        .padding(.horizontal, 8).frame(height: 34)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private func activityPill(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.58))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.white.opacity(0.055), in: Capsule())
    }

    private var title: String {
        if !media.isPlaying && !media.isRunning { return "Sessiz" }
        if !media.isAuthorized { return "\(media.source.title)’e bağlan" }
        return media.title.isEmpty ? "Sıradaki parçan" : media.title
    }
    private var subtitle: String {
        if !media.isPlaying && !media.isRunning { return "Bir şey çalmaya başlayınca burada görünür." }
        if !media.isAuthorized { return "Oynatmayı buradan yönet." }
        return media.artist.isEmpty ? "\(media.source.title)’ten bir parça seç." : "\(media.artist) · \(media.source.title)"
    }
    private func cover(size: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.11), .white.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let artwork = media.artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: media.source == .none ? "play.rectangle" : media.source.symbol)
                        .font(.system(size: size * 0.30, weight: .semibold))
                    if media.source == .none {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.22))
                            .frame(width: size * 0.36, height: 4)
                    }
                }
                .foregroundStyle(.white.opacity(media.source == .none ? 0.62 : 0.68))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.085)))
        .accessibilityHidden(true)
    }
    private func playbackButton(_ icon: String, label: String, size: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: prominent ? 16 : 13, weight: .semibold))
                .foregroundStyle(prominent ? .black : .white.opacity(0.85))
                .frame(width: size, height: size)
                .background(prominent ? .white : .white.opacity(0.07), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}
