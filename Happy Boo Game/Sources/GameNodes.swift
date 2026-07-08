import Foundation
import SpriteKit

final class ButtonNode: SKShapeNode {
    let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    var action: (() -> Void)?

    init(title: String, size: CGSize = CGSize(width: 280, height: 46), fill: SKColor = SKColor(red: 0.23, green: 0.36, blue: 0.72, alpha: 1)) {
        super.init()
        path = CGPath(roundedRect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), cornerWidth: 8, cornerHeight: 8, transform: nil)
        fillColor = fill
        strokeColor = .white.withAlphaComponent(0.2)
        lineWidth = 2
        isUserInteractionEnabled = true
        label.text = title
        label.fontSize = 20
        label.verticalAlignmentMode = .center
        label.fontColor = .white
        addChild(label)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        setScale(0.98)
    }

    override func mouseUp(with event: NSEvent) {
        setScale(1)
        action?()
    }

    func setTitle(_ title: String) {
        label.text = title
    }
}

final class HappyBooNode: SKNode {
    private let body = SKSpriteNode()
    private let face = SKSpriteNode()
    private let upperLeft = SKSpriteNode()
    private let lowerLeft = SKSpriteNode()
    private let footLeft = SKSpriteNode()
    private let upperRight = SKSpriteNode()
    private let lowerRight = SKSpriteNode()
    private let footRight = SKSpriteNode()
    private var walkTime: TimeInterval = 0

    override init() {
        super.init()
        [upperLeft, lowerLeft, footLeft, upperRight, lowerRight, footRight, body, face].forEach(addChild)
        applySkin(SettingsStore.shared.profile.equippedSkin)
        zPosition = 20
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applySkin(_ skinID: String) {
        let skin = SkinCatalog.definition(for: skinID)
        let base = skin.basePath ?? "characters/happy_boo"
        body.texture = AssetLoader.texture("\(base)/square_body.png")
        face.texture = AssetLoader.texture("\(base)/square_face.png")
        upperLeft.texture = AssetLoader.texture("\(base)/square_upper_leg.png")
        lowerLeft.texture = AssetLoader.texture("\(base)/square_lower_leg.png")
        footLeft.texture = AssetLoader.texture("\(base)/square_foot.png")
        upperRight.texture = upperLeft.texture
        lowerRight.texture = lowerLeft.texture
        footRight.texture = footLeft.texture

        body.setScale(1.7)
        face.setScale(1.7)
        [upperLeft, lowerLeft, footLeft, upperRight, lowerRight, footRight].forEach { $0.setScale(1.45) }
        body.position = CGPoint(x: 0, y: 16)
        face.position = CGPoint(x: 0, y: 28)
        upperLeft.position = CGPoint(x: -18, y: -16)
        lowerLeft.position = CGPoint(x: -18, y: -34)
        footLeft.position = CGPoint(x: -18, y: -48)
        upperRight.position = CGPoint(x: 18, y: -16)
        lowerRight.position = CGPoint(x: 18, y: -34)
        footRight.position = CGPoint(x: 18, y: -48)
    }

    func updateAnimation(delta: TimeInterval, moving: Bool) {
        guard moving else {
            [upperLeft, lowerLeft, footLeft, upperRight, lowerRight, footRight].forEach { $0.zRotation = 0 }
            return
        }
        walkTime += delta * 12
        let swing = sin(walkTime) * 0.22
        upperLeft.zRotation = swing
        lowerLeft.zRotation = -swing * 0.6
        footLeft.zRotation = swing * 0.5
        upperRight.zRotation = -swing
        lowerRight.zRotation = swing * 0.6
        footRight.zRotation = -swing * 0.5
    }
}

final class PlayerNode: SKNode {
    let boo = HappyBooNode()
    let gun = SKSpriteNode(texture: AssetLoader.texture("pistol/pistol.png"))
    let nameLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    var velocity = CGVector.zero
    var currentHealth: CGFloat = 100
    var maxHealth: CGFloat = 100
    var gunActive = false
    var controlsLocked = false
    var spawnTime: TimeInterval = 0
    var lastFireTime: TimeInterval = 0
    var lastBombTime: TimeInterval = -999

    override init() {
        super.init()
        addChild(boo)
        gun.setScale(1.2)
        gun.position = CGPoint(x: 36, y: 6)
        gun.zPosition = 30
        gun.isHidden = true
        addChild(gun)
        nameLabel.fontSize = 15
        nameLabel.fontColor = .white
        nameLabel.position = CGPoint(x: 0, y: 70)
        nameLabel.text = SettingsStore.shared.profile.username.isEmpty ? "Player" : SettingsStore.shared.profile.username
        addChild(nameLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func aim(at point: CGPoint) {
        let vector = point - position
        gun.zRotation = atan2(vector.dy, vector.dx)
    }

    func update(delta: TimeInterval, time: TimeInterval) {
        if time - spawnTime >= 5 {
            gunActive = !controlsLocked
            gun.isHidden = !gunActive
        }
        boo.updateAnimation(delta: delta, moving: velocity.length > 1)
    }

    func canBomb(time: TimeInterval) -> Bool {
        currentHealth >= maxHealth && time - lastBombTime >= 30
    }
}

final class MobNode: SKSpriteNode {
    enum Kind: String {
        case slime
        case medium
        case heavy
    }

    let kind: Kind
    var health: CGFloat
    var moveSpeed: CGFloat
    var contactDamage: CGFloat
    var networkID: String?
    var spawnTime: TimeInterval = 0

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .slime:
            health = 1
            moveSpeed = 300
            contactDamage = 12
            super.init(texture: AssetLoader.texture("characters/slime/slime_body.png"), color: .clear, size: CGSize(width: 54, height: 44))
        case .medium:
            health = 2
            moveSpeed = 360
            contactDamage = 18
            super.init(texture: AssetLoader.texture("monsters/assets/bee_rest.png"), color: .clear, size: CGSize(width: 70, height: 56))
        case .heavy:
            health = 4
            moveSpeed = 230
            contactDamage = 28
            super.init(texture: AssetLoader.texture("monsters/assets/slime_spike_rest.png"), color: .clear, size: CGSize(width: 82, height: 70))
        }
        zPosition = 12
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FoodNode: SKSpriteNode {
    var networkID: String?
    var textureIndex = 0
    static let texturePaths = stride(from: 0, through: 55, by: 5).map { String(format: "food/tile_%04d.png", $0) }

    init(textureIndex: Int) {
        self.textureIndex = max(0, min(textureIndex, FoodNode.texturePaths.count - 1))
        super.init(texture: AssetLoader.texture(FoodNode.texturePaths[self.textureIndex]), color: .clear, size: CGSize(width: 42, height: 42))
        zPosition = 10
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ProjectileNode: SKSpriteNode {
    var direction = CGVector(dx: 1, dy: 0)
    var shooterLocal = true
    var bornTime: TimeInterval = 0

    init() {
        super.init(texture: AssetLoader.texture("pistol/projectile.png"), color: .clear, size: CGSize(width: 22, height: 9))
        zPosition = 25
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class BombNode: SKSpriteNode {
    var velocity = CGVector.zero
    var bornTime: TimeInterval = 0

    init() {
        super.init(texture: AssetLoader.texture("bombs/tanks_mineOn.png"), color: .clear, size: CGSize(width: 34, height: 34))
        zPosition = 24
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class RemotePlayerNode: SKNode {
    let boo = HappyBooNode()
    let gun = SKSpriteNode(texture: AssetLoader.texture("pistol/pistol.png"))
    let nameLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    var targetPosition = CGPoint.zero
    var targetVelocity = CGVector.zero
    var lastStateTime: TimeInterval = 0

    override init() {
        super.init()
        addChild(boo)
        gun.setScale(1.2)
        gun.position = CGPoint(x: 36, y: 6)
        gun.zPosition = 30
        addChild(gun)
        nameLabel.fontSize = 15
        nameLabel.fontColor = .white
        nameLabel.position = CGPoint(x: 0, y: 70)
        addChild(nameLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ state: [String: Any], now: TimeInterval) {
        if let position = state["position"] as? [String: Any] {
            targetPosition = CGPoint(x: CGFloat(position["x"] as? Double ?? Double(targetPosition.x)), y: CGFloat(position["y"] as? Double ?? Double(targetPosition.y)))
            if self.position == .zero { self.position = targetPosition }
        }
        if let velocity = state["velocity"] as? [String: Any] {
            targetVelocity = CGVector(dx: CGFloat(velocity["x"] as? Double ?? 0), dy: CGFloat(velocity["y"] as? Double ?? 0))
        }
        nameLabel.text = state["username"] as? String ?? "Player"
        boo.applySkin(state["skin_id"] as? String ?? "classic")
        gun.isHidden = !((state["gun_active"] as? Bool) ?? false)
        gun.zRotation = CGFloat(state["aim_angle"] as? Double ?? 0)
        lastStateTime = now
    }

    func tick(delta: TimeInterval, now: TimeInterval) {
        let age = min(now - lastStateTime, 0.12)
        let predicted = targetPosition + (targetVelocity * age)
        let blend = min(CGFloat(delta) * 18, 1)
        position = CGPoint(x: position.x + (predicted.x - position.x) * blend, y: position.y + (predicted.y - position.y) * blend)
        boo.updateAnimation(delta: delta, moving: targetVelocity.length > 1)
    }
}
