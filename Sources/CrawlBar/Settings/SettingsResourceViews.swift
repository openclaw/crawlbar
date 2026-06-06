import CrawlBarCore
import SwiftUI

struct CrawlBarDatabaseRow: View {
    let database: CrawlDatabaseResource

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: self.iconName)
                .font(.body)
                .foregroundStyle(self.database.isPrimary ? .blue : .secondary)
                .frame(width: 18, height: 22)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(self.database.label)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if self.database.isPrimary {
                        Text("Primary")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(self.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if !self.database.counts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(self.database.counts.prefix(3)) { count in
                            Text("\(count.value) \(count.label.lowercased())")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let bytes = self.database.bytes {
                    Text(CrawlBarFileSizeText.string(fromByteCount: Int64(bytes)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let modifiedAt = self.database.modifiedAt {
                    Text(CrawlBarDateText.relative(modifiedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        let pieces = [
            self.database.role,
            self.database.path,
        ].compactMap { $0?.nilIfBlank }
        return pieces.isEmpty ? self.database.kind.rawValue : pieces.joined(separator: " · ")
    }

    private var iconName: String {
        switch self.database.kind {
        case .sqlite:
            "internaldrive"
        case .cache:
            "externaldrive.connected.to.line.below"
        case .logical:
            "square.stack.3d.up"
        case .remote, .d1, .cloudflareD1:
            "cloud"
        case .sqliteBundle:
            "archivebox"
        }
    }
}

struct CrawlBarConfigOptionField: View {
    let option: CrawlAppManifest.ConfigOption
    @Binding var value: String
    var disabledReason: String?

    var body: some View {
        CrawlBarControlRow(title: self.option.label, caption: self.caption) {
            self.control
        }
        .disabled(self.disabledReason != nil)
    }

    @ViewBuilder
    private var control: some View {
        switch self.option.kind {
        case .secret:
            HStack(spacing: 8) {
                SecureField(self.option.placeholder ?? "Value", text: self.$value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                Button {
                    self.value = ""
                } label: {
                    Image(systemName: "key.slash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear saved secret")
            }
        case .boolean:
            Toggle("", isOn: self.booleanBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        case .choice:
            Picker("Value", selection: self.$value) {
                ForEach(self.choices, id: \.self) { choice in
                    Text(choice).tag(choice)
                }
            }
            .labelsHidden()
            .frame(width: 220)
        case .string:
            TextField(self.option.placeholder ?? "Value", text: self.$value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
        case .number:
            TextField(self.option.placeholder ?? "0", text: self.$value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    private var caption: String? {
        [
            self.disabledReason?.nilIfBlank,
            self.option.help?.nilIfBlank,
            self.metadata,
        ].compactMap { $0 }.joined(separator: "\n").nilIfBlank
    }

    private var metadata: String? {
        [
            self.option.envVar?.nilIfBlank,
            self.option.configKey?.nilIfBlank,
        ].compactMap { $0 }.joined(separator: "   ").nilIfBlank
    }

    private var choices: [String] {
        var resolved = self.option.choices
        if let defaultValue = self.option.defaultValue?.nilIfBlank,
           !resolved.contains(defaultValue)
        {
            resolved.insert(defaultValue, at: 0)
        }
        if let currentValue = self.value.nilIfBlank,
           !resolved.contains(currentValue)
        {
            resolved.insert(currentValue, at: 0)
        }
        return resolved
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: { ["1", "true", "yes", "on"].contains(self.value.lowercased()) },
            set: { self.value = $0 ? "true" : "false" })
    }
}
