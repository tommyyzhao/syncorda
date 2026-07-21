import Darwin
import Foundation
import SyncordaAtomics

public enum SyncordaControlSocket {
    public static var defaultPath: String { "/tmp/syncorda-\(getuid()).sock" }
}

public enum LocalControlError: LocalizedError {
    case socket(String)
    case invalidPath
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case let .socket(message): return message
        case .invalidPath: return "The local control socket path is too long."
        case .malformedResponse: return "The Syncorda service sent an invalid response."
        }
    }
}

private func unixSocketAddress(_ path: String) throws -> (sockaddr_un, socklen_t) {
    var address = sockaddr_un()
    var length = socklen_t()
    let valid = path.withCString { path in
        syncorda_unix_socket_address(path, &address, &length)
    }
    guard valid != 0 else { throw LocalControlError.invalidPath }
    return (address, length)
}

private func withSockaddr<T>(_ address: inout sockaddr_un, length: socklen_t, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, length) }
    }
}

public final class LocalControlServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ControlRequest) -> ControlResponse

    private let path: String
    private let queue = DispatchQueue(label: "io.github.tommyyzhao.syncorda.control-server")
    private let handler: Handler
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceRead?

    public init(path: String = SyncordaControlSocket.defaultPath, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    deinit { stop() }

    public func start() throws {
        guard fileDescriptor == -1 else { return }
        _ = unlink(path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw LocalControlError.socket("Create local control socket: \(String(cString: strerror(errno)))") }
        do {
            configureNoSigPipe(descriptor)
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw LocalControlError.socket("Configure local control socket: \(String(cString: strerror(errno)))")
            }
            var addressAndLength = try unixSocketAddress(path)
            let bindResult = withSockaddr(&addressAndLength.0, length: addressAndLength.1) { pointer, length in bind(descriptor, pointer, length) }
            guard bindResult == 0 else { throw LocalControlError.socket("Bind local control socket: \(String(cString: strerror(errno)))") }
            guard chmod(path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
                throw LocalControlError.socket("Restrict local control socket: \(String(cString: strerror(errno)))")
            }
            guard listen(descriptor, 16) == 0 else { throw LocalControlError.socket("Listen on local control socket: \(String(cString: strerror(errno)))") }
            fileDescriptor = descriptor
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptConnections() }
            source.setCancelHandler { close(descriptor) }
            self.source = source
            source.resume()
        } catch {
            close(descriptor)
            _ = unlink(path)
            throw error
        }
    }

    public func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
        _ = unlink(path)
    }

    private func acceptConnections() {
        while true {
            let client = accept(fileDescriptor, nil, nil)
            if client < 0 {
                if errno != EWOULDBLOCK && errno != EAGAIN { return }
                return
            }
            let clientFlags = fcntl(client, F_GETFL)
            if clientFlags >= 0 { _ = fcntl(client, F_SETFL, clientFlags & ~O_NONBLOCK) }
            configureNoSigPipe(client)
            DispatchQueue.global(qos: .userInitiated).async { [handler] in
                defer { close(client) }
                let response: ControlResponse
                do {
                    let requestData = try readLine(from: client)
                    let request = try ControlCodec.decode(ControlRequest.self, from: requestData)
                    response = handler(request)
                } catch {
                    response = ControlResponse(ok: false, message: error.localizedDescription)
                }
                if let data = try? ControlCodec.encode(response) { writeAll(data, to: client) }
            }
        }
    }
}

public enum LocalControlClient {
    public static func send(_ request: ControlRequest, path: String = SyncordaControlSocket.defaultPath) throws -> ControlResponse {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw LocalControlError.socket("Create client socket: \(String(cString: strerror(errno)))") }
        defer { close(descriptor) }
        configureNoSigPipe(descriptor)
        var addressAndLength = try unixSocketAddress(path)
        let result = withSockaddr(&addressAndLength.0, length: addressAndLength.1) { pointer, length in connect(descriptor, pointer, length) }
        guard result == 0 else { throw LocalControlError.socket("Connect to Syncorda: \(String(cString: strerror(errno)))") }
        try writeData(ControlCodec.encode(request), to: descriptor)
        return try ControlCodec.decode(ControlResponse.self, from: readLine(from: descriptor))
    }
}

private func readLine(from descriptor: Int32) throws -> Data {
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while result.count < 65_536 {
        let received = buffer.withUnsafeMutableBytes { bytes in recv(descriptor, bytes.baseAddress, bytes.count, 0) }
        guard received > 0 else { throw LocalControlError.socket("Read local control socket: \(String(cString: strerror(errno)))") }
        result.append(buffer, count: received)
        if result.contains(0x0A) { return result }
    }
    throw LocalControlError.socket("Local control message is too large.")
}

private func writeData(_ data: Data, to descriptor: Int32) throws {
    var offset = 0
    while offset < data.count {
        let sent = data.withUnsafeBytes { bytes in
            send(descriptor, bytes.baseAddress?.advanced(by: offset), bytes.count - offset, 0)
        }
        guard sent > 0 else { throw LocalControlError.socket("Write local control socket: \(String(cString: strerror(errno)))") }
        offset += sent
    }
}

private func writeAll(_ data: Data, to descriptor: Int32) {
    _ = try? writeData(data, to: descriptor)
}

private func configureNoSigPipe(_ descriptor: Int32) {
    var enabled: Int32 = 1
    _ = withUnsafePointer(to: &enabled) { pointer in
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, pointer, socklen_t(MemoryLayout<Int32>.size))
    }
}
