import Foundation
import Logging
import CoreBluetooth

actor DeskController {
    
    // MARK: - Types
    
    enum ControllerError: Error {
        case missingServices
        case missingCharacteristics
        case notConnected
        case invalidPositionValue
        case invalidPositionCommand
    }
    
    private struct Service {
        var id: CBUUID
        var characteristicId: CBUUID
    }
    
    private enum Services {
        static let position = CBUUID(string: "99FA0020-338A-1024-8A49-009C0215F78A")
        static let control = CBUUID(string: "99FA0001-338A-1024-8A49-009C0215F78A")
        static let moveTo = CBUUID(string: "99FA0030-338A-1024-8A49-009C0215F78A")
    }
    
    private enum Characteristic {
        static let position = CBUUID(string: "99FA0021-338A-1024-8A49-009C0215F78A")
        static let command = CBUUID(string: "99FA0002-338A-1024-8A49-009C0215F78A")
        static let moveTo = CBUUID(string: "99FA0031-338A-1024-8A49-009C0215F78A")
    }
    
    private enum Command {
        static var up = Data([0x47, 0x00])
        static var down = Data([0x46, 0x00])
        static var stop = Data([0xff, 0x00])
        static var undefined = Data([0xFE, 0x00])
    }
    
    private struct Connection {
        var peripheralId: UUID
        var positionCharacteristic: CBCharacteristic
        var commandCharacteristic: CBCharacteristic
        var moveToCharacteristic: CBCharacteristic
    }
    
    // MARK: - Public Vars
    
    static let minimumDeskPosition: Double = 62
    static let maximumDeskPosition: Double = 127
    
    // MARK: - Private Vars
    
    private static let retryInterval: TimeAmount = .seconds(5)
    
    private var didStart = false
    private var isPoweredOn = false
    
    private let logger = Logger(label: "com.roebert.IKEADeskControl.DeskController")
    
    private let controller: PeripheralController
    private var peripheral: CBPeripheral?
    private var connection: Connection?
    
    private var isMoving = false
    private var moveTask: Task<Void, Error>?
    
    private var onConnected: ((DeskState) async -> Void)?
    private var onDisconnected: (() async -> Void)?
    private var onDeskState: ((DeskState) async -> Void)?
    
    // MARK: - Lifecycle
    
    init(peripheralId: UUID?) async {
        controller = await PeripheralController(
            serviceId: Services.control,
            peripheralId: peripheralId
        )
        await setupController()
    }
    
    private func setupController() async {
        await controller.onState { [weak self] in
            await self?.onState($0)
        }
        
        await controller.onDiscover { [weak self] in
            await self?.onDiscover($0)
        }
        
        await controller.onDisconnect { [weak self] in
            await self?.onDisconnect()
        }
        
        await controller.onCharacteristicUpdate { [weak self] in
            await self?.onCharacteristicUpdate($0)
        }
    }
    
    func start() {
        guard !didStart else {
            return
        }
        
        didStart = true
        Task {
            await setup()
        }
    }
    
    // MARK: - Events
    
    private func onState(_ state: CBManagerState) async {
        let isPoweredOn = state == .poweredOn
        guard isPoweredOn != self.isPoweredOn else {
            return
        }
        
        self.isPoweredOn = isPoweredOn
        await setup()
    }
    
    private func onDiscover(_ peripheral: CBPeripheral) async {
        guard self.peripheral == nil else {
            return
        }
        
        self.peripheral = peripheral
        await setup()
    }
    
    private func onDisconnect() async {
        guard connection != nil else {
            return
        }
        
        connection = nil
        await onDisconnected?()
        
        try? await Task.sleep(for: Self.retryInterval)
        await setup()
    }
    
    private func onCharacteristicUpdate(_ characteristic: CBCharacteristic) async {
        guard
            characteristic == connection?.positionCharacteristic,
            let deskState = try? deskState
        else {
            return
        }
        
        // Cancel any move task if speed is 0, user probably canceled manually
        if isMoving && deskState.speed == 0 {
            moveTask?.cancel()
            moveTask = nil
            isMoving = false
        }
        
        await onDeskState?(deskState)
    }
    
    // MARK: - Register Events
    
    func onDeskState(_ onDeskState: @escaping (DeskState) async -> Void) {
        self.onDeskState = onDeskState
    }
    
    func onConnected(_ onConnected: @escaping (DeskState) async -> Void) {
        self.onConnected = onConnected
    }
    
    func onDisconnected(_ onDisconnected: @escaping () async -> Void) {
        self.onDisconnected = onDisconnected
    }
    
    // MARK: - Setup
    
    private func setup() async {
        guard didStart && isPoweredOn else {
            return
        }
        
        do {
            if let peripheral = peripheral {
                try await connectAndDiscover(peripheral)
            } else {
                try await controller.findPeripheral()
            }
        } catch {
            logger.error("Failed to connect", metadata: [
                "error": "\(error)"
            ])
            
            try? await Task.sleep(for: Self.retryInterval)
            await setup()
        }
    }
    
    private func discover(_ peripheral: CBPeripheral) async throws -> [CBService] {
        try await controller.discoverServices(nil)
        
        guard let services = peripheral.services, !services.isEmpty else {
            throw ControllerError.missingServices
        }
        
        for service in services {
            try await controller.discoverCharacteristics(nil, for: service)
        }
        
        return services
    }
    
    private func connectAndDiscover(_ peripheral: CBPeripheral) async throws {
        logger.info("Connecting...", metadata: [
            "name": .string(peripheral.name ?? "unknown"),
            "uuid": .string(peripheral.identifier.uuidString)
        ])
        
        try await controller.connect()
        let services = try await discover(peripheral)
        
        guard
            let positionService = services.first(where: { $0.uuid == Services.position }),
            let controlService = services.first(where: { $0.uuid == Services.control }),
            let moveToService = services.first(where: { $0.uuid == Services.moveTo })
        else {
            throw ControllerError.missingServices
        }
        
        guard
            let positionCharacteristic = positionService.characteristics?.first(where: { $0.uuid == Characteristic.position }),
            let commandCharacteristic = controlService.characteristics?.first(where: { $0.uuid == Characteristic.command }),
            let moveToCharacteristic = moveToService.characteristics?.first(where: { $0.uuid == Characteristic.moveTo })
        else {
            throw ControllerError.missingCharacteristics
        }
        
        try await controller.readValue(for: positionCharacteristic)
        try await controller.setNotifyValue(true, for: positionCharacteristic)
        
        let connection = Connection(
            peripheralId: peripheral.identifier,
            positionCharacteristic: positionCharacteristic,
            commandCharacteristic: commandCharacteristic,
            moveToCharacteristic: moveToCharacteristic
        )
        
        let deskState = try deskState(for: connection)
        self.connection = connection
        
        logger.info("Connected!", metadata: [
            "name": .string(peripheral.name ?? "unknown"),
            "uuid": .string(peripheral.identifier.uuidString)
        ])
        
        await onConnected?(deskState)
    }
    
    // MARK: - Desk State
    
    private func deskState(for connection: Connection) throws -> DeskState {
        guard let value = connection.positionCharacteristic.value else {
            throw ControllerError.invalidPositionValue
        }
        
        var reader = DataReader(data: value)
        guard
            let positionInteger: UInt16 = reader.readInteger(),
            let speedInteger: Int16 = reader.readInteger()
        else {
            throw ControllerError.invalidPositionValue
        }
        
        let position = Double(positionInteger) / 100
        return DeskState(
            peripheralId: connection.peripheralId,
            position: Self.minimumDeskPosition + position,
            speed: Double(speedInteger) / 100,
            rawPosition: positionInteger
        )
    }
    
    private var deskState: DeskState {
        get throws {
            guard let connection = connection else {
                throw ControllerError.notConnected
            }
            return try deskState(for: connection)
        }
    }
    
    // MARK: - Move
    
    func move(toPosition position: Double) async throws {
        guard
            let commandCharacteristic = connection?.commandCharacteristic,
            let moveToCharacteristic = connection?.moveToCharacteristic
        else {
            throw ControllerError.notConnected
        }
        
        guard
            position >= Self.minimumDeskPosition,
            position <= Self.maximumDeskPosition
        else {
            throw ControllerError.invalidPositionCommand
        }
        
        // First stop the desk
        try await stop()
        
        let task = Task<Void, Error> {
            try await performMove(
                toPosition: position,
                commandCharacteristic: commandCharacteristic,
                moveToCharacteristic: moveToCharacteristic
            )
        }
        moveTask = task
        try await task.value
    }
    
    private func performMove(
        toPosition position: Double,
        commandCharacteristic: CBCharacteristic,
        moveToCharacteristic: CBCharacteristic
    ) async throws {
        let rawPosition = UInt16(round((position - Self.minimumDeskPosition) * 100))
        
        var moveToPosition = rawPosition.littleEndian
        let moveToCommand = withUnsafeBytes(of: &moveToPosition) {
            Data($0)
        }
        
        var deskState = try self.deskState
        guard deskState.rawPosition != rawPosition else {
            // Nothing to do, desk already at position
            return
        }
        
        // To allow using the move-to characteristic we have to send a undefined command first.
        try await controller.writeValue(Command.undefined, for: commandCharacteristic)
        
        // We cannot directly start moving, the desk needs some time to process for some reason.
        try await Task.sleep(for: .milliseconds(800))
        
        repeat {
            async let sleep: () = Task.sleep(for: .milliseconds(500))
            
            try await controller.writeValue(moveToCommand, for: moveToCharacteristic)
            try await sleep
            
            try Task.checkCancellation()
            isMoving = true
            
            deskState = try self.deskState
        } while deskState.rawPosition != rawPosition
        
        try await controller.writeValue(Command.stop, for: commandCharacteristic)
        try await controller.writeValue(Command.undefined, for: commandCharacteristic)
        
        if !Task.isCancelled {
            moveTask = nil
            isMoving = false
        }
    }
    
    func stop() async throws {
        guard let commandCharacteristic = connection?.commandCharacteristic else {
            throw ControllerError.notConnected
        }
        
        // Cancel and wait for any existing move task
        moveTask?.cancel()
        try? await moveTask?.value
        moveTask = nil
        isMoving = false
        
        // Send stop command
        try await controller.writeValue(Command.stop, for: commandCharacteristic)
    }
}
