import AfterglowAudio
import AfterglowCore
import AfterglowGlow
import SwiftUI

struct GlowStudioScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var previewIsLive = false

    var body: some View {
        @Bindable var settings = env.settings
        let glow = settings.settings.glow
        let palette = env.nowPlaying.palette

        ZStack {
            AmbientBackdrop(artwork: nil, palette: palette, intensity: 0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    header

                    VStack(spacing: DS.Space.s3) {
                        DevicePreview(
                            configuration: .init(settings: glow, colors: env.glowColors, isPlaying: env.nowPlaying.isPlaying),
                            palette: palette,
                            onSignalChange: { live in previewIsLive = live }
                        )
                        .frame(maxWidth: 820)
                        HStack(spacing: DS.Space.s2) {
                            if previewIsLive {
                                StatusPill(text: "Live audio", symbol: "waveform", color: .green)
                            } else {
                                StatusPill(text: "Demo signal: play music to preview with your own sound", symbol: "waveform.path")
                            }
                            StatusPill(text: glow.style.preset.displayName, symbol: "sparkles")
                            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                                StatusPill(text: "Reduce Motion is on, so movement is paused", symbol: "figure.walk.motion", color: .orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    PresetGallery()

                    ControlsGrid()
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var header: some View {
        @Bindable var settings = env.settings
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Edge Glow").font(DS.Font.display)
                Text("Ambient light around your display that moves with your music.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Toggle(isOn: $settings.settings.glow.isEnabled) {
                    Text(settings.settings.glow.isEnabled ? "On your screen" : "Show on screen")
                        .font(.system(size: 13, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.large)
                AudioStatusRow(state: env.audio.state, preset: settings.settings.glow.style.preset, waitingForPermission: env.audio.isWaitingForPermission)
                    .frame(maxWidth: 320, alignment: .trailing)
            }
        }
    }
}

// MARK: Presets

private struct PresetGallery: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Presets").font(.system(size: 20, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 196, maximum: 280), spacing: DS.Space.s4)], spacing: DS.Space.s4) {
                ForEach(GlowPreset.allCases) { preset in
                    PresetCard(preset: preset)
                }
            }
        }
    }
}

private struct PresetCard: View {
    @Environment(AppEnvironment.self) private var env
    var preset: GlowPreset
    @State private var hovering = false

    var body: some View {
        let glow = env.settings.settings.glow
        let selected = glow.style.preset == preset
        var cardSettings = glow
        cardSettings.style.preset = preset
        cardSettings.idleBehavior = .steady

        return Button {
            withAnimation(DS.Motion.snappy) { env.settings.settings.glow.style.preset = preset }
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ZStack {
                    Color(white: 0.03)
                    GlowPreview(configuration: .init(
                        settings: cardSettings, colors: env.glowColors,
                        isPlaying: env.nowPlaying.isPlaying, referenceWidth: 1100, showsNotch: false,
                        maximumFrameRate: 24
                    ))
                }
                .aspectRatio(16.0 / 10, contentMode: .fit)
                .clipShape(.rect(cornerRadius: DS.Radius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(preset.displayName).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else if preset.usesAudio {
                            Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(.tertiary)
                                .help("Reacts to audio")
                        }
                    }
                    Text(preset.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .padding(DS.Space.s3)
            .background(.white.opacity(selected ? 0.1 : (hovering ? 0.07 : 0.04)), in: .rect(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.white.opacity(0.08)), lineWidth: selected ? 1.5 : 0.5)
            }
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DS.Motion.snappy, value: hovering)
        .accessibilityLabel("\(preset.displayName) preset")
        .accessibilityHint(preset.summary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Controls

private struct ControlsGrid: View {
    @Environment(AppEnvironment.self) private var env
    @State private var newPresetName = ""

    var body: some View {
        @Bindable var settings = env.settings
        let glow = $settings.settings.glow
        let style = glow.style
        let tint = env.nowPlaying.palette.glowColors[0].color
        let percent: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }
        let points: (Double) -> String = { "\(Int($0.rounded())) pt" }
        let times: (Double) -> String = { String(format: "%.1f×", $0) }

        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s4, alignment: .top), GridItem(.flexible(), spacing: DS.Space.s4, alignment: .top)], spacing: DS.Space.s4) {
            GlassCard(title: "Light", symbol: "light.max") {
                ValueSlider(title: "Intensity", value: style.intensity, range: 0...1, format: percent, tint: tint)
                ValueSlider(title: "Thickness", value: style.thickness, range: 2...40, format: points, tint: tint)
                ValueSlider(title: "Spread", value: style.spread, range: 20...320, format: points, tint: tint)
                ValueSlider(title: "Softness", value: style.blur, range: 0...1, format: percent, tint: tint)
                ValueSlider(title: "Corner radius", value: glow.cornerRadius, range: 0...40, format: points, tint: tint)
            }

            GlassCard(title: "Motion", symbol: "wind") {
                ValueSlider(title: "Speed", value: style.animationSpeed, range: 0.1...3, format: times, tint: tint)
                ValueSlider(title: "Gradient angle", value: style.gradientAngle, range: 0...360, format: { "\(Int($0))°" }, tint: tint)
                LabeledPicker(title: "When nothing is playing", selection: glow.idleBehavior, options: GlowIdleBehavior.allCases) { $0.displayName }
            }

            GlassCard(title: "Audio response", symbol: "waveform",
                      caption: "Afterglow analyses the sound your Mac plays only to animate light. It stays in memory and is never recorded or uploaded.") {
                Group {
                    ValueSlider(title: "Sensitivity", value: style.audioSensitivity, range: 0...2, format: times, tint: tint)
                    ValueSlider(title: "Bass sensitivity", value: style.bassSensitivity, range: 0...2, format: times, tint: tint)
                    ValueSlider(title: "Response speed", value: style.responseSpeed, range: 0...1, format: percent, tint: tint)
                    Toggle("Beat synchronisation", isOn: style.beatSync)
                    Toggle("React to all apps' audio", isOn: glow.reactToAllAudio)
                        .help("Also light up for browsers and video. Off saves battery: audio is only analysed while Spotify or Music is playing.")
                }
                .disabled(!style.wrappedValue.preset.usesAudio)
                if !style.wrappedValue.preset.usesAudio {
                    Text("Ambient doesn't use audio.").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }

            GlassCard(title: "Colour", symbol: "paintpalette") {
                Toggle("Match album artwork", isOn: style.useArtworkColors)
                HStack(spacing: 6) {
                    ForEach(Array(env.glowColors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color.color).frame(width: 22, height: 22)
                            .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                    }
                    Spacer()
                    if style.wrappedValue.useArtworkColors {
                        Text("From current artwork").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                if !style.wrappedValue.useArtworkColors {
                    HStack {
                        ColorPicker("Primary", selection: colorBinding(style.primaryColor), supportsOpacity: false)
                        ColorPicker("Secondary", selection: colorBinding(style.secondaryColor), supportsOpacity: false)
                    }
                    HStack(spacing: DS.Space.s2) {
                        ForEach(ColorPair.all) { pair in
                            Button {
                                env.settings.settings.glow.style.primaryColor = pair.primary
                                env.settings.settings.glow.style.secondaryColor = pair.secondary
                            } label: {
                                Capsule()
                                    .fill(LinearGradient(colors: [pair.primary.color, pair.secondary.color], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 44, height: 18)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .help(pair.name)
                            .accessibilityLabel("\(pair.name) colours")
                        }
                    }
                }
            }

            GlassCard(title: "Displays", symbol: "display.2",
                      caption: "The glow can't appear over the login screen, Mission Control, or games that take exclusive control of a display.") {
                Picker("Show on", selection: glow.displays) {
                    Text("All displays").tag(DisplaySelection.all)
                    Text("Main display").tag(DisplaySelection.main)
                    ForEach(EdgeGlowRenderer.availableDisplays) { display in
                        Text(display.name).tag(DisplaySelection.specific([display.id]))
                    }
                }
                LabeledPicker(title: "Notch", selection: glow.notchMode, options: NotchMode.allCases) { $0.displayName }
                Toggle("HDR highlights", isOn: glow.hdrHighlights)
                    .help("On XDR and HDR displays, highlights shine brighter than white. Uses more power.")
            }

            GlassCard(title: "Your presets", symbol: "square.stack") {
                if glow.wrappedValue.customPresets.isEmpty {
                    Text("Save the current look to come back to it anytime.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(glow.wrappedValue.customPresets) { preset in
                    HStack {
                        Text(preset.name).font(.system(size: 12, weight: .medium))
                        Text(preset.style.preset.displayName).font(.system(size: 11)).foregroundStyle(.tertiary)
                        Spacer()
                        Button("Apply") {
                            withAnimation { env.settings.settings.glow.style = preset.style }
                        }
                        .controlSize(.small)
                        Button(role: .destructive) {
                            env.settings.settings.glow.customPresets.removeAll { $0.id == preset.id }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(preset.name)")
                    }
                }
                HStack {
                    TextField("Name", text: $newPresetName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        let name = newPresetName.trimmingCharacters(in: .whitespaces)
                        env.settings.settings.glow.customPresets.append(CustomGlowPreset(name: name, style: style.wrappedValue))
                        newPresetName = ""
                    }
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Reset look to defaults") {
                    withAnimation { env.settings.settings.glow.style = GlowStyle() }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    private func colorBinding(_ binding: Binding<RGBAColor>) -> Binding<Color> {
        Binding(get: { binding.wrappedValue.color }, set: { binding.wrappedValue = RGBAColor($0) })
    }
}

struct LabeledPicker<Option: Hashable & Identifiable>: View {
    var title: String
    @Binding var selection: Option
    var options: [Option]
    var label: (Option) -> String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(options) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

private struct ColorPair: Identifiable {
    var name: String
    var primary: RGBAColor
    var secondary: RGBAColor
    var id: String { name }

    static let all = [
        ColorPair(name: "Sunset", primary: RGBAColor(red: 1, green: 0.42, blue: 0.16), secondary: RGBAColor(red: 1, green: 0.13, blue: 0.45)),
        ColorPair(name: "Ocean", primary: RGBAColor(red: 0.1, green: 0.55, blue: 1), secondary: RGBAColor(red: 0.2, green: 0.95, blue: 0.85)),
        ColorPair(name: "Neon", primary: RGBAColor(red: 0.75, green: 0.2, blue: 1), secondary: RGBAColor(red: 0.2, green: 1, blue: 0.6)),
        ColorPair(name: "Ember", primary: RGBAColor(red: 1, green: 0.7, blue: 0.2), secondary: RGBAColor(red: 0.9, green: 0.15, blue: 0.1)),
        ColorPair(name: "Moonlight", primary: RGBAColor(red: 0.85, green: 0.9, blue: 1), secondary: RGBAColor(red: 0.45, green: 0.55, blue: 0.85)),
    ]
}
