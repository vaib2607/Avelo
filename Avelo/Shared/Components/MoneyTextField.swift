import SwiftUI

public struct MoneyTextField: View {
    @Binding public var paise: Int64
    public var placeholder: String = "0.00"
    public var alignment: TextAlignment = .trailing
    public var isEditable: Bool = true

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    public init(paise: Binding<Int64>,
                placeholder: String = "0.00",
                alignment: TextAlignment = .trailing,
                isEditable: Bool = true) {
        self._paise = paise
        self.placeholder = placeholder
        self.alignment = alignment
        self.isEditable = isEditable
    }

    public var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .font(AppTypography.monoDigitFont)
            .disabled(!isEditable)
            .focused($isFocused)
            .onAppear { text = format(paise) }
            .onChange(of: paise) { _, newValue in
                if !isFocused { text = format(newValue) }
            }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    text = paise == 0 ? "" : Currency.formatPaise(paise, style: .plain)
                } else {
                    text = format(paise)
                }
            }
            .onSubmit {
                commitFromText()
            }
            .frame(height: AppMetrics.fieldHeight)
    }

    private func format(_ value: Int64) -> String {
        value == 0 ? "" : Currency.formatPaise(value, style: .indianGrouping)
    }

    private func commitFromText() {
        if let parsed = Currency.parseRupeeInput(text) {
            paise = parsed
            text = format(paise)
        } else {
            text = format(paise)
        }
    }
}

extension MoneyTextField {
    public init(label: String, text: Binding<String>) {
        let paiseBinding = Binding<Int64>(
            get: { Currency.parseRupeeInput(text.wrappedValue) ?? 0 },
            set: { newValue in
                if newValue == 0 {
                    text.wrappedValue = ""
                } else {
                    text.wrappedValue = Currency.formatAmountInput(paise: newValue)
                }
            }
        )
        self.init(paise: paiseBinding, placeholder: label)
    }
}
