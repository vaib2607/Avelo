import SwiftUI

public struct SearchBar: View {
    @Binding public var text: String
    public var placeholder: String = "Search"
    public var onSubmit: (() -> Void)? = nil
    @State private var draftText: String = ""
    @State private var debounceTask: Task<Void, Never>?

    public init(text: Binding<String>, placeholder: String = "Search", onSubmit: (() -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: AppMetrics.spacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $draftText)
                .textFieldStyle(.plain)
                .font(AppTypography.bodyFont)
                .onSubmit {
                    debounceTask?.cancel()
                    text = draftText
                    onSubmit?()
                }
            if !draftText.isEmpty {
                Button {
                    debounceTask?.cancel()
                    draftText = ""
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, AppMetrics.padding)
        .frame(height: AppMetrics.fieldHeightLarge)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.cornerRadius)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cornerRadius)
                .stroke(AppColors.divider, lineWidth: 0.5)
        )
        .onAppear { draftText = text }
        .onChange(of: text) { _, newValue in
            if newValue != draftText {
                draftText = newValue
            }
        }
        .onChange(of: draftText) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
<<<<<<< HEAD:Avelo/Shared/Components/SearchBar.swift
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
=======
                try? await Task.sleep(nanoseconds: 250_000_000)
>>>>>>> origin/main:Mally/Shared/Components/SearchBar.swift
                guard !Task.isCancelled else { return }
                text = newValue
            }
        }
    }
}
