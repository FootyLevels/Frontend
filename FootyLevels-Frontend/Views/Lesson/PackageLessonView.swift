import SwiftUI

/// Plays one lesson made by the lesson pipeline: every skill in the video, each from
/// watching it to doing it. Everything shown comes from the lesson bundle.
struct PackageLessonView: View {
    let entry: LessonLibrary.Entry
    /// The stage the lesson opens on. Learn's practise card opens straight to Practise.
    var startStage: LessonStage = .watch

    @State private var model: PackageLessonModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let model {
                PackageLessonScreen(model: model)
            } else if let loadError {
                ContentUnavailableView("Lesson unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SL.page)
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        // A lesson has the whole screen; the tab bar would cover its sheet.
        .toolbar(.hidden, for: .tabBar)
        .task {
            guard model == nil, loadError == nil else { return }
            do {
                let lesson = try PackageLessonModel.load(entry.url)
                model = lesson
                await lesson.load()
                lesson.enter(startStage)
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onDisappear { model?.pause() }
    }
}

/// The video (or the 3D body) fills the screen, and the lesson sits in a sheet over it.
/// Slid away, the sheet leaves the key point in an island and a pill to bring it back.
/// The skill and the View options are in the navigation bar.
private struct PackageLessonScreen: View {
    let model: PackageLessonModel

    @State private var main: LessonMainView = .video
    @State private var detent: LessonSheetDetent = .peek
    /// The sheet's chosen row per stage, which the island also shows.
    @State private var picked: [LessonStage: String] = [:]
    @State private var headerHeight: CGFloat = 240
    @State private var showingView = false
    @State private var viewHeight: CGFloat = 520
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let screen = geo.size.height + insets.top + insets.bottom
            let layout = LessonSheetLayout(screenHeight: screen, headerHeight: headerHeight,
                                           bottomInset: insets.bottom, topReserve: insets.top + 12)
            ZStack(alignment: .bottom) {
                LessonMediaStage(model: model, main: $main,
                                 covered: showingView ? Swift.min(viewHeight, screen * 0.9) : layout.height(detent),
                                 top: insets.top)
                if detent == .hidden {
                    LessonWatchOverlay(model: model, selected: picked[model.stage], bottomInset: insets.bottom) {
                        detent = .peek
                    }
                    .transition(.opacity.combined(with: .offset(y: 20)))
                }
                PackageLessonSheet(model: model, detent: $detent, picked: $picked, layout: layout,
                                   onHeaderHeight: { headerHeight = $0 },
                                   openView: { showingView = true })
            }
            .ignoresSafeArea(edges: .bottom)
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: detent == .hidden)
        }
        .toolbar {
            // The skill pill names what's playing, so the bar shows no title.
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
            if model.package.document.skills.count > 1 {
                ToolbarItem(placement: .topBarLeading) { SkillMenu(model: model) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ViewButton(lit: main == .body || model.mirror) { showingView = true }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        // Light bar content over the video; dark over the light 3D stage.
        .toolbarColorScheme(main == .body && colorScheme == .light ? .light : .dark, for: .navigationBar)
        .sheet(isPresented: $showingView) {
            LessonViewOptions(model: model, main: $main) { viewHeight = $0 }
                .presentationDetents(viewHeight > 620 ? [.large] : [.height(viewHeight)])
                .presentationDragIndicator(.visible)
                .presentationBackground(SL.card)
                .presentationCornerRadius(28)
                // The 3D stays live above the sheet, so each change shows as it's made.
                .presentationBackgroundInteraction(.enabled)
        }
    }
}

/// Picks which of the video's skills the lesson teaches.
private struct SkillMenu: View {
    let model: PackageLessonModel

    var body: some View {
        Menu {
            Picker("Skill", selection: Binding(get: { model.skill.id }, set: { model.select($0) })) {
                ForEach(model.package.document.skills) { skill in
                    Text(skill.short).tag(skill.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(model.skill.short)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(.caption, weight: .semibold))
            }
            // White over the video, black over the light 3D stage: the bar's own colour.
            .foregroundStyle(.primary)
        }
        .tint(.primary)
        .accessibilityLabel("Skill: \(model.skill.short)")
        .accessibilityHint("Changes the skill")
        .disabled(!model.isReady)
    }
}

/// Opens View. Filled white while the 3D body or Mirror is on, so a changed view shows.
private struct ViewButton: View {
    let lit: Bool
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *), lit {
            button.buttonStyle(.glassProminent).tint(.white)
        } else if lit {
            button.background(Color.white, in: Circle())
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(lit ? Color.black : Color.white)
        }
        .accessibilityLabel("View options")
        .accessibilityValue(lit ? "Changed" : "")
    }
}
