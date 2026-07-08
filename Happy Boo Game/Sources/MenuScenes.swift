import AppKit
import SpriteKit

class BaseMenuScene: SKScene {
    let background = SKShapeNode(rectOf: CGSize(width: 4000, height: 4000))

    override func didMove(to view: SKView) {
        background.fillColor = SKColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
        background.strokeColor = .clear
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        background.zPosition = -100
        addChild(background)
    }

    func label(_ text: String, size: CGFloat, y: CGFloat, color: SKColor = .white) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        node.text = text
        node.fontSize = size
        node.fontColor = color
        node.position = CGPoint(x: frame.midX, y: y)
        addChild(node)
        return node
    }

    func button(_ title: String, y: CGFloat, color: SKColor = SKColor(red: 0.23, green: 0.36, blue: 0.72, alpha: 1), action: @escaping () -> Void) -> ButtonNode {
        let node = ButtonNode(title: title, fill: color)
        node.position = CGPoint(x: frame.midX, y: y)
        node.action = action
        addChild(node)
        return node
    }
}

final class UsernameScene: BaseMenuScene {
    private var input = ""
    private var status: SKLabelNode!

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        label("Happy Boo Game", size: 48, y: frame.midY + 130)
        label("Choose a username", size: 22, y: frame.midY + 70)
        status = label("Type 3-16 letters, numbers, or underscores. Press Enter.", size: 18, y: frame.midY - 40, color: .white.withAlphaComponent(0.82))
        updateInput()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            if SettingsStore.shared.setUsername(input) {
                SceneRouter.shared.showTitle()
            } else {
                status.text = "Username must be 3-16 letters, numbers, or underscores."
            }
            return
        }
        if event.keyCode == 51 {
            if !input.isEmpty { input.removeLast() }
            updateInput()
            return
        }
        guard let chars = event.charactersIgnoringModifiers else { return }
        for char in chars where char.isLetter || char.isNumber || char == "_" {
            if input.count < 16 { input.append(char) }
        }
        updateInput()
    }

    private func updateInput() {
        status?.text = input.isEmpty ? "Type 3-16 letters, numbers, or underscores. Press Enter." : "Username: \(input)"
    }
}

final class TitleScene: BaseMenuScene {
    private var overlay = SKShapeNode()
    private var modalNodes: [SKNode] = []
    private var status: SKLabelNode!
    private var coins: SKLabelNode!

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        AudioManager.shared.playMusic()
        buildMain()
    }

    private func buildMain() {
        removeAllChildren()
        addChild(background)
        label("Survivor Prototype", size: 46, y: frame.midY + 210)
        label("Clean arcade HUD + run-based action", size: 18, y: frame.midY + 170, color: .white.withAlphaComponent(0.8))
        coins = label("Coins: \(SettingsStore.shared.profile.coins)", size: 20, y: frame.midY + 130)
        button("New Run", y: frame.midY + 70) {
            SaveStore.shared.clearPending()
            MultiplayerClient.shared.disconnect()
            SceneRouter.shared.showGame()
        }
        button("Continue", y: frame.midY + 15, color: SKColor(red: 0.20, green: 0.50, blue: 0.85, alpha: 1)) {
            if let run = SaveStore.shared.load() {
                MultiplayerClient.shared.disconnect()
                SceneRouter.shared.showGame(continuedRun: run)
            } else {
                self.status.text = "No save found. Start a new run."
            }
        }
        button("Multiplayer", y: frame.midY - 40, color: SKColor(red: 0.20, green: 0.50, blue: 0.85, alpha: 1)) {
            SaveStore.shared.clearPending()
            SceneRouter.shared.showGame(online: true)
        }
        button("Store", y: frame.midY - 95, color: SKColor(red: 0.86, green: 0.64, blue: 0.17, alpha: 1)) { self.showStore() }
        button("Options", y: frame.midY - 150, color: SKColor(red: 0.34, green: 0.48, blue: 0.38, alpha: 1)) { self.showOptions() }
        button("Quit", y: frame.midY - 205, color: SKColor(red: 0.70, green: 0.18, blue: 0.18, alpha: 1)) { NSApp.terminate(nil) }
        status = label(SaveStore.shared.hasSave() ? "" : "No save found. Start a new run.", size: 16, y: frame.midY - 260, color: .white.withAlphaComponent(0.8))
    }

    private func showOverlay(title: String) -> SKShapeNode {
        overlay.removeFromParent()
        modalNodes.forEach { $0.removeFromParent() }
        modalNodes.removeAll()
        overlay = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        overlay.fillColor = .black.withAlphaComponent(0.82)
        overlay.strokeColor = .clear
        overlay.zPosition = 100
        addChild(overlay)
        let panel = SKShapeNode(rectOf: CGSize(width: 720, height: 520), cornerRadius: 10)
        panel.fillColor = SKColor(red: 0.15, green: 0.18, blue: 0.23, alpha: 1)
        panel.strokeColor = .white.withAlphaComponent(0.25)
        panel.position = CGPoint(x: frame.midX, y: frame.midY)
        panel.zPosition = 101
        addChild(panel)
        modalNodes.append(panel)
        let heading = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        heading.text = title
        heading.fontSize = 34
        heading.position = CGPoint(x: frame.midX, y: frame.midY + 215)
        heading.zPosition = 102
        addChild(heading)
        modalNodes.append(heading)
        return panel
    }

    private func showStore() {
        _ = showOverlay(title: "Skin Store")
        let owned = SettingsStore.shared.profile.ownedSkins
        let equipped = SettingsStore.shared.profile.equippedSkin
        let coinLabel = label("Coins: \(SettingsStore.shared.profile.coins)", size: 20, y: frame.midY + 175)
        coinLabel.zPosition = 102
        modalNodes.append(coinLabel)
        var y = frame.midY + 115
        for skin in SkinCatalog.skins {
            let preview = SKSpriteNode(texture: AssetLoader.texture(skin.previewPath))
            preview.size = CGSize(width: 54, height: 54)
            preview.position = CGPoint(x: frame.midX - 245, y: y + 6)
            preview.zPosition = 102
            addChild(preview)
            modalNodes.append(preview)
            let name = label(skin.name, size: 19, y: y)
            name.horizontalAlignmentMode = .left
            name.position.x = frame.midX - 190
            name.zPosition = 102
            modalNodes.append(name)
            let state = equipped == skin.id ? "Equipped" : (owned.contains(skin.id) ? "Equip" : "Buy \(skin.price)")
            let buy = ButtonNode(title: state, size: CGSize(width: 135, height: 38), fill: .darkGray)
            buy.position = CGPoint(x: frame.midX + 240, y: y + 3)
            buy.zPosition = 102
            buy.action = {
                if equipped != skin.id {
                    self.status.text = SettingsStore.shared.buyOrEquipSkin(skin)
                    self.showStore()
                }
            }
            addChild(buy)
            modalNodes.append(buy)
            y -= 70
        }
        let close = ButtonNode(title: "Close", size: CGSize(width: 160, height: 42), fill: .darkGray)
        close.position = CGPoint(x: frame.midX, y: frame.midY - 220)
        close.zPosition = 102
        close.action = { self.buildMain() }
        addChild(close)
        modalNodes.append(close)
    }

    private func showOptions() {
        _ = showOverlay(title: "Options")
        let lines = [
            "Audio: available through macOS system volume in this native build.",
            "Display: resizable macOS window.",
            "Controls: WASD move, pointer aim, Z bomb, Esc pause, Enter chat.",
            "Tutorial can be replayed by resetting progress below."
        ]
        var y = frame.midY + 130
        for line in lines {
            let item = label(line, size: 18, y: y, color: .white.withAlphaComponent(0.86))
            item.zPosition = 102
            modalNodes.append(item)
            y -= 48
        }
        let tutorial = ButtonNode(title: "Replay Tutorial Next Run", size: CGSize(width: 300, height: 42), fill: .darkGray)
        tutorial.position = CGPoint(x: frame.midX, y: frame.midY - 100)
        tutorial.zPosition = 102
        tutorial.action = { SettingsStore.shared.markTutorialCompleted(false) }
        addChild(tutorial)
        modalNodes.append(tutorial)
        let close = ButtonNode(title: "Close", size: CGSize(width: 160, height: 42), fill: .darkGray)
        close.position = CGPoint(x: frame.midX, y: frame.midY - 190)
        close.zPosition = 102
        close.action = { self.buildMain() }
        addChild(close)
        modalNodes.append(close)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, !modalNodes.isEmpty {
            buildMain()
        }
    }
}
