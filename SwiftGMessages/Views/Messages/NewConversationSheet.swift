import SwiftUI

struct NewConversationSheet: View {
    @EnvironmentObject private var model: GMAppModel
    @Binding var isPresented: Bool

    @State private var phoneNumber: String = {
        #if DEBUG
        return "4752287656"
        #else
        return ""
        #endif
    }()
    @State private var initialMessage: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("Phone number", text: $phoneNumber)
                    Text("Tip: You can enter a 10-digit US number or a +E.164 number.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Message (Optional)") {
                    TextField("Message", text: $initialMessage, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("New Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let number = phoneNumber
                        let msg = initialMessage
                        isPresented = false
                        Task { await model.createConversation(phoneNumberRaw: number, initialMessage: msg) }
                    }
                    .disabled(phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 280)
    }
}
