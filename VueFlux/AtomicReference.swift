import Foundation

/// A value reference that may be updated atomically.
public final class AtomicReference<Value> {
    /// Atomically value getter and setter.
    public var value: Value {
        get { return synchronized { $0 } }
        set { modify { $0 = newValue } }
    }
    
    /// Initialize with a given initial value.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    public convenience init(_ value: Value) {
        self.init(value, usePosixThreadLockForced: false)
    }
    
    /// For testability.
    init(_ value: Value, usePosixThreadLockForced: Bool) {
        _value = value
        
        if #available(*, iOS 10.0, macOS 10.12, tvOS 10.0, watchOS 3.0), !usePosixThreadLockForced {
            lock = OSUnfairLock()
        } else {
            lock = PosixThreadMutex()
        }
    }
    
    private var _value: Value
    private let lock: NSLocking
    
    /// Atomically perform an arbitrary function using the current value.
    ///
    /// - Parameters:
    ///   - function: Arbitrary function with current value.
    ///
    /// - Returns: Result value of action.
    @discardableResult
    public func synchronized<Result>(_ function: (Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try function(_value)
    }
    
    /// Atomically modifies the value.
    ///
    /// - Parameters:
    ///   - function: Arbitrary modification function for current value.
    ///
    /// - Returns: Result value of modification action.
    @discardableResult
    public func modify<Result>(_ function: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try function(&_value)
    }
    
    /// Set the new value and returns old value.
    ///
    /// - Parameters:
    ///   - newValue: A new value.
    ///
    /// - Returns: An old value.
    @discardableResult
    public func swap(_ newValue: Value) -> Value {
        return modify { value in
            let oldValue = value
            value = newValue
            return oldValue
        }
    }
}

private extension AtomicReference {
    @available(iOS 10.0, *)
    @available(macOS 10.12, *)
    @available(tvOS 10.0, *)
    @available(watchOS 3.0, *)
    final class OSUnfairLock: NSLocking {
        private let _lock = os_unfair_lock_t.allocate(capacity: 1)
        
        init() {
            _lock.initialize(to: os_unfair_lock())
        }
        
        deinit {
            _lock.deinitialize()
            _lock.deallocate(capacity: 1)
        }
        
        func lock() {
            os_unfair_lock_lock(_lock)
        }
        
        func unlock() {
            os_unfair_lock_unlock(_lock)
        }
    }
    
    final class PosixThreadMutex: NSLocking {
        private let _lock = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        
        init() {
            _lock.initialize(to: pthread_mutex_t())
            pthread_mutex_init(_lock, nil)
        }
        
        deinit {
            pthread_mutex_destroy(_lock)
            _lock.deinitialize()
            _lock.deallocate(capacity: 1)
        }
        
        func lock() {
            pthread_mutex_lock(_lock)
        }
        
        func unlock() {
            pthread_mutex_unlock(_lock)
        }
    }
}
