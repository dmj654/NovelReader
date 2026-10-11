import SwiftUI

/// 阅读设置面板：字号、行距、段距、页边距、字体、段首缩进、主题、翻页方式、亮度与常亮。
struct ReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: ReadingSettingsStore

    var body: some View {
        NavigationStack {
            Form {
                typographySection
                appearanceSection
                speechSection
                screenSection
                resetSection
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

    // MARK: - 排版

    private var typographySection: some View {
        Section("排版") {
            sliderRow(
                title: "字号",
                systemImage: "textformat.size",
                value: $settings.fontSize,
                range: 14...32,
                step: 1,
                display: "\(Int(settings.fontSize)) pt",
                accessibilityValue: "\(Int(settings.fontSize)) 磅"
            )

            sliderRow(
                title: "行距",
                systemImage: "arrow.up.and.down.text.below",
                value: $settings.lineSpacing,
                range: 0...24,
                step: 1,
                display: "\(Int(settings.lineSpacing)) pt",
                accessibilityValue: "\(Int(settings.lineSpacing)) 磅"
            )

            sliderRow(
                title: "段间距",
                systemImage: "paragraphsign",
                value: $settings.paragraphSpacing,
                range: 0...28,
                step: 1,
                display: "\(Int(settings.paragraphSpacing)) pt",
                accessibilityValue: "\(Int(settings.paragraphSpacing)) 磅"
            )

            sliderRow(
                title: "页边距",
                systemImage: "rectangle.inset.filled",
                value: $settings.horizontalPadding,
                range: 12...40,
                step: 2,
                display: "\(Int(settings.horizontalPadding)) pt",
                accessibilityValue: "\(Int(settings.horizontalPadding)) 磅"
            )

            fontPicker

            Toggle(isOn: $settings.paragraphIndent) {
                Label("段首缩进两字符", systemImage: "increase.indent")
            }
            .accessibilityLabel("段首缩进两字符")
        }
    }

    private var fontPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("字体", systemImage: "character")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReaderFontOption.available) { option in
                        Button {
                            settings.fontOption = option
                        } label: {
                            Text(option.displayName)
                                .font(Font.custom(option.font(ofSize: 16).fontName, size: 16))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    settings.fontOption.id == option.id
                                        ? Color.accentColor.opacity(0.16)
                                        : Color(uiColor: .tertiarySystemFill),
                                    in: Capsule()
                                )
                                .foregroundStyle(settings.fontOption.id == option.id ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.displayName)
                        .accessibilityAddTraits(settings.fontOption.id == option.id ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        Section("外观") {
            themeGrid

            Picker("翻页方式", selection: $settings.pageTurnMode) {
                ForEach(PageTurnMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("翻页方式")

            Toggle(isOn: $settings.showPageFooter) {
                Label("页脚显示页码与时间", systemImage: "number")
            }
            .accessibilityLabel("页脚显示页码与时间")
        }
    }

    private var themeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            ForEach(ReaderTheme.allCases) { theme in
                ThemeChip(theme: theme, isSelected: settings.theme == theme) {
                    settings.theme = theme
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 听书

    private var speechSection: some View {
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
    }

    // MARK: - 屏幕

    private var screenSection: some View {
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
    }

    // MARK: - 恢复默认

    private var resetSection: some View {
        Section {
            Button("恢复默认排版") {
                settings.resetToDefaults()
            }
            .accessibilityLabel("恢复默认阅读设置")
        } footer: {
            Text("书籍、进度与书源不受影响。")
        }
    }

    // MARK: - 通用行

    private func sliderRow(
        title: String,
        systemImage: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        display: String,
        accessibilityValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                Text(display)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
        }
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
