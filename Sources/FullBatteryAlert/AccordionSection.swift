import SwiftUI

struct AccordionSection<Content: View>: View {
    /// Screenshot-mode global override. When non-nil, ALL AccordionSection
    /// instances render with this open state regardless of @AppStorage.
    nonisolated(unsafe) static var screenshotForceOpen: Bool? {
        get { _screenshotForceOpen }
        set { _screenshotForceOpen = newValue }
    }

    let id: String
    let title: String
    @ViewBuilder var content: () -> Content

    @AppStorage private var isOpen: Bool

    init(id: String, title: String, defaultOpen: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.content = content
        self._isOpen = AppStorage(wrappedValue: defaultOpen, "accordion.\(id).open")
    }

    private var effectiveOpen: Bool {
        AccordionSectionConfig.forceOpen ?? isOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(effectiveOpen ? 90 : 0))
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if effectiveOpen {
                content()
                    .padding(.leading, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// Plain global (read once per render) — avoids actor-isolation friction.
nonisolated(unsafe) private var _screenshotForceOpen: Bool? = nil
enum AccordionSectionConfig {
    nonisolated(unsafe) static var forceOpen: Bool? {
        get { _screenshotForceOpen }
        set { _screenshotForceOpen = newValue }
    }
}
