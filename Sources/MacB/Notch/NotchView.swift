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
    @ObservedObject var aiActivity: AIActivityService
    @ObservedObject var systemMonitor: SystemMonitorService
    @ObservedObject var processes: ProcessMonitorService
    @ObservedObject var watchers: WatchTaskStore
    @ObservedObject var lid: LidAngleService
    @ObservedObject var keyboardCleaning: KeyboardCleaningService
    @ObservedObject var timer: TimerService
    @ObservedObject var widgets: IslandLayoutStore
    @ObservedObject var launcher: AppLauncherStore
    @ObservedObject var background: IslandBackgroundStore
    @ObservedObject var weather: WeatherService
    @ObservedObject var note: QuickNoteStore
    @ObservedObject var faceUnlock: FaceUnlockService
    @ObservedObject var assistant: JarvisSession
    @ObservedObject var briefing: BriefingService
    @ObservedObject var jobs: AgentJobStore
    var closeAssistant: () -> Void
    var closeBriefing: () -> Void
    var approveProposal: (AgentProposal, UUID) -> Void
    var refuseProposal: (AgentProposal, UUID) -> Void
    var dismissAgent: (UUID) -> Void
    var startAssistant: () -> Void
    /// One process-wide assertion, so there is one shared instance of it.
    @ObservedObject private var keepAwake = KeepAwakeService.shared
    var open: () -> Void
    var close: () -> Void
    var select: (NotchContent) -> Void
    var openSettings: () -> Void
    var cameraAction: () -> Void
    var notify: (String, String) -> Void
    @State private var clipboardFilter: ClipboardFilter = .recent
    /// Where the pointer is inside the panel, for the specular highlight.
    @State private var pointer: CGPoint?
    /// The island is glass from edge to edge, so this setting is not a detail
    /// here: with it on, every translucent surface in the panel goes solid.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            islandSurface
            if presentation.transition < 1 {
                content(presentation.previousLayout, isInteractive: false)
                    .opacity(1 - presentation.transition)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            content(presentation.layout, isInteractive: true).opacity(presentation.transition)
            if let toast = presentation.toast {
                toastView(toast)
                    .padding(.top, presentation.cameraHeight + 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .frame(width: presentation.width, height: presentation.height, alignment: .top)
        .clipShape(islandShape)
        .overlay(specularHighlight)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point): pointer = point
            case .ended: pointer = nil
            }
        }
        .overlay(islandShape.strokeBorder(surfaceStrokeStyle,
            lineWidth: presentation.layout.phase == .collapsed ? 0 : 1)
            .motion(MacBDesign.Motion.gentle, value: media.tint))
        .modifier(HingeFold(progress: lid.foldProgress))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onExitCommand(perform: close)
    }

    /// The bright spot a sheet of glass carries under a light source.
    ///
    /// Apple's interactive glass already brightens the rim under the pointer,
    /// which is felt more than seen. This is the other half of the same idea:
    /// a soft pool of light on the face of the sheet, moving with the cursor,
    /// so the panel reads as something with a surface rather than a hole cut in
    /// the screen. It is deliberately faint. A highlight you notice as a
    /// highlight has already failed.
    ///
    /// Only on glass, and never while collapsed: there is no sheet to light
    /// when the island is a black bar, and a moving spot on pure black would
    /// just look like a rendering fault.
    @ViewBuilder private var specularHighlight: some View {
        if let pointer, carriesGlass, presentation.layout.phase != .collapsed {
            RadialGradient(colors: [.white.opacity(0.10), .white.opacity(0.03), .clear],
                           center: .center, startRadius: 0, endRadius: 90)
                .frame(width: 220, height: 220)
                .position(pointer)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .motion(MacBDesign.Motion.instant, value: pointer)
        }
    }

    private var carriesGlass: Bool {
        guard !reduceTransparency else { return false }
        return preferences.islandAppearance == .liquidGlass || preferences.islandAppearance == .blackGlass
    }

    @ViewBuilder private var islandSurface: some View {
        if presentation.layout.phase == .collapsed {
            Color.clear
        } else if reduceTransparency {
            // Asked for less transparency, given none: a flat surface the
            // widgets are guaranteed to read against, whatever the wallpaper.
            Color.black
        } else {
            switch preferences.islandAppearance {
            case .pureBlack:
                Color.black
            case .liquidGlass:
                translucentSurface(tinted: false)
            case .blackGlass:
                translucentSurface(tinted: true)
            case .customImage:
                if let image = background.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    // Widgets and labels are white; the picture has to stay behind them.
                    Color.black.opacity(0.55)
                    glassSheen
                } else {
                    Color.black
                }
            }
        }
    }

    /// What the island draws over its own glass.
    ///
    /// The glass itself is not here. A `.behindWindow` material cannot sample
    /// the screen from inside a SwiftUI hierarchy that clips and folds itself,
    /// so it lives in the panel's window under this view — see
    /// `NotchController.updateBackdrop(phase:)`. What is left here is the veil
    /// that keeps white text legible over a white desktop, and how much of it
    /// there is, is the user's call.
    @ViewBuilder private func translucentSurface(tinted: Bool) -> some View {
        Color.black.opacity(veilOpacity(tinted: tinted))
        glassSheen
    }

    /// How much black sits between the desktop and the widgets.
    ///
    /// At the top of the slider there is none at all: the material behind the
    /// panel already carries enough of its own weight to keep white text on it,
    /// and anything added on top of that was the reason the "glass" still read
    /// as a black bar over a dark desktop.
    private func veilOpacity(tinted: Bool) -> Double {
        let heaviest: Double = tinted ? 0.62 : 0.46
        return heaviest * (1 - translucency)
    }

    private var translucency: Double {
        min(1, max(0, preferences.islandTranslucency))
    }

    /// What light does to a sheet of glass, as opposed to what paint does to a
    /// panel.
    ///
    /// The old sheen ran from a white corner to a flat 28% black one, and that
    /// black was there whatever the slider said — over a dark desktop it was
    /// most of why the island still read as a bar rather than a pane. Glass
    /// does darken towards the edge it is lit away from, but by a fraction of
    /// that, and the fraction shrinks as the sheet gets thinner.
    private var glassSheen: some View {
        LinearGradient(stops: [
            .init(color: .white.opacity(0.16 - 0.05 * translucency), location: 0),
            .init(color: .white.opacity(0.05 - 0.02 * translucency), location: 0.22),
            .init(color: .clear, location: 0.55),
            .init(color: .black.opacity(0.22 * (1 - translucency) + 0.03), location: 1)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The lit rim.
    ///
    /// The single most glass-like thing on a sheet of glass is its edge: it
    /// gathers light along the top, almost vanishes down the sides, and picks
    /// up a second, weaker line where it meets what is under it. A flat
    /// one-colour hairline says "rounded rectangle"; this says "edge".
    private var surfaceStrokeStyle: AnyShapeStyle {
        if presentation.layout.phase == .collapsed { return AnyShapeStyle(Color.clear) }
        if media.isPlaying, let tint = media.tint {
            return AnyShapeStyle(LinearGradient(
                colors: [tint.opacity(0.60), tint.opacity(0.20), tint.opacity(0.34)],
                startPoint: .top, endPoint: .bottom))
        }
        if preferences.islandAppearance == .pureBlack || reduceTransparency {
            return AnyShapeStyle(MacBDesign.IslandToken.Fill.hairline)
        }
        return AnyShapeStyle(LinearGradient(colors: [
            .white.opacity(0.24 + 0.22 * translucency),
            .white.opacity(0.06),
            .white.opacity(0.10 + 0.08 * translucency)
        ], startPoint: .top, endPoint: .bottom))
    }

    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: presentation.cameraHeight > 0 ? 0 : presentation.radius,
            bottomLeadingRadius: presentation.radius, bottomTrailingRadius: presentation.radius,
            topTrailingRadius: presentation.cameraHeight > 0 ? 0 : presentation.radius)
    }

    @ViewBuilder private func content(_ layout: NotchLayout, isInteractive: Bool) -> some View {
        switch layout.phase {
        case .collapsed:
            compact.frame(width: layout.width, height: layout.height)
        case .peek:
            VStack(spacing: 0) {
                Color.clear.frame(height: presentation.cameraHeight)
                Group {
                    if let event = presentation.event {
                        IslandEventView(event: event, artwork: media.artwork)
                            .transition(.opacity)
                    } else {
                        peek
                    }
                }
                .frame(height: IslandGeometry.peekHeight)
                .padding(.horizontal, 18)
            }.frame(width: layout.width, height: layout.height, alignment: .top).clipped()
        case .expanded:
            VStack(spacing: 0) {
                Color.clear.frame(height: presentation.cameraHeight)
                    .overlay {
                        if layout.content == .assistant, hasEars {
                            IslandAssistantEars(session: assistant, captions: $preferences.assistantCaptions,
                                                earWidth: IslandGeometry.assistantEarContentWidth(
                                                    panelWidth: layout.width, notchWidth: presentation.cameraWidth),
                                                close: closeAssistant)
                        }
                    }
                VStack(spacing: IslandGeometry.gap) {
                    if layout.content == .assistant, assistant.showsInput {
                        IslandAssistantInput(session: assistant, openSettings: openSettings,
                                             isInteractive: isInteractive)
                            .transition(.opacity)
                    } else {
                        // The target section, not this copy's. Both copies of the
                        // panel are on screen during a cross-fade, and a row that
                        // disagrees with itself shows two pucks at once.
                        IslandNavigation(selected: presentation.layout.content, isEditing: widgets.isEditing,
                                         select: select,
                                         toggleEditing: { widgets.isEditing.toggle() },
                                         cameraAction: cameraAction, openSettings: openSettings)
                            .transition(.opacity)
                    }
                    if presentation.cameraPreviewVisible { cameraCard }
                    if layout.content != .assistant || assistantHasBody { section(layout) }
                }
                .motion(MacBDesign.Motion.quick, value: assistant.showsInput)
                .padding(.horizontal, IslandGeometry.horizontalPadding)
                .padding(.top, IslandGeometry.topPadding)
                .padding(.bottom, IslandGeometry.bottomPadding)
            }.frame(width: layout.width, height: layout.height, alignment: .top).clipped()
        }
    }

    @ViewBuilder private func section(_ layout: NotchLayout) -> some View {
        if presentation.isDropTarget {
            IslandDropView(recentTargets: recentTargets, pendingURLs: presentation.pendingDropURLs,
                           sendToAirDrop: { urls in
                               if !AirDropSender.send(urls) { notify("exclamationmark", "AirDrop bu dosyaları alamadı") }
                           },
                           addToShelf: { urls in
                               shelf.add(urls: urls)
                               notify("checkmark", "\(urls.count) öğe rafa eklendi")
                           },
                           openTarget: recentTargets.open)
        } else {
            switch layout.content {
            case .home:
                IslandWidgetStrip(store: widgets, media: media, timer: timer, clipboard: clipboard,
                                  aiActivity: aiActivity, systemMonitor: systemMonitor,
                                  processes: processes, watchers: watchers, recentFiles: recentFiles, tasks: tasks, launcher: launcher,
                                  weather: weather, shelf: shelf, note: note,
                                  preferences: preferences, width: layout.width,
                                  isLeaving: presentation.isLeaving, select: select,
                                  openSettings: openSettings, notify: notify)
            case .apps:
                appsContent
            case .files:
                if isLocked(.shelf) {
                    lockedContent(for: .shelf)
                } else {
                    filesContent
                }
            case .clipboard:
                if isLocked(.clipboard) {
                    lockedContent(for: .clipboard)
                } else {
                    IslandClipboardView(clipboard: clipboard, filter: $clipboardFilter, notify: notify)
                }
            case .timer:
                IslandTimerView(timer: timer)
            case .assistant:
                IslandAssistantView(session: assistant, captions: $preferences.assistantCaptions,
                                    showsPresence: !hasEars, close: closeAssistant)
            case .briefing:
                IslandBriefingView(briefing: briefing, close: closeBriefing, talk: startAssistant)
            case .agent:
                IslandAgentView(jobs: jobs, approve: approveProposal, refuse: refuseProposal,
                                dismiss: dismissAgent)
            }
        }
    }

    /// Whether the orb and status can sit beside the camera: only with a notch
    /// to sit beside.
    private var hasEars: Bool { presentation.cameraHeight > 0 && presentation.cameraWidth > 0 }

    /// Mirrors `IslandGeometry.assistantHeight`: false when the controller
    /// reserved no body, so the section does not leave a gap under the row.
    private var assistantHasBody: Bool {
        !hasEars || assistant.islandDetail(captions: preferences.assistantCaptions) != nil
            || assistant.confirmation != nil
    }

    @ViewBuilder private var appsContent: some View {
        IslandLauncherView(launcher: launcher, notify: notify)
    }

    /// Collapsed indicators. With nothing running the island renders nothing and takes no clicks.
    @ViewBuilder private var compact: some View {
        if collapsedIndicators.isEmpty {
            Color.clear.allowsHitTesting(false).accessibilityHidden(true)
        } else {
            Button(action: open) {
                HStack(spacing: MacBDesign.Space.regular) {
                    Spacer(minLength: 0)
                    ForEach(collapsedIndicators, id: \.label) { indicator in
                        HStack(spacing: MacBDesign.Space.tight) {
                            if indicator.isAssistant {
                                JarvisMiniOrb(state: assistant.state,
                                              level: assistant.state == .speaking ? assistant.outputLevel
                                                                                  : assistant.inputLevel)
                            } else if indicator.isPlayingMedia {
                                EqualizerBars(tint: indicator.tint, isPlaying: media.isPlaying, height: 10)
                            } else {
                                Image(systemName: indicator.symbol).font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                            }
                            Text(indicator.value).font(.system(size: MacBDesign.TypeScale.micro, weight: .medium)).monospacedDigit()
                        }
                        .foregroundStyle(indicator.tint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MacBDesign.Space.regular)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { statusLine }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(collapsedIndicators.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
        }
    }

    /// A hairline along the bottom of the closed island, filled as far as
    /// whatever is counting has got.
    ///
    /// One thing at a time, and the most urgent wins: a timer running out beats
    /// a battery filling, which beats a song playing. Nothing to count, no line.
    @ViewBuilder private var statusLine: some View {
        if let status = collapsedStatus {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MacBDesign.IslandToken.Fill.base)
                    Capsule().fill(status.tint)
                        .frame(width: proxy.size.width * min(1, max(0, status.fraction)))
                }
            }
            .frame(height: 2)
            .padding(.horizontal, MacBDesign.Space.regular)
            .padding(.bottom, MacBDesign.Space.hair)
            .motion(MacBDesign.Motion.normal, value: status.fraction)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private struct CollapsedStatus {
        let fraction: Double
        let tint: Color
    }

    private var collapsedStatus: CollapsedStatus? {
        if timer.isActive {
            return CollapsedStatus(fraction: timer.progress, tint: MacBDesign.IslandToken.accent)
        }
        if systemMonitor.snapshot.isCharging, let battery = systemMonitor.snapshot.batteryPercent {
            return CollapsedStatus(fraction: battery / 100, tint: Color(nsColor: .systemGreen))
        }
        if media.isPlaying, media.duration > 0 {
            return CollapsedStatus(fraction: media.position / media.duration,
                                   tint: media.tint ?? MacBDesign.IslandToken.primaryText.opacity(0.8))
        }
        return nil
    }

    private struct CollapsedIndicator {
        let symbol: String
        let value: String
        let label: String
        let tint: Color
        /// Drawn as moving bars rather than a static glyph.
        var isPlayingMedia = false
        /// Drawn as the assistant's own orb, which carries the state in its
        /// colour so the closed island needs no words for it.
        var isAssistant = false
    }

    private var collapsedIndicators: [CollapsedIndicator] {
        guard presentation.indicators else { return [] }
        var result: [CollapsedIndicator] = []
        if media.isPlaying {
            result.append(CollapsedIndicator(symbol: "waveform", value: mediaTitle, label: "Çalıyor",
                                             tint: media.tint ?? MacBDesign.IslandToken.primaryText,
                                             isPlayingMedia: true))
        }
        if timer.isActive {
            result.append(CollapsedIndicator(symbol: "timer", value: timer.remainingText,
                                             label: "Zamanlayıcı", tint: MacBDesign.IslandToken.accent))
        }
        if assistant.isActive {
            result.append(CollapsedIndicator(symbol: "waveform", value: assistantIndicator,
                                             label: "MacB", tint: MacBDesign.IslandToken.accent,
                                             isAssistant: true))
        }
        if keepAwake.isActive {
            result.append(CollapsedIndicator(symbol: "cup.and.heat.waves.fill", value: keepAwake.remainingText,
                                             label: "Uyanık", tint: MacBDesign.IslandToken.accent))
        }
        if !shelf.items.isEmpty {
            result.append(CollapsedIndicator(symbol: "tray.full.fill", value: "\(shelf.items.count)",
                                             label: "Rafta", tint: MacBDesign.IslandToken.secondaryText))
        }
        return result
    }

    /// What the closed island says while a conversation is running.
    private var assistantIndicator: String {
        switch assistant.state {
        case .listening: return "dinliyor"
        case .speaking: return "konuşuyor"
        case .thinking: return "düşünüyor"
        case .connecting: return "bağlanıyor"
        default: return "açık"
        }
    }

    private var peek: some View {
        IslandPeekView(chips: PeekModel.chips(peekInput), artwork: media.artwork,
                       mediaIsPlaying: media.isPlaying, open: open,
                       toggleMedia: media.playPause)
    }

    private var peekInput: PeekModel.Input {
        PeekModel.input(media: media, timer: timer, weather: weather, shelf: shelf,
                        aiActivity: aiActivity, systemMonitor: systemMonitor)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold)).frame(width: 27, height: 27).background(MacBDesign.IslandToken.Fill.hairline, in: Circle()) }
            .buttonStyle(.plain).foregroundStyle(MacBDesign.IslandToken.Ink.secondary).help(label).accessibilityLabel(label)
    }


    private var filesContent: some View {
        VStack(spacing: MacBDesign.Space.regular) {
            if !recentTargets.items.isEmpty {
                HStack(spacing: MacBDesign.Space.close) {
                    Text("Son hedefler").font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold)).foregroundStyle(MacBDesign.IslandToken.Ink.faint)
                    ForEach(recentTargets.items.prefix(3)) { target in
                        Button { recentTargets.open(target) } label: {
                            Text(target.appName).font(.system(size: MacBDesign.TypeScale.micro, weight: .medium)).lineLimit(1).padding(.horizontal, MacBDesign.Space.close).frame(height: 23).background(MacBDesign.IslandToken.Fill.low, in: Capsule())
                        }.buttonStyle(.plain).help("\(target.appName) uygulamasını aç")
                    }
                    Spacer()
                }
            }
            if shelf.items.isEmpty && recentFiles.items.isEmpty {
                Button(action: shelf.chooseFiles) {
                    HStack(spacing: MacBDesign.Space.regular) {
                        Image(systemName: presentation.isDropTarget ? "arrow.down" : "plus").font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
                        Text(presentation.isDropTarget ? "Bırak" : "Dosya ekle").font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                    }.frame(maxWidth: .infinity).frame(height: 64).background(MacBDesign.IslandToken.Fill.hairline, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain)
            } else {
                ScrollView {
                    LazyVStack(spacing: MacBDesign.Space.snug) {
                        ForEach(shelf.items) { item in fileRow(item) }
                        if preferences.recentFilesEnabled { ForEach(recentFiles.items) { item in recentFileRow(item) } }
                    }
                }.frame(maxHeight: 190).scrollIndicators(.hidden)
            }
            HStack {
                if let error = shelf.errorMessage { Text(error).foregroundStyle(.orange).lineLimit(1) }
                else { Text("\(shelf.items.count) öğe").foregroundStyle(MacBDesign.IslandToken.Ink.faint) }
                Spacer()
                if shelfPDFs.count > 1 {
                    Button { convert("PDF'ler birleştirildi") { try await ShelfConverter.merge(shelfPDFs) } } label: {
                        Label("\(shelfPDFs.count) PDF'i birleştir", systemImage: "arrow.triangle.merge")
                    }.buttonStyle(.plain).help("Sıradaki PDF'leri tek dosyada birleştir; asıllar olduğu gibi kalır")
                }
                if !shelfFiles.isEmpty {
                    Button {
                        if !ShelfConverter.airDrop(shelfFiles) { notify("exclamationmark.triangle", "AirDrop kullanılamıyor") }
                    } label: { Image(systemName: "dot.radiowaves.left.and.right").frame(width: 26, height: 24) }
                        .buttonStyle(.plain).help("Raftaki dosyaları AirDrop ile gönder")
                }
                Button(action: shelf.chooseFiles) { Image(systemName: "plus").frame(width: 26, height: 24) }.buttonStyle(.plain).help("Dosya ekle")
            }.font(.system(size: MacBDesign.TypeScale.micro))
        }
    }

    private func fileRow(_ item: ShelfItem) -> some View {
        HStack(spacing: MacBDesign.Space.tight) {
            NativeFileDragView(item: item).frame(height: 32)
            rowButton("doc.on.doc", "Kopyala") { shelf.copy(item: item); notify("doc.on.doc", "Kopyalandı") }
            if item.isAvailable, let url = item.url, !item.isDirectory { fileMenu(url) }
            rowButton("xmark", "Raftan kaldır") { shelf.remove(id: item.id) }
        }.padding(.horizontal, MacBDesign.Space.snug).background(MacBDesign.IslandToken.Fill.hairline, in: RoundedRectangle(cornerRadius: 9))
    }

    /// Files on the shelf that exist and are not folders, in shelf order.
    private var shelfFiles: [URL] {
        shelf.items.compactMap { item in item.isAvailable && !item.isDirectory ? item.url : nil }
    }

    private var shelfPDFs: [URL] { shelfFiles.filter(ShelfConversion.isPDF) }

    /// What else can be done with one file. Every conversion writes a new file
    /// beside the original and puts it on the shelf; the original is untouched.
    private func fileMenu(_ url: URL) -> some View {
        Menu {
            if ShelfConversion.canConvertToJPEG(url) {
                Button("JPEG kopyası oluştur") { convert("JPEG hazır") { try await ShelfConverter.jpegCopy(of: url) } }
            }
            if ShelfConversion.isImage(url) {
                Button("Küçük kopya oluştur (1600 px)") { convert("Küçük kopya hazır") { try await ShelfConverter.reducedCopy(of: url) } }
            }
            Button("AirDrop ile gönder") {
                if !ShelfConverter.airDrop([url]) { notify("exclamationmark.triangle", "AirDrop kullanılamıyor") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold)).frame(width: 25, height: 25)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(MacBDesign.IslandToken.Ink.tertiary)
        .help("Dönüştür veya gönder")
        .accessibilityLabel("Dosya işlemleri")
    }

    private func convert(_ done: String, _ work: @escaping () async throws -> URL) {
        Task { @MainActor in
            do {
                let result = try await work()
                shelf.add(urls: [result])
                notify("checkmark.circle", done)
            } catch {
                notify("exclamationmark.triangle", error.localizedDescription)
            }
        }
    }

    private func recentFileRow(_ item: RecentFileItem) -> some View {
        HStack(spacing: MacBDesign.Space.close) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill").frame(width: 18).foregroundStyle(MacBDesign.IslandToken.Ink.tertiary)
            Text(item.name).font(.system(size: MacBDesign.TypeScale.caption, weight: .medium)).lineLimit(1)
            Spacer()
            rowButton("plus", "Rafa ekle") { shelf.add(urls: [item.url]); notify("plus", "Rafa eklendi") }
        }.padding(.horizontal, MacBDesign.Space.close).frame(height: 32).background(MacBDesign.IslandToken.Fill.hairline, in: RoundedRectangle(cornerRadius: 9))
    }

    private var cameraCard: some View {
        Button(action: cameraAction) {
            ZStack(alignment: .bottomTrailing) {
                if camera.isRunning { CameraPreviewView(service: camera) }
                else { MacBDesign.IslandToken.Fill.hairline.overlay(ProgressView().controlSize(.small)) }
                Label("Büyüt", systemImage: "arrow.up.left.and.arrow.down.right").font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                    .padding(.horizontal, MacBDesign.Space.close).frame(height: 24).background(.black.opacity(0.6), in: Capsule()).padding(MacBDesign.Space.close)
            }.frame(height: 118).clipShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel("Kamera önizlemesini büyüt")
    }

    private func compactEmpty(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: MacBDesign.Space.comfortable) {
            Image(systemName: symbol).font(.system(size: MacBDesign.TypeScale.title, weight: .medium)).frame(width: 32, height: 32)
                .background(MacBDesign.IslandToken.Fill.low, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                Text(title).font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                Text(detail).font(.system(size: MacBDesign.TypeScale.micro)).foregroundStyle(MacBDesign.IslandToken.Ink.tertiary)
            }
            Spacer()
        }.padding(MacBDesign.Space.regular).background(MacBDesign.IslandToken.Fill.hairline, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// True when the section needs an unlock before it shows anything.
    private func isLocked(_ area: ProtectedArea) -> Bool {
        if faceUnlock.settings.guards(area) { return !faceUnlock.isUnlocked(area) }
        if preferences.protectPrivateTools, area == .clipboard { return !auth.isAuthenticated }
        return false
    }

    /// The locked panel. While a scan runs it becomes the scan animation, so the
    /// user can see the camera is on and see it stop.
    @ViewBuilder private func lockedContent(for area: ProtectedArea) -> some View {
        Button {
            select(area == .clipboard ? .clipboard : .files)
        } label: {
            Group {
                if case .idle = faceUnlock.phase {
                    VStack(spacing: MacBDesign.Space.regular) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: MacBDesign.TypeScale.heading, weight: .medium))
                            .symbolEffect(.pulse, isActive: auth.isAuthenticating)
                        Text(auth.isAuthenticating ? "Doğrulanıyor" : "\(area.title) kilitli")
                            .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                    }
                } else {
                    IslandFaceScanView(phase: faceUnlock.phase, instruction: faceUnlock.scanInstruction)
                        .padding(.horizontal, 18)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(MacBDesign.IslandToken.Fill.hairline, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(area.title) kilitli, açmak için seç")
    }

    private func sectionLabel(_ title: String) -> some View { Text(title).font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold)).foregroundStyle(MacBDesign.IslandToken.Ink.faint).padding(.horizontal, MacBDesign.Space.tight) }
    private func rowButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold)).frame(width: 25, height: 25) }
            .buttonStyle(.plain).foregroundStyle(MacBDesign.IslandToken.Ink.tertiary).help(label).accessibilityLabel(label)
    }
    private func toastView(_ toast: IslandToast) -> some View {
        Label(toast.message, systemImage: toast.symbol).font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
            .padding(.horizontal, MacBDesign.Space.regular).frame(height: 26).background(MacBDesign.IslandToken.Fill.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(MacBDesign.IslandToken.Fill.low))
    }
    private var mediaTitle: String { media.title.isEmpty ? media.source.title : media.title }
    private var mediaSubtitle: String { media.artist.isEmpty ? media.source.title : "\(media.artist) · \(media.source.title)" }
    private func cover(size: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [MacBDesign.IslandToken.Fill.base, MacBDesign.IslandToken.Fill.hairline], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let artwork = media.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
            else { Image(systemName: media.source == .none ? "play.rectangle.fill" : media.source.symbol).font(.system(size: size * 0.3, weight: .semibold)).foregroundStyle(MacBDesign.IslandToken.Ink.secondary) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius)).overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(MacBDesign.IslandToken.Fill.low)).accessibilityHidden(true)
    }
    private func playbackButton(_ icon: String, label: String, size: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: prominent ? MacBDesign.TypeScale.emphasis : MacBDesign.TypeScale.caption, weight: .semibold)).foregroundStyle(prominent ? .black : MacBDesign.IslandToken.Ink.primary).frame(width: size, height: size).background(prominent ? .white : MacBDesign.IslandToken.Fill.low, in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}

/// The island folding with the lid.
///
/// The rotation is around the top edge, which is where the hinge is, so the
/// island lies down into the bezel rather than shrinking in place. It is driven
/// straight from the sensor, so it tracks the hand on the screen instead of
/// playing a canned animation, and it is skipped entirely when the system asks
/// for reduced motion.
private struct HingeFold: ViewModifier {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion || progress <= 0.001 {
            content
        } else {
            content
                .rotation3DEffect(.degrees(-86 * progress), axis: (x: 1, y: 0, z: 0),
                                  anchor: .top, perspective: 0.55)
                .scaleEffect(x: 1 - 0.06 * progress, anchor: .top)
                // Straight-line, like the fold itself: one degree of hinge is
                // one step of blur, all the way down. A curve here makes the
                // picture lag the hand turning the lid.
                .blur(radius: 16 * progress)
                .opacity(1 - 0.85 * progress)
                // Short enough to feel attached to the hinge, long enough that a
                // jittery reading does not look like a stutter.
                .motion(MacBDesign.Motion.tracking, value: progress)
        }
    }
}
