import SwiftUI

/// 阅读设置面板：字号、行距、字体、主题、翻页方式、亮度与常亮。
struct ReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: ReadingSettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section("排版") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("字号", systemImage: "textformat.size")
                            Spacer(minLength: 8)
                            Text("\(Int(settings.fontSize)) pt")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.fontSize, in: 14...30, step: 1)
                            .accessibilityLabel("正文字号")
                            .accessibilityValue("\(Int(settings.fontSize)) 磅")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("行距", systemImage: "arrow.up.and.down.text.below")
                            Spacer(minLength: 8)
                            Text("\(Int(settings.lineSpacing)) pt")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.lineSpacing, in: 2...16, step: 1)
                            .accessibilityLabel("行距")
                            .accessibilityValue("\(Int(settings.lineSpacing)) 磅")
                    }

                    Picker("字体", selection: $settings.fontOption) {
                        ForEach(ReaderFontOption.available) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("正文字体")
                }

                Section("外观") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(ReaderTheme.allCases) { theme in
                            ThemeChip(theme: theme, isSelected: settings.theme == theme) {
                                settings.theme = theme
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    Picker("翻页方式", selection: $settings.pageTurnMode) {
                        ForEach(PageTurnMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("翻页方式")

                    Toggle(isOn: $settings.showPageFooter) {
                        Label("显示页码", systemImage: "number")
                    }
                }

                Section("听书") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("语速", systemImage: "waveform")
                            Spacer(minLength: 8)
                            Text(SpeechPreset.speedName(settings.speechRate))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.speechRate, in: 0.1...1.0, step: 0.05)
                            .accessibilityLabel("听书语速")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("语调", systemImage: "music.note")
                            Spacer(minLength: 8)
                            Text(SpeechPreset.pitchName(settings.speechPitch))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.speechPitch, in: 0.5...2.0, step: 0.05)
                            .accessibilityLabel("听书语调")
                    }
                }

                Section("屏幕") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("亮度", systemImage: "sun.max")
                            Spacer(minLength: 8)
                            Text("\(Int(settings.brightness * 100))%")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.brightness, in: 0.4...1.0, step: 0.05)
                            .accessibilityLabel("阅读亮度")
                            .accessibilityValue("\(Int(settings.brightness * 100))%")
                            .onChange(of: settings.brightness) { _, value in
                                UIScreen.main.brightness = value
                            }
                    }

                    Toggle(isOn: $settings.keepScreenAwake) {
                        Label("阅读时保持屏幕常亮", systemImage: "lock.display")
                    }
                    .onChange(of: settings.keepScreenAwake) { _, value in
                        UIApplication.shared.isIdleTimerDisabled = value
                    }
                }

                Section {
                    Button("恢复默认") {
                        settings.fontSize = 18
                        settings.lineSpacing = 6
                        settings.paragraphSpacing = 10
                        settings.theme = .paper
                        settings.pageTurnMode = .curl
                        settings.brightness = 1.0
                    }
                    .accessibilityLabel("恢复默认阅读设置")
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityLabel("关闭阅读设置")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ThemeChip: View {
    let theme: ReaderTheme
    let isSelected: Bool
    let action: () -> Void

    private var background: Color {
        Color(uiColor: UIColor(named: theme.backgroundAsset) ?? .secondarySystemBackground)
    }

    private var foreground: Color {
        Color(uiColor: UIColor(named: theme.textAsset) ?? .label)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(background)
                        .frame(height: 44)
                    Text("Aa")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(foreground)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
