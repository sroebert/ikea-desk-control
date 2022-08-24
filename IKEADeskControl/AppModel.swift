import Foundation
import SwiftUI
import Logging
import MQTTNIO

final class AppModel: ObservableObject {
    
    // MARK: - Types
    
    private struct Configuration: Codable {
        var peripheralId: UUID?
        var mqttURL: URL
        var mqttUsername: String?
        var mqttPassword: String?
        var mqttIdentifier: String
    }
    
    // MARK: - Public Vars
    
    static let shared: AppModel = AppModel()
    
    var isActive: Bool {
        return activeTask != nil
    }
    
    // MARK: - Private Vars
    
    @KeychainItem("configuration")
    private var configuration: Configuration?
    
    private typealias ActiveTaskData = (DeskController, MQTTController)
    private var activeTask: Task<ActiveTaskData, Never>?
    
    // MARK: - Lifecycle
    
    private init() {
        Self.loggingBootstrap()
        
        if let configuration = configuration {
            activeTask = Task {
                await setup(
                    peripheralId: configuration.peripheralId,
                    mqttURL: configuration.mqttURL,
                    mqttUsername: configuration.mqttUsername,
                    mqttPassword: configuration.mqttPassword,
                    mqttIdentifier: configuration.mqttIdentifier
                )
            }
        }
    }
    
    private static func loggingBootstrap() {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            
            #if DEBUG
            handler.logLevel = .debug
            #else
            handler.logLevel = .info
            #endif
            
            return handler
        }
    }
    
    // MARK: - Start
    
    func start(
        mqttURL: URL,
        mqttUsername: String? = nil,
        mqttPassword: String? = nil,
        mqttIdentifier: String
    ) {
        stop()
        
        configuration = .init(
            mqttURL: mqttURL,
            mqttUsername: mqttUsername,
            mqttPassword: mqttPassword,
            mqttIdentifier: mqttIdentifier
        )
        
        activeTask = Task {
            await setup(
                peripheralId: nil,
                mqttURL: mqttURL,
                mqttUsername: mqttUsername,
                mqttPassword: mqttPassword,
                mqttIdentifier: mqttIdentifier
            )
        }
    }
    
    func stop() {
        activeTask?.cancel()
        activeTask = nil
        configuration = nil
    }
    
    private func setup(
        peripheralId: UUID? = nil,
        mqttURL: URL,
        mqttUsername: String? = nil,
        mqttPassword: String? = nil,
        mqttIdentifier: String
    ) async -> ActiveTaskData {
        let deskController = await DeskController(
            peripheralId: peripheralId
        )
        
        let credentials: MQTTConfiguration.Credentials?
        if let username = mqttUsername, let password = mqttPassword {
            credentials = .init(username: username, password: password)
        } else {
            credentials = nil
        }

        let mqttController = await MQTTController(
            identifier: mqttIdentifier,
            url: mqttURL,
            credentials: credentials
        )

        await deskController.onConnected { [weak self, weak mqttController] deskState in
            self?.configuration?.peripheralId = deskState.peripheralId

            await mqttController?.deskDidConnect(deskState: deskState)
        }

        await deskController.onDisconnected { [weak mqttController] in
            await mqttController?.deskDidDisconnect()
        }

        await deskController.onDeskState { [weak mqttController] in
            await mqttController?.didReceiveDeskState($0)
        }

        await mqttController.onCommand { [weak deskController] command in
            guard let deskController = deskController else {
                return
            }
            
            switch command {
            case .stop:
                try? await deskController.stop()

            case .moveTo(let position):
                try? await deskController.move(toPosition: position)

            case .open:
                try? await deskController.move(toPosition: DeskController.maximumDeskPosition)

            case .close:
                try? await deskController.move(toPosition: DeskController.minimumDeskPosition)
            }
        }

        await mqttController.start()
        await deskController.start()
        
        return (deskController, mqttController)
    }
}
