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
    @ObservedObject var tasks: TaskStore
    @ObservedObject var camera: CameraPreviewService
    @ObservedObject var auth: BiometricAuthService
    @ObservedObject var recentTargets: RecentTargetStore
    var open: () -> Void
    var close: () -> Void
    var select: (NotchContent) -> Void
    var openSettings: () -> Void
    var cameraAction: () -> Void
    var notify: (String, String) -> Void
    @State private var newTask = ""

    var body: some View {
        ZStack(alignment: .top) {
            islandSurface
            if presentation.transition < 1 {
                content(presentation.previousLayout)
                    .opacity(1 - presentation.transition)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            content(presentation.layout).opacity(presentation.transition)
            if let toast = presentation.toast {
                toastView(toast)
                    .padding(.top, presentation.cameraHeight + 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .frame(width: presentation.width, height: presentation.height, alignment: .top)
        .clipShape(islandShape)
        .overlay(islandShape.strokeBorder(presentation.isDropTarget ? MacBDesign.accent.opacity(0.8) : .white.opacity(0.075), lineWidth: presentation.isDropTarget ? 1.5 : 0.7))
        .shadow(color: .black.opacity(0.42), radius: 24, y: 10)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onExitCommand(perform: close)
    }

    private var islandSurface: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [.white.opacity(0.055), .clear, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [MacBDesign.accent.opacity(0.07), .clear], center: .topTrailing, startRadius: 0, endRadius: 250)
        }
    }

    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: presentation.cameraHeight > 0 ? 0 : presentation.radius,
            bottomLeadingRadius: presentation.radius, bottomTrailingRadius: presentation.radius,
            topTrailingRadius: presentation.cameraHeight > 0 ? 0 : presentation.radius)
    }

    @ViewBuilder private func content(_ layout: NotchLayout) -> some View {
        switch layout.phase {
        case .collapsed:
            compact.frame(width: layout.width, height: layout.height)
        case .glance:
            VStack(spacing: 0) {
                Color.clear.frame(height: presentation.cameraHeight)
                glance.frame(height: MacBDesign.Island.glanceBodyHeight).padding(.horizontal, 16)
            }.frame(width: layout.width, height: layout.height, alignment: .top).clipped()
        case .expanded:
            VStack(spacing: 0) {
                Color.clear.frame(height: presentation.cameraHeight)
                VStack(spacing: MacBDesign.Island.contentSpacing) {
                    tabs(layout.content)
                    if presentation.cameraPreviewVisible { cameraCard }
                    switch layout.content {
                    case .music: mediaContent
                    case .files: filesContent
                    case .clipboard: clipboardContent
                    case .tasks: tasksContent
                    }
                }
                .padding(.horizontal, MacBDesign.Island.horizontalPadding)
                .padding(.top, 10).padding(.bottom, 16)
            }.frame(width: layout.width, height: layout.height, alignment: .top).clipped()
        }
    }

    private var compact: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                if presentation.indicators && media.isPlaying { cover(size: 20, radius: 6).frame(width: 38) }
                Color.clear.frame(width: max(24, presentation.cameraWidth))
                if presentation.indicators && (!shelf.items.isEmpty || fileActivity.activeCount > 0) {
                    Text("\(max(shelf.items.count, fileActivity.activeCount))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                        .frame(width: 20, height: 20).background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 6)).frame(width: 38)
                }
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("MacB panelini aç")
    }

    private var glance: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                cover(size: 42, radius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.isPlaying ? mediaTitle : "Sessiz").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if media.isPlaying { Text(mediaSubtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if media.isPlaying {
                    playbackButton(media.isPlaying ? "pause.fill" : "play.fill", label: media.isPlaying ? "Duraklat" : "Oynat", size: 34, action: media.playPause)
                } else {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(media.isPlaying ? "\(mediaTitle), ayrıntıları aç" : "Medya yok, paneli aç")
    }

    private func tabs(_ selected: NotchContent) -> some View {
        HStack(spacing: 4) {
            tab("Medya", "play.fill", .music, selected)
            tab("Dosyalar", "tray.fill", .files, selected)
            tab("Pano", "doc.on.clipboard", .clipboard, selected)
            tab("İşler", "checkmark.circle", .tasks, selected)
            Spacer(minLength: 4)
            iconButton(presentation.cameraPreviewVisible ? "camera.fill" : "camera", label: "Kamera", action: cameraAction)
            iconButton("gearshape", label: "Ayarlar", action: openSettings)
        }.frame(height: MacBDesign.Island.tabHeight)
    }

    private func tab(_ title: String, _ symbol: String, _ section: NotchContent, _ selected: NotchContent) -> some View {
        Button { select(section) } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }.padding(.horizontal, 8).frame(height: 27)
                .foregroundStyle(.white.opacity(selected == section ? 0.94 : 0.42))
                .background(selected == section ? .white.opacity(0.11) : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected == section ? .isSelected : [])
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 27, height: 27).background(.white.opacity(0.055), in: Circle()) }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.58)).help(label).accessibilityLabel(label)
    }

    @ViewBuilder private var mediaContent: some View {
        if media.isPlaying || media.isRunning {
            VStack(spacing: 11) {
                HStack(spacing: 12) {
                    cover(size: MacBDesign.Island.heroArtwork, radius: 14)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mediaTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(mediaSubtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.48)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(11).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
                mediaControls
                if let error = media.errorMessage { Text(error).font(.system(size: 10)).foregroundStyle(.orange.opacity(0.8)).lineLimit(1) }
            }
        } else {
            HStack(spacing: 12) {
                cover(size: 48, radius: 13)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sessiz").font(.system(size: 15, weight: .semibold))
                    Text("Medya oynatınca burada görünür.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
                Image(systemName: "waveform").foregroundStyle(.white.opacity(0.25))
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder private var mediaControls: some View {
        if media.isPlaying {
            HStack(spacing: 16) {
                playbackButton("backward.fill", label: "Önceki", size: 32, action: media.previousTrack)
                playbackButton("pause.fill", label: "Duraklat", size: 40, prominent: true, action: media.playPause)
                playbackButton("forward.fill", label: "Sonraki", size: 32, action: media.nextTrack)
            }.frame(maxWidth: .infinity)
        } else if media.isRunning && !media.isAuthorized {
            Button("Bağlan", action: media.requestAuthorization).buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 34).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        } else {
            Button(action: media.playPause) { Label("Oynat", systemImage: "play.fill").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain).frame(maxWidth: .infinity).frame(height: 34).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private var filesContent: some View {
        VStack(spacing: 10) {
            if !recentTargets.items.isEmpty {
                HStack(spacing: 7) {
                    Text("Son hedefler").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
                    ForEach(recentTargets.items.prefix(3)) { target in
                        Button { recentTargets.open(target) } label: {
                            Text(target.appName).font(.system(size: 9, weight: .medium)).lineLimit(1).padding(.horizontal, 8).frame(height: 23).background(.white.opacity(0.06), in: Capsule())
                        }.buttonStyle(.plain).help("\(target.appName) uygulamasını aç")
                    }
                    Spacer()
                }
            }
            if shelf.items.isEmpty && recentFiles.items.isEmpty {
                Button(action: shelf.chooseFiles) {
                    HStack(spacing: 10) {
                        Image(systemName: presentation.isDropTarget ? "arrow.down" : "plus").font(.system(size: 15, weight: .semibold))
                        Text(presentation.isDropTarget ? "Bırak" : "Dosya ekle").font(.system(size: 12, weight: .semibold))
                    }.frame(maxWidth: .infinity).frame(height: 64).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(shelf.items) { item in fileRow(item) }
                        if preferences.recentFilesEnabled { ForEach(recentFiles.items) { item in recentFileRow(item) } }
                    }
                }.frame(maxHeight: 190).scrollIndicators(.hidden)
            }
            HStack {
                if let error = shelf.errorMessage { Text(error).foregroundStyle(.orange).lineLimit(1) }
                else { Text("\(shelf.items.count) öğe").foregroundStyle(.white.opacity(0.32)) }
                Spacer()
                Button(action: shelf.chooseFiles) { Image(systemName: "plus").frame(width: 26, height: 24) }.buttonStyle(.plain).help("Dosya ekle")
            }.font(.system(size: 10))
        }
    }

    private func fileRow(_ item: ShelfItem) -> some View {
        HStack(spacing: 3) {
            NativeFileDragView(item: item).frame(height: 32)
            rowButton("doc.on.doc", "Kopyala") { shelf.copy(item: item); notify("doc.on.doc", "Kopyalandı") }
            rowButton("xmark", "Raftan kaldır") { shelf.remove(id: item.id) }
        }.padding(.horizontal, 5).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private func recentFileRow(_ item: RecentFileItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill").frame(width: 18).foregroundStyle(.white.opacity(0.4))
            Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Spacer()
            rowButton("plus", "Rafa ekle") { shelf.add(urls: [item.url]); notify("plus", "Rafa eklendi") }
        }.padding(.horizontal, 8).frame(height: 32).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private var clipboardContent: some View {
        if preferences.protectPrivateTools && !auth.isAuthenticated {
            lockedContent(title: auth.isAuthenticating ? "Doğrulanıyor" : "Pano kilitli", symbol: "lock.fill") { select(.clipboard) }
        } else if clipboard.items.isEmpty {
            compactEmpty("Pano boş", symbol: "doc.on.clipboard", detail: "Kopyaladıkların burada görünür.")
        } else {
            VStack(spacing: 6) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if !clipboard.favorites.isEmpty { sectionLabel("Sık kullanılanlar") }
                        ForEach(clipboard.items.sorted { $0.isFavorite && !$1.isFavorite }) { item in clipboardRow(item) }
                    }
                }.frame(maxHeight: 218).scrollIndicators(.hidden)
                if let error = clipboard.errorMessage { Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1) }
            }
        }
    }

    private func clipboardRow(_ item: ClipboardShelfItem) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.isFavorite ? "star.fill" : "text.quote").frame(width: 18).foregroundStyle(item.isFavorite ? .yellow.opacity(0.8) : .white.opacity(0.38))
            Text(item.text.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 11)).lineLimit(1)
            Spacer()
            rowButton("doc.on.doc", "Kopyala") { clipboard.copy(item); notify("checkmark", "Kopyalandı") }
            rowButton(item.isFavorite ? "star.slash" : "star", item.isFavorite ? "Sık kullanılanlardan kaldır" : "Sık kullanılanlara ekle") { clipboard.toggleFavorite(item) }
            rowButton("xmark", "Sil") { clipboard.remove(item) }
        }.padding(.horizontal, 8).frame(height: 34).background(.white.opacity(item.isFavorite ? 0.065 : 0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private var tasksContent: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                TextField("Yeni iş…", text: $newTask).textFieldStyle(.plain).font(.system(size: 11)).onSubmit(addTask)
                Button(action: addTask) { Image(systemName: "plus").frame(width: 28, height: 26).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.leading, 10).padding(.trailing, 4).frame(height: 34).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            if tasks.items.isEmpty {
                compactEmpty("Liste temiz", symbol: "checkmark.circle", detail: "Aklındakini hemen ekle.")
            } else {
                ScrollView { LazyVStack(spacing: 6) { ForEach(tasks.items) { item in taskRow(item) } } }
                    .frame(maxHeight: 180).scrollIndicators(.hidden)
            }
            if let error = tasks.errorMessage { Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1) }
        }
    }

    private func taskRow(_ item: LocalTaskItem) -> some View {
        HStack(spacing: 7) {
            Button { tasks.toggleComplete(id: item.id) } label: { Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle").frame(width: 22, height: 28) }.buttonStyle(.plain)
            Text(item.title).font(.system(size: 11, weight: .medium)).strikethrough(item.isCompleted).foregroundStyle(.white.opacity(item.isCompleted ? 0.35 : 0.78)).lineLimit(1)
            Spacer()
            rowButton(item.isPinned ? "pin.slash" : "pin", item.isPinned ? "Sabitlemeyi kaldır" : "Sabitle") { tasks.togglePin(id: item.id) }
            rowButton("xmark", "Sil") { tasks.remove(id: item.id) }
        }.padding(.horizontal, 6).frame(height: 34).background(.white.opacity(item.isPinned ? 0.065 : 0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private var cameraCard: some View {
        Button(action: cameraAction) {
            ZStack(alignment: .bottomTrailing) {
                if camera.isRunning { CameraPreviewView(service: camera) }
                else { Color.white.opacity(0.035).overlay(ProgressView().controlSize(.small)) }
                Label("Büyüt", systemImage: "arrow.up.left.and.arrow.down.right").font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 8).frame(height: 24).background(.black.opacity(0.6), in: Capsule()).padding(8)
            }.frame(height: 118).clipShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel("Kamera önizlemesini büyüt")
    }

    private func compactEmpty(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(width: 34, height: 34).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }.padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func lockedContent(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 22, weight: .medium)).symbolEffect(.pulse, isActive: auth.isAuthenticating)
                Text(title).font(.system(size: 12, weight: .semibold))
            }.frame(maxWidth: .infinity).frame(height: 112).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }

    private func sectionLabel(_ title: String) -> some View { Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.35)).padding(.horizontal, 4) }
    private func rowButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 25, height: 25) }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.48)).help(label).accessibilityLabel(label)
    }
    private func toastView(_ toast: IslandToast) -> some View {
        Label(toast.message, systemImage: toast.symbol).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 10).frame(height: 26).background(.white.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }
    private func addTask() {
        let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        tasks.add(title: title); newTask = ""; notify("checkmark", "İş eklendi")
    }
    private var mediaTitle: String { media.title.isEmpty ? media.source.title : media.title }
    private var mediaSubtitle: String { media.artist.isEmpty ? media.source.title : "\(media.artist) · \(media.source.title)" }
    private func cover(size: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let artwork = media.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
            else { Image(systemName: media.source == .none ? "play.rectangle.fill" : media.source.symbol).font(.system(size: size * 0.3, weight: .semibold)).foregroundStyle(.white.opacity(0.5)) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius)).overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.08))).accessibilityHidden(true)
    }
    private func playbackButton(_ icon: String, label: String, size: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: prominent ? 14 : 11, weight: .semibold)).foregroundStyle(prominent ? .black : .white.opacity(0.82)).frame(width: size, height: size).background(prominent ? .white : .white.opacity(0.07), in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}
