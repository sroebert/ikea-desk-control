import Foundation
import Combine

final class SetupViewModel: ObservableObject {
    
    // MARK: - Types
    
    struct StartConfiguration {
        var mqttURL: URL
        var mqttUsername: String?
        var mqttPassword: String?
        var mqttIdentifier: String
    }
    
    // MARK: - Public Vars
    
    @Published var mqttURLString = ""
    @Published var mqttUsername = ""
    @Published var mqttPassword = ""
    @Published var mqttIdentifier = ""
    
    @Published var isInvalidURLAlertVisible = false
    @Published var isInvalidIdentifierAlertVisible = false
    
    // MARK: - Private Vars
    
    private let onStart: (StartConfiguration) -> Void

    // MARK: - Lifecycle
    
    init(onStart: @escaping (StartConfiguration) -> Void) {
        self.onStart = onStart
    }
    
    // MARK: - Actions
    
    func start() {
        guard let url = URL(string: mqttURLString) else {
            isInvalidURLAlertVisible = true
            return
        }
        
        guard !mqttIdentifier.isEmpty &&
                !mqttIdentifier.contains(where: { $0 == "*" }) &&
                !mqttIdentifier.contains(where: { $0 == "+" })
        else {
            isInvalidIdentifierAlertVisible = true
            return
        }
        
        onStart(StartConfiguration(
            mqttURL: url,
            mqttUsername: mqttUsername,
            mqttPassword: mqttPassword,
            mqttIdentifier: mqttIdentifier
        ))
    }
}
