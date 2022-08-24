import Foundation
import MQTTNIO
import Logging

actor MQTTController {
    
    // MARK: - Types
    
    enum Command {
        case stop
        case open
        case close
        case moveTo(Double)
    }
    
    private enum Topic: String {
        case connected
        case status
        case command
    }
    
    private struct MQTTDeskState: Codable {
        var position: Double
        var speed: Double
    }
    
    // MARK: - Public Vars
    
    let identifier: String
    let url: URL
    let credentials: MQTTConfiguration.Credentials?
    
    // MARK: - Private Vars
    
    private var onCommand: ((Command) async -> Void)?
    
    private let logger = Logger(label: "com.roebert.IKEADeskControl.MQTTController")
    
    private let client: MQTTClient
    
    private let globalTopicPrefix: String
    private let topicPrefix: String
    
    private var isConnected = false
    private var deskState: DeskState?
    
    private let debouncer = Limiter(policy: .debounce, interval: .milliseconds(200))
    
    // MARK: - Lifecycle
    
    init(
        identifier: String,
        url: URL,
        credentials: MQTTConfiguration.Credentials?
    ) async {
        self.identifier = identifier
        self.url = url
        self.credentials = credentials
        
        globalTopicPrefix = "ikea-desk-control"
        topicPrefix = "\(globalTopicPrefix)/\(identifier)"
        
        client = .init(configuration: .init(
            url: url,
            credentials: credentials
        ))
        
        client.configuration.willMessage = .init(
            topic: topic(.connected),
            payload: "false"
        )
        
        setupClient()
    }
    
    private func setupClient() {
        client.whenConnected { [weak self] _ in
            Task { [self] in
                await self?.onMQTTConnect()
            }
        }
        
        client.whenMessage { [weak self] message in
            Task { [self] in
                await self?.onMessage(message)
            }
        }
    }
    
    func start() {
        client.connect()
    }
    
    deinit {
        Task { [client] in
            try? await client.disconnect(sendWillMessage: true)
        }
    }
    
    // MARK: - Utils
    
    private func globalTopic(_ topic: Topic) -> String {
        return "\(globalTopicPrefix)/\(topic.rawValue)"
    }
    
    private func topic(_ topic: Topic) -> String {
        return "\(topicPrefix)/\(topic.rawValue)"
    }
    
    private var deskStateJSON: String? {
        guard let deskState = deskState else {
            return nil
        }
        
        let mqttDeskState = MQTTDeskState(
            position: deskState.position,
            speed: deskState.speed
        )
        
        guard let data = try? JSONEncoder().encode(mqttDeskState) else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Actions
    
    private func publish() {
        publishConnected()
        publishDeskState()
    }
    
    private func publishConnected() {
        client.publish(isConnected ? "true" : "false", to: topic(.connected))
    }
    
    private func publishDeskState() {
        guard let deskStateJSON = deskStateJSON else {
            return
        }
        
        Task {
            await debouncer.perform {
                try? await self.client.publish(
                    .string(deskStateJSON, contentType: "application/json"),
                    to: self.topic(.status)
                )
            }
        }
    }
    
    // MARK: - Register Events
    
    func onCommand(_ onCommand: @escaping (Command) async -> Void) {
        self.onCommand = onCommand
    }
    
    // MARK: - Events
    
    private func onMQTTConnect() async {
        do {
            let response = try await client.subscribe(to: [
                globalTopic(.command),
                topic(.command)
            ])
            
            for result in response.results {
                guard case .success = result else {
                    Task {
                        try await client.reconnect()
                    }
                    return
                }
            }
            
            publish()
        } catch {
            Task {
                try await client.reconnect()
            }
        }
    }
    
    private func onMessage(_ message: MQTTMessage) async {
        switch message.payload.string?.lowercased() {
        case "stop":
            await onCommand?(.stop)
            
        case "open":
            await onCommand?(.open)
            
        case "close":
            await onCommand?(.close)
            
        case "announce":
            publish()
            
        case .some(let command):
            if let position = Double(command) {
                await onCommand?(.moveTo(position))
            } else {
                logger.warning("Received invalid command: \(command)")
            }
            
        case .none:
            logger.warning("Received empty command")
        }
    }
    
    func deskDidConnect(deskState: DeskState) {
        guard !isConnected else {
            return
        }
        
        isConnected = true
        self.deskState = deskState
        publish()
    }
    
    func deskDidDisconnect() {
        guard isConnected else {
            return
        }
        
        isConnected = false
        publishConnected()
    }
    
    func didReceiveDeskState(_ deskState: DeskState) {
        guard deskState != self.deskState else {
            return
        }
        
        self.deskState = deskState
        publishDeskState()
    }
}
