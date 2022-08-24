import Foundation

actor Limiter {
    
    // MARK: - Types
    
    enum Policy {
        case throttle
        case debounce
    }
    
    // MARK: - Public Vars
    
    let policy: Policy
    let interval: TimeAmount
    
    // MARK: - Private Vars
    
    private var isThrottling = false
    
    private var isDebouncing = false
    private var debounceTask: (@Sendable () async -> Void)?
    
    // MARK: - Lifecycle
    
    init(policy: Policy, interval: TimeAmount) {
        self.policy = policy
        self.interval = interval
    }
    
    // MARK: - Public
    
    func perform(_ task: @escaping @Sendable () async -> Void) async {
        switch policy {
        case .throttle:
            await throttle(task)
            
        case .debounce:
            await debounce(task)
        }
    }
    
    // MARK: - Private
    
    private func throttle(_ task: @escaping @Sendable () async -> Void) async {
        guard !isThrottling else {
            return
        }
        
        isThrottling = true
        defer {
            isThrottling = false
        }
        
        Task {
            await task()
        }
        
        try? await Task.sleep(for: interval)
    }
    
    private func debounce(_ task: @escaping @Sendable () async -> Void) async {
        debounceTask = task
        
        guard !isDebouncing else {
            return
        }
        
        isDebouncing = true
        defer {
            debounceTask = nil
            isDebouncing = false
        }
        
        try? await Task.sleep(for: interval)
        
        if let finalTask = debounceTask {
            Task {
                await finalTask()
            }
        }
    }
}
