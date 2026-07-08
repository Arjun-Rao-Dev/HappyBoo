import Foundation

enum MultiplayerStatus: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case online = "Online"
    case roomFull = "Room Full"
}

protocol MultiplayerClientDelegate: AnyObject {
    func multiplayerStatusChanged(_ status: MultiplayerStatus, detail: String)
    func multiplayerHostChanged(isHost: Bool)
    func multiplayerReceived(_ message: [String: Any])
}

final class MultiplayerClient {
    static let shared = MultiplayerClient()

    static let defaultURL = URL(string: "wss://sixtyfold-unhappily-brilliant.ngrok-free.dev")!
    static let defaultRoom = "lobby"

    weak var delegate: MultiplayerClientDelegate?
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private(set) var localPlayerID = ""
    private(set) var isHost = false
    private(set) var status: MultiplayerStatus = .disconnected
    private var roomID = MultiplayerClient.defaultRoom
    private var hasJoined = false

    func connect(url: URL = MultiplayerClient.defaultURL, room: String = MultiplayerClient.defaultRoom) {
        disconnect()
        roomID = room
        hasJoined = false
        localPlayerID = ""
        isHost = false
        status = .connecting
        delegate?.multiplayerStatusChanged(.connecting, detail: "Connecting")
        task = session.webSocketTask(with: url)
        task?.resume()
        send(["type": "join", "room_id": roomID])
        hasJoined = true
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        localPlayerID = ""
        isHost = false
        status = .disconnected
        delegate?.multiplayerHostChanged(isHost: false)
        delegate?.multiplayerStatusChanged(.disconnected, detail: "Disconnected")
    }

    func sendPlayerState(_ state: [String: Any]) {
        var payload = state
        payload["type"] = "player_state"
        send(payload)
    }

    func sendWorldMessage(_ type: String, _ payload: [String: Any] = [:]) {
        var message = payload
        message["type"] = type
        send(message)
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handle(text)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure:
                DispatchQueue.main.async {
                    self.status = .disconnected
                    self.delegate?.multiplayerStatusChanged(.disconnected, detail: "Disconnected")
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any] else { return }
        DispatchQueue.main.async {
            let type = message["type"] as? String ?? ""
            switch type {
            case "welcome":
                self.localPlayerID = message["player_id"] as? String ?? ""
            case "host_assigned":
                self.isHost = (message["is_host"] as? Bool) ?? false
                self.delegate?.multiplayerHostChanged(isHost: self.isHost)
            case "joined":
                self.status = .online
                self.delegate?.multiplayerStatusChanged(.online, detail: "Online")
            case "room_full":
                let maxPlayers = Int(message["max_players"] as? Double ?? 4)
                self.status = .roomFull
                self.delegate?.multiplayerStatusChanged(.roomFull, detail: "Room Full (\(maxPlayers) max)")
            default:
                self.delegate?.multiplayerReceived(message)
            }
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let task,
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }
}
