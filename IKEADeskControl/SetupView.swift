import SwiftUI

struct SetupView: View {

    // MARK: - Public Vars

    @ObservedObject var viewModel: SetupViewModel

    // MARK: - View

    var body: some View {
        Form {
            Text("MQTT")
            TextField("URL:", text: $viewModel.mqttURLString)
            TextField("Username:", text: $viewModel.mqttUsername)
            SecureField("Password:", text: $viewModel.mqttPassword)
            TextField("Identifier:", text: $viewModel.mqttIdentifier)
            
            Button("Start") {
                viewModel.start()
            }
        }
        .padding()
        .alert("The entered MQTT url is invalid.", isPresented: $viewModel.isInvalidURLAlertVisible) {
            Button("OK") {
                viewModel.isInvalidURLAlertVisible = false
            }
        }
        .alert("Missing or invalid MQTT identifier ('+' or '*' is not allowed).", isPresented: $viewModel.isInvalidIdentifierAlertVisible) {
            Button("OK") {
                viewModel.isInvalidIdentifierAlertVisible = false
            }
        }
        .frame(minWidth: 300)
        .fixedSize()
    }
}

#if DEBUG
struct SetupView_Previews: PreviewProvider {
    static var previews: some View {
        SetupView(viewModel: .init() { _ in
            
        })
    }
}
#endif
