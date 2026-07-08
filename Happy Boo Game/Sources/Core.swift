import AppKit
import AVFoundation
import Foundation
import SpriteKit

struct Vec2: Codable {
    var x: CGFloat
    var y: CGFloat

    var point: CGPoint { CGPoint(x: x, y: y) }

    init(_ point: CGPoint = .zero) {
        self.x = point.x
        self.y = point.y
    }
}

struct AudioSettings: Codable {
    var masterDB: Double = 0
    var musicDB: Double = -2
    var sfxDB: Double = 0
}

struct DisplaySettings: Codable {
    var fullscreen: Bool = false
}

struct ControlSettings: Codable {
    var moveLeft: UInt16 = 0
    var moveRight: UInt16 = 2
    var moveUp: UInt16 = 13
    var moveDown: UInt16 = 1
    var throwBomb: UInt16 = 6
    var pause: UInt16 = 53
}

struct Profile: Codable {
    var username: String = ""
    var tutorialCompleted: Bool = false
    var coins: Int = 0
    var ownedSkins: [String] = ["classic"]
    var equippedSkin: String = "classic"
}

struct SettingsPayload: Codable {
    var version: Int = 1
    var audio = AudioSettings()
    var display = DisplaySettings()
    var controls = ControlSettings()
    var profile = Profile()
}

struct RunState: Codable {
    var score: Int
    var gunScore: Int
    var currentHealth: CGFloat
    var maxHealth: CGFloat
    var playerPosition: Vec2
    var elapsedRunTimeSec: TimeInterval
}

struct SavePayload: Codable {
    var version: Int = 1
    var savedAtUnix: TimeInterval
    var runState: RunState
    var settings: SettingsPayload
}

struct SkinDefinition {
    let id: String
    let name: String
    let price: Int
    let basePath: String?
    let previewPath: String
}

enum SkinCatalog {
    static let skins: [SkinDefinition] = [
        SkinDefinition(id: "classic", name: "Classic Boo", price: 0, basePath: nil, previewPath: "characters/happy_boo/square_ref.png"),
        SkinDefinition(id: "berry", name: "Berry Boo", price: 25, basePath: "characters/happy_boo/skins/berry", previewPath: "characters/happy_boo/skins/berry/preview.png"),
        SkinDefinition(id: "mint", name: "Mint Boo", price: 50, basePath: "characters/happy_boo/skins/mint", previewPath: "characters/happy_boo/skins/mint/preview.png"),
        SkinDefinition(id: "gold", name: "Gold Boo", price: 100, basePath: "characters/happy_boo/skins/gold", previewPath: "characters/happy_boo/skins/gold/preview.png"),
        SkinDefinition(id: "sappy", name: "Sappy Boo", price: 150, basePath: "characters/happy_boo/skins/sappy", previewPath: "characters/happy_boo/skins/sappy/preview.png")
    ]

    static func definition(for id: String) -> SkinDefinition {
        skins.first { $0.id == id } ?? skins[0]
    }
}

final class SettingsStore {
    static let shared = SettingsStore()
    var payload = SettingsPayload()

    var profile: Profile { payload.profile }

    private var settingsURL: URL {
        supportDirectory().appendingPathComponent("settings.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? JSONDecoder().decode(SettingsPayload.self, from: data) else {
            save()
            return
        }
        payload = decoded
        if !payload.profile.ownedSkins.contains("classic") {
            payload.profile.ownedSkins.append("classic")
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? FileManager.default.createDirectory(at: supportDirectory(), withIntermediateDirectories: true)
        try? data.write(to: settingsURL)
    }

    func setUsername(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[A-Za-z0-9_]{3,16}$", options: .regularExpression) != nil else { return false }
        payload.profile.username = trimmed
        save()
        return true
    }

    func addCoins(_ amount: Int) {
        payload.profile.coins = max(0, payload.profile.coins + max(0, amount))
        save()
    }

    func buyOrEquipSkin(_ skin: SkinDefinition) -> String {
        if payload.profile.ownedSkins.contains(skin.id) {
            payload.profile.equippedSkin = skin.id
            save()
            return "Skin equipped."
        }
        guard payload.profile.coins >= skin.price else { return "Not enough coins." }
        payload.profile.coins -= skin.price
        payload.profile.ownedSkins.append(skin.id)
        payload.profile.equippedSkin = skin.id
        save()
        return "Skin bought and equipped."
    }

    func markTutorialCompleted(_ completed: Bool = true) {
        payload.profile.tutorialCompleted = completed
        save()
    }

    private func supportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Happy Boo Game", isDirectory: true)
    }
}

final class SaveStore {
    static let shared = SaveStore()
    var pendingRun: RunState?

    private var saveURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Happy Boo Game", isDirectory: true)
            .appendingPathComponent("savegame.json")
    }

    func hasSave() -> Bool {
        FileManager.default.fileExists(atPath: saveURL.path)
    }

    func save(runState: RunState) {
        let payload = SavePayload(savedAtUnix: Date().timeIntervalSince1970, runState: runState, settings: SettingsStore.shared.payload)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: saveURL)
    }

    func load() -> RunState? {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode(SavePayload.self, from: data) else { return nil }
        SettingsStore.shared.payload = decoded.settings
        SettingsStore.shared.save()
        return decoded.runState
    }

    func clearPending() {
        pendingRun = nil
    }
}

enum AssetLoader {
    static func texture(_ path: String) -> SKTexture {
        if let image = image(path) {
            return SKTexture(image: image)
        }
        return SKTexture()
    }

    static func image(_ path: String) -> NSImage? {
        guard let url = resourceURL(path) else { return nil }
        return NSImage(contentsOf: url)
    }

    static func url(_ path: String) -> URL? {
        resourceURL(path)
    }

    private static func resourceURL(_ path: String) -> URL? {
        Bundle.main.url(forResource: "Resources/Assets/\(path)", withExtension: nil)
            ?? Bundle.main.url(forResource: "Assets/\(path)", withExtension: nil)
    }
}

final class AudioManager {
    static let shared = AudioManager()
    private var music: AVAudioPlayer?

    func playMusic() {
        guard music == nil, let url = AssetLoader.url("music/in_game_music.mp3") else { return }
        music = try? AVAudioPlayer(contentsOf: url)
        music?.numberOfLoops = -1
        music?.volume = 0.45
        music?.play()
    }

    func pause(_ paused: Bool) {
        if paused {
            music?.pause()
        } else {
            music?.play()
        }
    }
}

final class SceneRouter {
    static let shared = SceneRouter()
    private weak var view: SKView?

    func configure(view: SKView) {
        self.view = view
    }

    func showUsername() {
        present(UsernameScene(size: view?.bounds.size ?? CGSize(width: 1280, height: 720)))
    }

    func showTitle() {
        present(TitleScene(size: view?.bounds.size ?? CGSize(width: 1280, height: 720)))
    }

    func showGame(online: Bool = false, continuedRun: RunState? = nil) {
        let scene = GameScene(size: view?.bounds.size ?? CGSize(width: 1280, height: 720))
        scene.onlineRun = online
        scene.continuedRun = continuedRun
        present(scene)
    }

    private func present(_ scene: SKScene) {
        scene.scaleMode = .resizeFill
        view?.presentScene(scene, transition: .fade(withDuration: 0.18))
    }
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
        CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }
}

extension CGVector {
    var length: CGFloat { sqrt(dx * dx + dy * dy) }
    var normalized: CGVector {
        let len = max(length, 0.0001)
        return CGVector(dx: dx / len, dy: dy / len)
    }

    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }
}
