import Foundation
@preconcurrency import CoreBluetooth

actor PeripheralController {
    
    // MARK: - Types
    
    enum ControllerError: Error {
        case bluetoothNotPoweredOn
        case cancelled
        case failedToConnect
        case disconnected
        case notConnectedToPeripheral
    }
    
    // MARK: - Public Vars
    
    let serviceId: CBUUID
    var peripheralId: UUID?
    
    // MARK: - Private Vars
    
    private var peripheral: CBPeripheral?
    
    private var onState: (@Sendable (CBManagerState) async -> Void)?
    private var onDiscover: (@Sendable (CBPeripheral) async -> Void)?
    private var onDisconnect: (@Sendable () async -> Void)?
    private var onCharacteristicUpdate: (@Sendable (CBCharacteristic) async -> Void)?
    
    private let manager: CBCentralManager
    private let delegate: Delegate
    
    private var isConnected = false
    
    private var activeTask: Task<Void, Error>?
    private var activeContinuation: CheckedContinuation<Void, Error>?
    
    private var readTask: Task<Void, Error>?
    private var readContinuation: CheckedContinuation<Void, Error>?
    private var readCharacteristic: CBCharacteristic?
    
    // MARK: - Lifecycle
    
    init(serviceId: CBUUID, peripheralId: UUID?) async {
        self.serviceId = serviceId
        self.peripheralId = peripheralId
        
        delegate = Delegate()
        manager = CBCentralManager(
            delegate: delegate,
            queue: nil
        )
        
        delegate.controller = self
    }
    
    deinit {
        Task {
            if manager.isScanning {
                manager.stopScan()
            }
            
            if await isConnected, let peripheral = await peripheral {
                manager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    // MARK: - Actions
    
    func findPeripheral() async throws {
        guard manager.state == .poweredOn, !manager.isScanning else {
            throw ControllerError.bluetoothNotPoweredOn
        }
        
        if let peripheralId = peripheralId, let peripheral = manager.retrievePeripherals(withIdentifiers: [peripheralId]).first {
            await onDiscover(peripheral)
            return
        }
        
        manager.scanForPeripherals(withServices: [serviceId], options: nil)
    }
    
    func connect() async throws {
        guard !isConnected, let peripheral = peripheral else {
            return
        }
        
        guard manager.state == .poweredOn else {
            throw ControllerError.bluetoothNotPoweredOn
        }
        
        try await performTask {
            Task {
                await MainActor.run {
                    self.manager.connect(peripheral, options: [
                        CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
                    ])
                }
            }
        }
        
        isConnected = true
    }
    
    func discoverServices(_ services: [CBUUID]?) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.discoverServices(services)
        }
    }
    
    func discoverCharacteristics(_ characteristics: [CBUUID]?, for service: CBService) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.discoverCharacteristics(characteristics, for: service)
        }
    }
    
    func discoverDescriptors(for characteristic: CBCharacteristic) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.discoverDescriptors(for: characteristic)
        }
    }
    
    func readValue(for characteristic: CBCharacteristic) async throws {
        readContinuation?.resume(throwing: ControllerError.cancelled)
        readContinuation = nil
        readCharacteristic = nil
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        if let task = readTask {
            return try await task.value
        }
        
        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                readContinuation = continuation
                peripheral.readValue(for: characteristic)
            }
        }
        
        readTask = task
        readCharacteristic = characteristic
        defer {
            readTask = nil
            readCharacteristic = nil
        }
        
        try await task.value
    }
    
    func writeValue(_ data: Data, for characteristic: CBCharacteristic) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
    
    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.setNotifyValue(enabled, for: characteristic)
        }
    }
    
    // MARK: - Register Events
    
    func onState(_ onState: @escaping @Sendable (CBManagerState) async -> Void) {
        self.onState = onState
    }
    
    func onDiscover(_ onDiscover: @escaping @Sendable (CBPeripheral) async -> Void) {
        self.onDiscover = onDiscover
    }
    
    func onDisconnect(_ onDisconnect: @escaping @Sendable () async -> Void) {
        self.onDisconnect = onDisconnect
    }
    
    func onCharacteristicUpdate(_ onCharacteristicUpdate: @escaping @Sendable (CBCharacteristic) async -> Void) {
        self.onCharacteristicUpdate = onCharacteristicUpdate
    }
    
    // MARK: - Events
    
    private func onStateUpdate(_ state: CBManagerState) async {
        await onState?(state)
    }
    
    private func onDiscover(_ peripheral: CBPeripheral) async {
        guard self.peripheral == nil else {
            return
        }
        
        self.peripheral = peripheral
        peripheral.delegate = delegate
        
        manager.stopScan()
        
        await onDiscover?(peripheral)
    }
    
    private func onConnect() {
        completeTask()
    }
    
    private func onDisconnect(with error: Error?) async {
        failTask(with: error ?? ControllerError.disconnected)
        
        guard isConnected else {
            return
        }
        
        isConnected = false
        await onDisconnect?()
    }
    
    private func onFailedToConnect(with error: Error?) async {
        failTask(with: error ?? ControllerError.failedToConnect)
    }
    
    private func onTaskResult(error: Error?) {
        if let error {
            failTask(with: error)
        } else {
            completeTask()
        }
    }
    
    private func onCharacteristicUpdate(_ characteristic: CBCharacteristic, error: Error?) async {
        if let error {
            failTask(with: error)
        } else {
            if readCharacteristic == characteristic {
                readContinuation?.resume()
                readContinuation = nil
            }
            
            await onCharacteristicUpdate?(characteristic)
        }
    }
    
    // MARK: - Utils
    
    private func performTask(_ action: @escaping () -> Void) async throws {
        if let task = activeTask {
            return try await task.value
        }
        
        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                activeContinuation = continuation
                action()
            }
        }
        
        activeTask = task
        defer {
            activeTask = nil
        }
        
        try await task.value
    }
    
    private func completeTask() {
        activeContinuation?.resume()
        activeContinuation = nil
    }
    
    private func failTask(with error: Error) {
        activeContinuation?.resume(throwing: error)
        activeContinuation = nil
    }
    
    // MARK: - Delegate
    
    private final class Delegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        // MARK: - Public Vars
        
        weak var controller: PeripheralController?
        
        // MARK: - Utils
        
        private func handleTaskResult(error: Error?) {
            Task { [controller] in
                await controller?.onTaskResult(error: error)
            }
        }
        
        // MARK: - CBCentralManagerDelegate
        
        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            let state = central.state
            Task { [controller] in
                await controller?.onStateUpdate(state)
            }
        }
        
        func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
            Task { [controller] in
                await controller?.onDiscover(peripheral)
            }
        }
        
        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            Task { [controller] in
                await controller?.onConnect()
            }
        }
        
        func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            Task { [controller] in
                await controller?.onFailedToConnect(with: error)
            }
        }
        
        func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            Task { [controller] in
                await controller?.onDisconnect(with: error)
            }
        }
        
        // MARK: - CBPeripheralDelegate
        
        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            handleTaskResult(error: error)
        }
        
        func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            handleTaskResult(error: error)
        }
        
        func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
            handleTaskResult(error: error)
        }
        
        func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            Task { [controller] in
                await controller?.onCharacteristicUpdate(characteristic, error: error)
            }
        }
        
        func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
            handleTaskResult(error: error)
        }
        
        func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
            handleTaskResult(error: error)
        }
    }
}
