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
    /// The island is glass from edge to edge, so this setting is not a detail
    /// here: with it on, every translucent surface in the panel goes solid.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increaseContrast: Bool { colorSchemeContrast == .increased }

    /// The window is larger than the island and never resizes while it
    /// moves (see `IslandEnvelope`); the island sits at its top centre and
    /// everything around it is transparent.
    var body: some View {
        island
            .modifier(HingeFold(progress: lid.foldProgress))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
            .onExitCommand(perform: close)
    }

    private var isCollapsed: Bool { presentation.layout.phase == .collapsed }

    /// The shape itself: surface, content, rim and shadow, clipped to the
    /// notch-grown outline. Its size and corners are the only things that
    /// animate for an open or a close, on one spring set by the controller.
    private var island: some View {
        islandContent
            .frame(width: presentation.width + 2 * silhouette.shoulder,
                   height: presentation.height + IslandEnvelope.topBleed, alignment: .top)
            .clipShape(outline)
            // The surface sits behind the clipped content, outside any
            // compositing group: Liquid Glass has to see the desktop behind
            // the window, and a flattened group would hide it.
            .background { islandSurface }
            .overlay(outline.stroke(surfaceStrokeStyle, lineWidth: isCollapsed ? 0 : 0.8))
    }

    private var islandContent: some View {
        ZStack(alignment: .top) {
            Group {
                if presentation.transition < 1 {
                    content(presentation.previousLayout, isInteractive: false)
                        .opacity(1 - presentation.transition)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                content(presentation.layout, isInteractive: true)
                    .opacity(presentation.transition)
                if let toast = presentation.toast {
                    toastView(toast)
                        .padding(.top, presentation.cameraHeight + 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            // On the way out the content goes first, softly, and the shape
            // follows it.
            .blur(radius: presentation.isLeaving ? IslandMotion.leaveBlur : 0)
            .opacity(presentation.isLeaving ? 0 : 1)
            .padding(.top, IslandEnvelope.topBleed)
        }
    }

    private var silhouette: IslandSilhouette {
        IslandSilhouette.forBody(height: presentation.height + IslandEnvelope.topBleed,
                                 radius: presentation.radius,
                                 underNotch: presentation.cameraHeight > 0)
    }

    private var outline: IslandOutlineShape { IslandOutlineShape(silhouette: silhouette) }

    private var carriesGlass: Bool {
        guard !reduceTransparency else { return false }
        return preferences.islandAppearance == .liquidGlass || preferences.islandAppearance == .blackGlass
    }

    /// Pure black by default, like the notch it grows out of. Liquid Glass
    /// is Apple's own glass in the island's outline, nothing laid over it;
    /// Black Glass is the same glass tinted dark, as much as the slider
    /// says. The closed strip stays black so it never outlines the camera.
    @ViewBuilder private var islandSurface: some View {
        if isCollapsed && collapsedIndicators.isEmpty && presentation.hud == nil {
            // Nothing to show: the island is not there, and the hardware notch
            // is left to be itself.
            Color.clear
        } else if isCollapsed || !carriesGlass && preferences.islandAppearance != .customImage {
            blackSurface
        } else {
            switch preferences.islandAppearance {
            case .pureBlack:
                blackSurface
            case .liquidGlass, .blackGlass:
                glassSurface(dark: preferences.islandAppearance == .blackGlass)
            case .customImage:
                if let image = background.image {
                    ZStack {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        Color.black.opacity(0.35 + 0.5 * (1 - preferences.islandTranslucency))
                    }
                    .clipShape(outline)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                } else {
                    blackSurface
                }
            }
        }
    }

    /// A plain shadow, no coloured glow: the open island is an object
    /// standing off the screen. A collapsed island is flush with the bezel
    /// and casts nothing.
    private var blackSurface: some View {
        outline.fill(Color.black)
            .shadow(color: .black.opacity(isCollapsed ? 0 : 0.5), radius: isCollapsed ? 0 : 18, y: isCollapsed ? 0 : 8)
    }

    @ViewBuilder private func glassSurface(dark: Bool) -> some View {
        if #available(macOS 26.0, *) {
            let glass: Glass = dark
                ? .regular.tint(.black.opacity(0.25 + 0.6 * (1 - preferences.islandTranslucency)))
                : .regular
            Color.clear.glassEffect(glass, in: outline)
        } else {
            outline.fill(.ultraThinMaterial)
        }
    }

    /// A faint rim: light along the top edge, almost nothing down the sides.
    /// Pure black gets only a hairline, and only with Increase Contrast.
    private var surfaceStrokeStyle: AnyShapeStyle {
        if isCollapsed { return AnyShapeStyle(Color.clear) }
        if preferences.islandAppearance == .pureBlack || reduceTransparency {
            return AnyShapeStyle(increaseContrast ? Color.white.opacity(0.45) : Color.white.opacity(0.06))
        }
        return AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05), .white.opacity(0.10)],
                                            startPoint: .top, endPoint: .bottom))
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
        case .expanded where layout.isAssistantCompact:
            IslandAssistantPanel(session: assistant, captions: $preferences.assistantCaptions,
                                 cameraHeight: hasEars ? presentation.cameraHeight : 0,
                                 earWidth: hasEars
                                    ? IslandGeometry.assistantEarContentWidth(panelWidth: layout.width,
                                                                              notchWidth: presentation.cameraWidth)
                                    : 0,
                                 showsInput: layout.showsAssistantInput, isInteractive: isInteractive,
                                 close: closeAssistant, openSettings: openSettings)
                .frame(width: layout.width, height: layout.height, alignment: .top).clipped()
        case .expanded where presentation.cameraHeight > 0 && presentation.cameraWidth > 0:
            VStack(spacing: 0) {
                // The tabs live in the camera's ears, the way the hardware
                // notch leaves room for them: sections left, tools right.
                HStack(spacing: 0) {
                    navigation(.sections)
                    Spacer(minLength: presentation.cameraWidth + 16)
                    navigation(.tools)
                }
                .padding(.horizontal, IslandGeometry.horizontalPadding)
                .frame(height: presentation.cameraHeight)
                VStack(spacing: IslandGeometry.gap) {
                    if presentation.cameraPreviewVisible { cameraCard } else { section(layout) }
                }
                .padding(.horizontal, IslandGeometry.horizontalPadding)
                .padding(.top, IslandGeometry.topPadding)
                .padding(.bottom, IslandGeometry.bottomPadding)
            }.frame(width: layout.width, height: layout.height, alignment: .top).clipped()
        case .expanded:
            VStack(spacing: 0) {
                Color.clear.frame(height: presentation.cameraHeight)
                VStack(spacing: IslandGeometry.gap) {
                    // The target section, not this copy's. Both copies of the
                    // panel are on screen during a cross-fade, and a row that
                    // disagrees with itself shows two pucks at once.
                    IslandNavigation(selected: presentation.layout.content, isEditing: widgets.isEditing,
                                     battery: batteryReading,
                                     select: select,
                                     toggleEditing: { widgets.isEditing.toggle() },
                                     cameraAction: cameraAction, openSettings: openSettings)
                    if presentation.cameraPreviewVisible { cameraCard } else { section(layout) }
                }
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
                IslandPlayerView(media: media, width: layout.width - 2 * IslandGeometry.horizontalPadding)
            case .stats:
                IslandStatsView(monitor: systemMonitor)
            case .widgets:
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
                // Reached only while a drop or the camera preview has the
                // panel; the conversation itself is `IslandAssistantPanel`.
                EmptyView()
            case .briefing:
                IslandBriefingView(briefing: briefing, close: closeBriefing, talk: startAssistant)
            case .agent:
                IslandAgentView(jobs: jobs, approve: approveProposal, refuse: refuseProposal,
                                dismiss: dismissAgent)
            }
        }
    }

    private func navigation(_ part: IslandNavigation.Part) -> some View {
        // The target section, not this copy's: both copies of the panel are
        // on screen during a cross-fade.
        IslandNavigation(selected: presentation.layout.content, part: part, isEditing: widgets.isEditing,
                         battery: batteryReading,
                         select: select, toggleEditing: { widgets.isEditing.toggle() },
                         cameraAction: cameraAction, openSettings: openSettings)
    }

    private var batteryReading: (percent: Double, isCharging: Bool)? {
        systemMonitor.snapshot.batteryPercent.map { ($0, systemMonitor.snapshot.isCharging) }
    }

    /// Whether the orb and status can sit beside the camera: only with a notch
    /// to sit beside.
    private var hasEars: Bool { presentation.cameraHeight > 0 && presentation.cameraWidth > 0 }

    @ViewBuilder private var appsContent: some View {
        IslandLauncherView(launcher: launcher, notify: notify)
    }

    /// The closed island: the notch with two small wings for the one thing
    /// that matters most right now — a picture on the left, a live reading on
    /// the right. With nothing running it renders nothing and takes no clicks.
    @ViewBuilder private var compact: some View {
        if let hud = presentation.hud {
            hudWings(hud)
        } else if let activity = activities.first {
            Button(action: open) {
                HStack(spacing: 0) {
                    leftWing(activity)
                        .frame(width: activity.wing)
                        .overlay(alignment: .bottomTrailing) { secondaryBadge }
                    Spacer(minLength: 0)
                    rightWing(activity)
                        .frame(width: activity.wing)
                }
                .id(activity)
                .transition(.blurReplace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .motion(MacBDesign.Motion.gentle, value: activity)
            .accessibilityLabel(collapsedIndicators.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
        } else {
            Color.clear.allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    /// A level that just changed: its symbol on the left, a meter and the
    /// number on the right.
    private func hudWings(_ hud: IslandHUD) -> some View {
        let tint: Color = hud.kind == .brightness ? Color(red: 1, green: 0.84, blue: 0.35) : .white
        return HStack(spacing: 0) {
            Image(systemName: hud.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: IslandHUD.wing - 24, alignment: .leading)
                .padding(.leading, 18)
                .frame(width: IslandHUD.wing, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule().fill(tint).frame(width: max(5, proxy.size.width * hud.shownLevel))
                    }
                }
                .frame(height: 5)
                Text(hud.percentText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
                    .frame(width: 22, alignment: .trailing)
            }
            .padding(.trailing, 16)
            .frame(width: IslandHUD.wing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.blurReplace)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hud.accessibilityText)
    }

    /// The same order the controller sizes the island by.
    private var activities: [IslandActivity] {
        guard presentation.indicators else { return [] }
        return IslandActivity.running(assistant: assistant.isActive, timer: timer.isActive, music: media.isPlaying,
                                      keepAwake: keepAwake.isActive, shelf: !shelf.items.isEmpty)
    }

    @ViewBuilder private func leftWing(_ activity: IslandActivity) -> some View {
        switch activity {
        case .music:
            if let artwork = media.artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            } else {
                Image(systemName: "music.note").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(media.tint ?? .white)
            }
        case .timer:
            ZStack {
                Circle().stroke(.white.opacity(0.16), lineWidth: 2.5)
                Circle().trim(from: 0, to: max(0.02, 1 - timer.progress))
                    .stroke(MacBDesign.IslandToken.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .motion(MacBDesign.Motion.progress, value: timer.progress)
            }
            .frame(width: 15, height: 15)
        case .assistant:
            JarvisMiniOrb(state: assistant.state,
                          level: assistant.state == .speaking ? assistant.outputLevel : assistant.inputLevel)
                .frame(width: 16, height: 16)
        case .keepAwake:
            Image(systemName: "cup.and.heat.waves.fill").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.accent)
        case .shelf:
            Image(systemName: "tray.full.fill").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    @ViewBuilder private func rightWing(_ activity: IslandActivity) -> some View {
        switch activity {
        case .music:
            EqualizerBars(tint: media.tint ?? .white, isPlaying: media.isPlaying, height: 12)
                .frame(width: 16)
        case .timer:
            wingReading(timer.remainingText, tint: MacBDesign.IslandToken.accent)
        case .assistant:
            EqualizerBars(tint: MacBDesign.IslandToken.accent,
                          isPlaying: assistant.state == .speaking || assistant.state == .listening, height: 12)
                .frame(width: 16)
        case .keepAwake:
            wingReading(keepAwake.remainingText, tint: .white.opacity(0.85))
        case .shelf:
            wingReading("\(shelf.items.count)", tint: .white.opacity(0.85))
        }
    }

    private func wingReading(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .contentTransition(.numericText())
            .motion(MacBDesign.Motion.gentle, value: text)
    }

    /// Something else is running too: a dot on the picture says so, and the
    /// open panel says what.
    @ViewBuilder private var secondaryBadge: some View {
        if activities.count > 1 {
            Circle().fill(MacBDesign.IslandToken.accent)
                .frame(width: 5, height: 5)
                .overlay(Circle().strokeBorder(.black, lineWidth: 1))
                .offset(x: -8, y: -6)
                .accessibilityHidden(true)
        }
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
        IslandPeekView(parts: PeekModel.parts(peekInput), artwork: media.artwork,
                       tint: media.tint, mediaIsPlaying: media.isPlaying,
                       keepAwakeIsOn: keepAwake.isActive,
                       open: open, toggleMedia: media.playPause,
                       openClipboard: { select(.clipboard) }, openShelf: { select(.files) },
                       run: run)
    }

    private var peekInput: PeekModel.Input {
        PeekModel.input(media: media, timer: timer, shelf: shelf,
                        clipboard: clipboard, clipboardLocked: isLocked(.clipboard))
    }

    /// The strip's own buttons. Each one is something the island can do
    /// without opening: nothing here needs a panel.
    private func run(_ action: PeekAction) {
        switch action {
        case .assistant:
            startAssistant()
        case .screenshot:
            // The selection screenshot macOS itself takes; MacB never captures
            // a screen on its own.
            close()
            SystemActions.captureSelectionToClipboard()
        case .keepAwake:
            if keepAwake.isActive { keepAwake.stop() } else { _ = keepAwake.toggle(minutes: 60) }
        }
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

    /// The camera fills the panel on its own: a mirror is something to look
    /// at, not a strip above a list.
    private var cameraCard: some View {
        Button(action: cameraAction) {
            ZStack(alignment: .bottomTrailing) {
                if camera.isRunning {
                    CameraPreviewView(service: camera)
                } else {
                    Color.white.opacity(0.06).overlay {
                        if let message = camera.errorMessage {
                            VStack(spacing: 10) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                Text("Yeniden denemek için dokun")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 24)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                Label("Büyüt", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                    .padding(.horizontal, MacBDesign.Space.close)
                    .frame(height: 24)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(MacBDesign.Space.close)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kamera önizlemesini büyüt")
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

/// `IslandSilhouette` as a SwiftUI shape, animatable, so the shoulders and the
/// corners move on the same spring as the size.
struct IslandOutlineShape: Shape {
    var silhouette: IslandSilhouette

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(silhouette.shoulder, AnimatablePair(silhouette.topRadius, silhouette.bottomRadius)) }
        set {
            silhouette.shoulder = newValue.first
            silhouette.topRadius = newValue.second.first
            silhouette.bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path { Path(silhouette.path(in: rect)) }
}
