import PhotosUI
import SwiftUI

/// Playback presets with their details tucked away, sound, and appearance.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PlaybackPreferences.startFromBeginningKey) private var startFromBeginning = false
    @AppStorage(PlaybackPreferences.videoQualityKey) private var videoQuality = VideoQualityMode.standard
    @AppStorage(PlaybackPreferences.dialogueBoostKey) private var dialogueBoost = false
    @AppStorage(PlaybackPreferences.nightModeKey) private var nightMode = false
    @AppStorage(PlaybackPreferences.balanceKey) private var balance = 0.0
    @AppStorage(AccentChoice.key) private var accent = AccentChoice.silver
    @AppStorage(Wallpaper.key) private var wallpaper = Wallpaper.ink
    @AppStorage("wallpaperRevision") private var wallpaperRevision = 0
    @AppStorage(AccessibilityPreferences.largeControlsKey) private var largeControls = false
    @AppStorage(AccessibilityPreferences.highContrastKey) private var highContrast = false
    @State private var showingDetails = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoError: String?

    private var preset: PlaybackPreset? {
        PlaybackPreset.matching(videoQuality: videoQuality, dialogueBoost: dialogueBoost, nightMode: nightMode)
    }

    var body: some View {
        NavigationStack {
            Form {
                playback
                sound
                appearance
                accessibility
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    // MARK: Playback

    private var playback: some View {
        Section {
            Toggle("Always Watch from Beginning", isOn: $startFromBeginning)
            Picker("Preset", selection: Binding(
                get: { preset },
                set: { if let new = $0 { choose(new) } }
            )) {
                ForEach(PlaybackPreset.allCases) { Text($0.title).tag(Optional($0)) }
                if preset == nil { Text("Custom").tag(PlaybackPreset?.none) }
            }
            DisclosureGroup("Details", isExpanded: $showingDetails) {
                Picker("Picture", selection: $videoQuality) {
                    ForEach(VideoQualityMode.allCases) { Text($0.title).tag($0) }
                }
                Text("Picture settings apply to MKV and other formats played by the extended player. MP4 and MOV always play at full quality in hardware.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Playback")
        } footer: {
            Text(preset?.summary ?? "Your own mix of the settings below.")
        }
    }

    private func choose(_ preset: PlaybackPreset) {
        videoQuality = preset.videoQuality
        dialogueBoost = preset.sound.dialogueBoost
        nightMode = preset.sound.nightMode
    }

    // MARK: Sound

    private var sound: some View {
        Section {
            Toggle("Boost Dialogue", isOn: $dialogueBoost)
            Toggle("Night Mode", isOn: $nightMode)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Balance")
                    Spacer()
                    Text(balanceLabel).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack {
                    Text("L").font(.caption).foregroundStyle(.secondary)
                    // Snaps to the centre so "even" is easy to find again.
                    Slider(value: Binding(get: { balance }, set: { balance = abs($0) < 0.06 ? 0 : $0 }), in: -1...1)
                    Text("R").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Sound")
        } footer: {
            Text("Boost Dialogue lifts voices. Night Mode evens out loud and quiet scenes. Both can also be changed from the speaker button while watching.")
        }
    }

    private var balanceLabel: String {
        if balance == 0 { return "Centre" }
        return "\(Int((abs(balance) * 100).rounded()))% \(balance < 0 ? "Left" : "Right")"
    }

    // MARK: Accessibility

    private var accessibility: some View {
        Section {
            Toggle("Larger Player Controls", isOn: $largeControls)
            Toggle("High Contrast", isOn: $highContrast)
        } header: {
            Text("Accessibility")
        } footer: {
            Text("Text follows the size set in Settings > Display & Brightness > Text Size. High Contrast is also on whenever Increase Contrast is on in the system settings. With a keyboard: Space plays and pauses, arrows skip and change volume, C cycles subtitles, B saves a moment, P starts Picture in Picture.")
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Accent")
                HStack(spacing: 12) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button { accent = choice } label: {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if accent == choice {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(choice.onAccent)
                                    }
                                }
                                .overlay(Circle().strokeBorder(.white.opacity(accent == choice ? 0.9 : 0.15), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(accent == choice ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("Wallpaper")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(Wallpaper.builtIn + (Wallpaper.hasPhoto ? [.photo] : [])) { choice in
                        Button { wallpaper = choice } label: {
                            VStack(spacing: 4) {
                                WallpaperSwatch(wallpaper: choice, photo: choice == .photo ? Wallpaper.loadPhoto() : nil)
                                    .frame(height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(wallpaper == choice ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.15)),
                                                      lineWidth: wallpaper == choice ? 3 : 1))
                                Text(choice.title).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(wallpaper == choice ? .isSelected : [])
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(Wallpaper.hasPhoto ? "Choose a Different Photo…" : "Use a Photo…", systemImage: "photo")
                }
                if let photoError {
                    Text(photoError).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), Wallpaper.savePhoto(data) {
                    wallpaperRevision += 1
                    wallpaper = .photo
                    photoError = nil
                } else {
                    photoError = "That photo couldn't be used."
                }
                photoItem = nil
            }
        }
    }
}
