import SwiftUI

public struct MoneyTextField: View {
    @Binding public var paise: Int64
    public var placeholder: String = "0.00"
    public var alignment: TextAlignment = .trailing
    public var isEditable: Bool = true
    /// Called after a Return/Enter submit (not a plain blur) commits the
    /// typed amount. Voucher-line grids use this to add a new line per the
    /// PRD's "Enter on amount adds a new line" contract (AVL-P0-020).
    public var onCommit: (() -> Void)? = nil
    /// Two-way link to a host-owned focus flag, mirroring
    /// `AccountPicker.isFocusedExternally` — lets a Tally-style Enter
    /// cascade move the caret into this field programmatically.
    public var isFocusedExternally: Binding<Bool>? = nil

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    public init(paise: Binding<Int64>,
                placeholder: String = "0.00",
                alignment: TextAlignment = .trailing,
                isEditable: Bool = true,
                onCommit: (() -> Void)? = nil,
                isFocusedExternally: Binding<Bool>? = nil) {
        self._paise = paise
        self.placeholder = placeholder
        self.alignment = alignment
        self.isEditable = isEditable
        self.onCommit = onCommit
        self.isFocusedExternally = isFocusedExternally
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
                let formatted = format(newValue)
                if !isFocused, text != formatted { text = formatted }
            }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    let focusedText = paise == 0 ? "" : Currency.formatPaise(paise, style: .plain)
                    if text != focusedText { text = focusedText }
                } else {
                    // Commit whatever was typed. Tab/Shift-Tab and clicking
                    // another field both blur without firing onSubmit, so
                    // relying on onSubmit alone silently discarded the last
                    // edit in a voucher-line grid.
                    commitFromText()
                }
                isFocusedExternally?.wrappedValue = focused
            }
            .onChange(of: isFocusedExternally?.wrappedValue) { _, external in
                if external == true { isFocused = true }
            }
            .onSubmit {
                commitFromText()
                onCommit?()
            }
            .frame(height: AppMetrics.fieldHeight)
    }

    private func format(_ value: Int64) -> String {
        value == 0 ? "" : Currency.formatPaise(value, style: .indianGrouping)
    }

    private func commitFromText() {
        if let parsed = Currency.parseRupeeInput(text) {
            let formatted = format(parsed)
            if paise != parsed { paise = parsed }
            if text != formatted { text = formatted }
        } else {
            let formatted = format(paise)
            if text != formatted { text = formatted }
        }
    }
}

extension MoneyTextField {
    public init(label: String, text: Binding<String>, onCommit: (() -> Void)? = nil, isFocusedExternally: Binding<Bool>? = nil) {
        let paiseBinding = Binding<Int64>(
            get: { Currency.parseRupeeInput(text.wrappedValue) ?? 0 },
            set: { newValue in
                if newValue == 0 {
                    if text.wrappedValue != "" { text.wrappedValue = "" }
                } else {
                    let formatted = Currency.formatAmountInput(paise: newValue)
                    if text.wrappedValue != formatted { text.wrappedValue = formatted }
                }
            }
        )
        self.init(paise: paiseBinding, placeholder: label, onCommit: onCommit, isFocusedExternally: isFocusedExternally)
    }
}
