import Foundation

// Protocol for cross-platform network connection
public protocol NetworkConnectionProtocol {
    func connect(host: String, port: UInt16)
    func disconnect()
    func cancel()
    func send(data: Data, completion: @escaping (Error?) -> Void)
    func receive(completion: @escaping (Data?, Error?) -> Void)
    var stateUpdateHandler: ((ConnectionState) -> Void)? { get set }
}

public enum ConnectionState {
    case setup
    case waiting(Error)
    case preparing
    case ready
    case failed(Error)
    case cancelled
}