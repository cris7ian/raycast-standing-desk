import SwiftUI

struct SafetyAcknowledgementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Before Movement") {
                    checklist("Watch the desk during the complete movement.")
                    checklist("Clear people, chairs, drawers, shelves, and loose objects.")
                    checklist("Check power and data cable slack.")
                    checklist("Keep the physical controller within reach.")
                }

                Section {
                    Toggle("I completed the safety checks", isOn: $confirmed)
                } footer: {
                    Text("The app stores this acknowledgement and does not ask again unless its data is removed.")
                }
            }
            .navigationTitle("Safety Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { onAccept() }
                        .disabled(!confirmed)
                }
            }
        }
    }

    private func checklist(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "checkmark.circle")
    }
}
