import AppKit
import SpriteKit

final class GameScene: SKScene, MultiplayerClientDelegate {
    var onlineRun = false
    var continuedRun: RunState?

    private let world = SKNode()
    private let hud = SKNode()
    private let player = PlayerNode()
    private let cameraNode = SKCameraNode()
    private var keys = Set<UInt16>()
    private var mouseWorld = CGPoint.zero
    private var lastUpdateTime: TimeInterval = 0
    private var runStartTime: TimeInterval = 0
    private var score = 0
    private var gunScore = 0
    private var coinsAwarded = false
    private var spawnedChunks = Set<String>()
    private var hostEntityChunks = Set<String>()
    private var mobs: [MobNode] = []
    private var foods: [FoodNode] = []
    private var projectiles: [ProjectileNode] = []
    private var bombs: [BombNode] = []
    private var remotePlayers: [String: RemotePlayerNode] = [:]
    private var networkMobs: [String: MobNode] = [:]
    private var networkFoods: [String: FoodNode] = [:]
    private var nextMobID = 1
    private var nextFoodID = 1
    private var isHost = false
    private var roleAssigned = false
    private var stateSendAccumulator: TimeInterval = 0
    private var mobSendAccumulator: TimeInterval = 0
    private var isPausedOverlay = false
    private var isGameOver = false
    private var tutorialActive = false
    private var tutorialIndex = 0
    private var chatActive = false
    private var chatText = ""
    private var chatMessages: [(String, String, TimeInterval)] = []
    private var lastChatSend: TimeInterval = -999

    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let healthLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let bombLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let multiplayerLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let chatLabel = SKLabelNode(fontNamed: "Menlo")
    private let overlay = SKNode()

    private let tutorialSteps = [
        "Use WASD to move around the map.",
        "Aim with the mouse. Your pistol auto-fires every 0.5 seconds once the headstart ends.",
        "Pick up food to heal 20 health. Staying healthy also lets you use bombs.",
        "Bombs only work at full health. Press Z to throw one toward your cursor.",
        "Goal: stay alive, clear mobs, and keep your score climbing."
    ]

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.72, green: 0.78, blue: 0.62, alpha: 1)
        addChild(world)
        addChild(hud)
        camera = cameraNode
        addChild(cameraNode)
        setupPlayer()
        setupHUD()
        AudioManager.shared.playMusic()
        runStartTime = CACurrentMediaTime()
        if let continuedRun {
            apply(run: continuedRun)
        }
        if onlineRun {
            MultiplayerClient.shared.delegate = self
            MultiplayerClient.shared.connect()
            multiplayerLabel.isHidden = false
        }
        if !SettingsStore.shared.profile.tutorialCompleted && !onlineRun {
            showTutorial()
        }
        spawnAroundPlayers()
    }

    override func willMove(from view: SKView) {
        if onlineRun {
            MultiplayerClient.shared.disconnect()
        }
    }

    private func setupPlayer() {
        player.position = continuedRun?.playerPosition.point ?? CGPoint(x: 922, y: 499)
        player.spawnTime = CACurrentMediaTime()
        player.boo.applySkin(SettingsStore.shared.profile.equippedSkin)
        world.addChild(player)
    }

    private func setupHUD() {
        [scoreLabel, healthLabel, bombLabel, multiplayerLabel, chatLabel].forEach {
            $0.fontSize = 18
            $0.fontColor = .white
            $0.horizontalAlignmentMode = .left
            $0.zPosition = 500
            hud.addChild($0)
        }
        scoreLabel.position = CGPoint(x: -610, y: 330)
        healthLabel.position = CGPoint(x: -610, y: 300)
        bombLabel.position = CGPoint(x: -610, y: 270)
        multiplayerLabel.position = CGPoint(x: -610, y: 240)
        multiplayerLabel.isHidden = true
        chatLabel.position = CGPoint(x: -610, y: -310)
        chatLabel.fontSize = 15
        updateHUD()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        cameraNode.position = player.position
    }

    override func keyDown(with event: NSEvent) {
        if chatActive {
            handleChatKey(event)
            return
        }
        if isPausedOverlay || tutorialActive || isGameOver {
            if isGameOver && (event.keyCode == 36 || event.keyCode == 76) {
                MultiplayerClient.shared.disconnect()
                SceneRouter.shared.showGame(online: onlineRun)
            } else if event.keyCode == 12 {
                MultiplayerClient.shared.disconnect()
                SceneRouter.shared.showTitle()
            } else if isPausedOverlay && event.keyCode == 1 {
                SaveStore.shared.save(runState: exportRunState())
                makeOverlay(title: "Paused", lines: ["Saved.", "Esc: Resume", "Q: Quit to Title"])
            } else if event.keyCode == 53 {
                clearOverlay()
            } else if event.keyCode == 36 || event.keyCode == 76 {
                advanceTutorialOrClose()
            }
            return
        }
        if onlineRun && (event.keyCode == 36 || event.keyCode == 76) {
            chatActive = true
            player.controlsLocked = true
            updateChatLabel()
            return
        }
        if event.keyCode == 53 {
            showPause()
            return
        }
        keys.insert(event.keyCode)
    }

    override func keyUp(with event: NSEvent) {
        keys.remove(event.keyCode)
    }

    override func mouseMoved(with event: NSEvent) {
        mouseWorld = convertPoint(fromView: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = lastUpdateTime == 0 ? 1.0 / 60.0 : min(currentTime - lastUpdateTime, 0.05)
        lastUpdateTime = currentTime
        guard !isPausedOverlay, !tutorialActive, !isGameOver else { return }
        updatePlayer(delta: delta, time: currentTime)
        updateProjectiles(delta: delta, time: currentTime)
        updateBombs(delta: delta, time: currentTime)
        updateMobs(delta: delta, time: currentTime)
        updateFood()
        updateRemotePlayers(delta: delta, time: currentTime)
        spawnAroundPlayers()
        processMultiplayer(delta: delta, time: currentTime)
        pruneChat(time: currentTime)
        cameraNode.position = player.position
        hud.position = cameraNode.position
        updateHUD()
    }

    private func updatePlayer(delta: TimeInterval, time: TimeInterval) {
        var direction = CGVector.zero
        if keys.contains(SettingsStore.shared.payload.controls.moveLeft) { direction.dx -= 1 }
        if keys.contains(SettingsStore.shared.payload.controls.moveRight) { direction.dx += 1 }
        if keys.contains(SettingsStore.shared.payload.controls.moveUp) { direction.dy += 1 }
        if keys.contains(SettingsStore.shared.payload.controls.moveDown) { direction.dy -= 1 }
        if player.controlsLocked { direction = .zero }
        player.velocity = direction.normalized * 600
        player.position = player.position + (player.velocity * CGFloat(delta))
        player.aim(at: mouseWorld)
        player.update(delta: delta, time: time)
        if player.gunActive && time - player.lastFireTime >= 0.5 {
            fireProjectile(local: true, position: player.position + CGVector(dx: cos(player.gun.zRotation) * 46, dy: sin(player.gun.zRotation) * 46), angle: player.gun.zRotation, time: time)
            player.lastFireTime = time
        }
        if keys.contains(SettingsStore.shared.payload.controls.throwBomb), player.canBomb(time: time) {
            throwBomb(time: time)
        }
    }

    private func fireProjectile(local: Bool, position: CGPoint, angle: CGFloat, time: TimeInterval) {
        let projectile = ProjectileNode()
        projectile.position = position
        projectile.zRotation = angle
        projectile.direction = CGVector(dx: cos(angle), dy: sin(angle))
        projectile.shooterLocal = local
        projectile.bornTime = time
        world.addChild(projectile)
        projectiles.append(projectile)
        if local && onlineRun {
            MultiplayerClient.shared.sendWorldMessage("projectile_fired", ["position": pointPayload(position), "rotation": Double(angle)])
        }
    }

    private func throwBomb(time: TimeInterval) {
        let direction = (mouseWorld - player.position).normalized
        let bomb = BombNode()
        bomb.position = player.position + (direction * 36)
        bomb.velocity = direction * 950
        bomb.bornTime = time
        world.addChild(bomb)
        bombs.append(bomb)
        player.lastBombTime = time
    }

    private func updateProjectiles(delta: TimeInterval, time: TimeInterval) {
        for projectile in projectiles {
            projectile.position = projectile.position + (projectile.direction * CGFloat(1200 * delta))
            if time - projectile.bornTime > 2 {
                projectile.removeFromParent()
                continue
            }
            guard projectile.shooterLocal else { continue }
            for mob in mobs where mob.parent != nil && distance(projectile.position, mob.position) < 36 {
                handleProjectileHit(mob)
                projectile.removeFromParent()
                break
            }
        }
        projectiles.removeAll { $0.parent == nil }
    }

    private func updateBombs(delta: TimeInterval, time: TimeInterval) {
        for bomb in bombs {
            bomb.velocity = bomb.velocity * 0.986
            bomb.position = bomb.position + (bomb.velocity * CGFloat(delta))
            bomb.zRotation += CGFloat(delta) * 7
            if time - bomb.bornTime >= 1.4 {
                explodeBomb(bomb)
            }
        }
        bombs.removeAll { $0.parent == nil }
    }

    private func updateMobs(delta: TimeInterval, time: TimeInterval) {
        for mob in mobs where mob.parent != nil {
            if time - mob.spawnTime >= 5 {
                let target = nearestPlayer(to: mob.position)
                let direction = (target - mob.position).normalized
                mob.position = mob.position + (direction * CGFloat(mob.moveSpeed * delta))
            }
            if distance(mob.position, player.position) < 48 && time - player.spawnTime >= 5 {
                player.currentHealth = max(0, player.currentHealth - mob.contactDamage * CGFloat(delta))
                if player.currentHealth <= 0 {
                    showGameOver()
                }
            }
        }
        mobs.removeAll { $0.parent == nil }
    }

    private func updateFood() {
        for food in foods where food.parent != nil && distance(food.position, player.position) < 42 {
            if onlineRun, !isHost {
                if let id = food.networkID {
                    MultiplayerClient.shared.sendWorldMessage("food_collect", ["food_id": id])
                }
            } else {
                collectFood(food, collectorID: MultiplayerClient.shared.localPlayerID)
            }
        }
        foods.removeAll { $0.parent == nil }
    }

    private func handleProjectileHit(_ mob: MobNode) {
        if onlineRun, !isHost, let id = mob.networkID {
            MultiplayerClient.shared.sendWorldMessage("projectile_hit", ["mob_id": id, "damage": 1.0])
            return
        }
        mob.health -= 1
        if mob.health <= 0 {
            addScore(1, countsForCoins: true)
            if onlineRun, let id = mob.networkID {
                networkMobs[id] = nil
                MultiplayerClient.shared.sendWorldMessage("mob_died", ["mob_id": id, "counts_for_coins": true])
            }
            mob.removeFromParent()
        }
    }

    private func explodeBomb(_ bomb: BombNode) {
        let flash = SKSpriteNode(texture: AssetLoader.texture("bombs/tank_explosion12.png"), size: CGSize(width: 360, height: 360))
        flash.position = bomb.position
        flash.zPosition = 80
        world.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.28), .removeFromParent()]))
        if onlineRun, !isHost {
            MultiplayerClient.shared.sendWorldMessage("bomb_exploded", ["position": pointPayload(bomb.position), "radius": 3000.0, "damage": 9999.0])
            bomb.removeFromParent()
            return
        }
        var kills = 0
        for mob in mobs where mob.parent != nil && distance(mob.position, bomb.position) <= 3000 {
            kills += 1
            if let id = mob.networkID {
                networkMobs[id] = nil
                MultiplayerClient.shared.sendWorldMessage("mob_died", ["mob_id": id, "counts_for_coins": false])
            }
            mob.removeFromParent()
        }
        if kills > 0 { addScore(kills, countsForCoins: false) }
        bomb.removeFromParent()
    }

    private func collectFood(_ food: FoodNode, collectorID: String) {
        if collectorID == MultiplayerClient.shared.localPlayerID || collectorID.isEmpty {
            player.currentHealth = min(player.maxHealth, player.currentHealth + 20)
        }
        if onlineRun, isHost, let id = food.networkID {
            networkFoods[id] = nil
            MultiplayerClient.shared.sendWorldMessage("food_collected", ["food_id": id, "collector_player_id": collectorID])
        }
        food.removeFromParent()
    }

    private func addScore(_ amount: Int, countsForCoins: Bool) {
        score += amount
        if countsForCoins { gunScore += amount }
    }

    private func spawnAroundPlayers() {
        if onlineRun && !roleAssigned { return }
        let centers = spawnCenters()
        for center in centers {
            let chunk = worldToChunk(center)
            for x in (chunk.0 - 2)...(chunk.0 + 2) {
                for y in (chunk.1 - 2)...(chunk.1 + 2) {
                    let key = "\(x):\(y)"
                    if spawnedChunks.contains(key) { continue }
                    spawnedChunks.insert(key)
                    spawnChunk(x: x, y: y)
                }
            }
        }
    }

    private func spawnChunk(x: Int, y: Int) {
        let origin = CGPoint(x: CGFloat(x) * 900, y: CGFloat(y) * 900)
        for index in 0..<10 {
            let tree = SKSpriteNode(texture: AssetLoader.texture("trees/pine_tree.png"), size: CGSize(width: 130, height: 160))
            tree.position = seededPoint(origin: origin, salt: index)
            tree.zPosition = 2
            world.addChild(tree)
        }
        if onlineRun && !isHost { return }
        if onlineRun && hostEntityChunks.contains("\(x):\(y)") { return }
        hostEntityChunks.insert("\(x):\(y)")
        let mobChance: Double = onlineRun ? 0.75 : 0.35
        if Double.random(in: 0...1) <= mobChance {
            let count = 1 + min(score / 20, 4)
            for index in 0..<count {
                let kind: MobNode.Kind = score >= 35 && Double.random(in: 0...1) < 0.55 ? .heavy : (score >= 12 && Double.random(in: 0...1) < 0.45 ? .medium : .slime)
                let mob = MobNode(kind: kind)
                mob.position = farSpawn(origin: origin, salt: 30 + index, minimum: 300)
                mob.spawnTime = CACurrentMediaTime()
                world.addChild(mob)
                mobs.append(mob)
                if onlineRun {
                    let id = "mob_\(nextMobID)"
                    nextMobID += 1
                    mob.networkID = id
                    networkMobs[id] = mob
                    MultiplayerClient.shared.sendWorldMessage("world_spawn", mobPayload(id: id, mob: mob))
                }
            }
        }
        if Double.random(in: 0...1) <= 0.45 {
            for index in 0..<2 {
                let textureIndex = Int.random(in: 0..<FoodNode.texturePaths.count)
                let food = FoodNode(textureIndex: textureIndex)
                food.position = farSpawn(origin: origin, salt: 70 + index, minimum: 140)
                world.addChild(food)
                foods.append(food)
                if onlineRun {
                    let id = "food_\(nextFoodID)"
                    nextFoodID += 1
                    food.networkID = id
                    networkFoods[id] = food
                    MultiplayerClient.shared.sendWorldMessage("world_spawn", ["entity_type": "food", "food_id": id, "texture_index": textureIndex, "visual_scale": 1.8, "position": pointPayload(food.position)])
                }
            }
        }
    }

    private func processMultiplayer(delta: TimeInterval, time: TimeInterval) {
        guard onlineRun else { return }
        stateSendAccumulator += delta
        if stateSendAccumulator >= 0.05 {
            stateSendAccumulator = 0
            MultiplayerClient.shared.sendPlayerState(localPlayerState())
        }
        guard isHost else { return }
        mobSendAccumulator += delta
        if mobSendAccumulator >= 0.12 {
            mobSendAccumulator = 0
            for (id, mob) in networkMobs where mob.parent != nil {
                MultiplayerClient.shared.sendWorldMessage("mob_state", ["mob_id": id, "position": pointPayload(mob.position), "health": Double(mob.health)])
            }
        }
    }

    func multiplayerStatusChanged(_ status: MultiplayerStatus, detail: String) {
        multiplayerLabel.text = "Multiplayer: \(detail)"
    }

    func multiplayerHostChanged(isHost: Bool) {
        self.isHost = isHost
        roleAssigned = true
        multiplayerLabel.text = isHost ? "Multiplayer: Online (Host)" : "Multiplayer: Online"
        spawnAroundPlayers()
    }

    func multiplayerReceived(_ message: [String: Any]) {
        let type = message["type"] as? String ?? ""
        switch type {
        case "player_state":
            applyRemotePlayer(message)
        case "player_left":
            if let id = message["player_id"] as? String {
                remotePlayers[id]?.removeFromParent()
                remotePlayers[id] = nil
            }
        case "player_joined":
            if isHost { sendWorldSnapshot() }
        case "world_snapshot":
            if !isHost { applyWorldSnapshot(message) }
        case "world_spawn":
            if !isHost { applyWorldSpawn(message) }
        case "mob_state":
            if !isHost { applyMobState(message) }
        case "mob_died":
            applyMobDied(message)
        case "projectile_hit":
            if isHost, let id = message["mob_id"] as? String, let mob = networkMobs[id] { handleProjectileHit(mob) }
        case "projectile_fired":
            applyRemoteProjectile(message)
        case "bomb_exploded":
            if isHost, let pos = pointFrom(message["position"]) {
                let bomb = BombNode()
                bomb.position = pos
                explodeBomb(bomb)
            }
        case "food_collect":
            if isHost, let id = message["food_id"] as? String, let food = networkFoods[id] {
                collectFood(food, collectorID: message["from_player_id"] as? String ?? "")
            }
        case "food_collected":
            if let id = message["food_id"] as? String, let food = networkFoods[id] {
                collectFood(food, collectorID: message["collector_player_id"] as? String ?? "")
            }
        case "chat_message":
            let fromID = message["from_player_id"] as? String ?? ""
            if fromID != MultiplayerClient.shared.localPlayerID {
                chatMessages.append((message["username"] as? String ?? "Player", message["text"] as? String ?? "", CACurrentMediaTime()))
                updateChatLabel()
            }
        default:
            break
        }
    }

    private func applyRemotePlayer(_ message: [String: Any]) {
        guard let id = message["from_player_id"] as? String, id != MultiplayerClient.shared.localPlayerID else { return }
        let remote = remotePlayers[id] ?? RemotePlayerNode()
        if remote.parent == nil {
            world.addChild(remote)
            remotePlayers[id] = remote
        }
        remote.apply(message, now: CACurrentMediaTime())
    }

    private func updateRemotePlayers(delta: TimeInterval, time: TimeInterval) {
        for remote in remotePlayers.values {
            remote.tick(delta: delta, now: time)
        }
    }

    private func sendWorldSnapshot() {
        let mobData = networkMobs.map { mobPayload(id: $0.key, mob: $0.value) }
        let foodData = networkFoods.map { ["entity_type": "food", "food_id": $0.key, "texture_index": $0.value.textureIndex, "visual_scale": 1.8, "position": pointPayload($0.value.position)] as [String: Any] }
        MultiplayerClient.shared.sendWorldMessage("world_snapshot", ["mobs": mobData, "foods": foodData])
    }

    private func applyWorldSnapshot(_ message: [String: Any]) {
        for mob in networkMobs.values { mob.removeFromParent() }
        for food in networkFoods.values { food.removeFromParent() }
        networkMobs.removeAll()
        networkFoods.removeAll()
        mobs.removeAll()
        foods.removeAll()
        for item in message["mobs"] as? [[String: Any]] ?? [] { applyWorldSpawn(item) }
        for item in message["foods"] as? [[String: Any]] ?? [] { applyWorldSpawn(item) }
    }

    private func applyWorldSpawn(_ message: [String: Any]) {
        if message["entity_type"] as? String == "food" {
            let id = message["food_id"] as? String ?? ""
            guard !id.isEmpty, networkFoods[id] == nil, let pos = pointFrom(message["position"]) else { return }
            let food = FoodNode(textureIndex: Int(message["texture_index"] as? Double ?? 0))
            food.networkID = id
            food.position = pos
            world.addChild(food)
            foods.append(food)
            networkFoods[id] = food
            return
        }
        let id = message["mob_id"] as? String ?? ""
        guard !id.isEmpty, networkMobs[id] == nil, let pos = pointFrom(message["position"]) else { return }
        let kind = MobNode.Kind(rawValue: message["mob_kind"] as? String ?? "slime") ?? .slime
        let mob = MobNode(kind: kind)
        mob.networkID = id
        mob.position = pos
        mob.health = CGFloat(message["health"] as? Double ?? Double(mob.health))
        world.addChild(mob)
        mobs.append(mob)
        networkMobs[id] = mob
    }

    private func applyMobState(_ message: [String: Any]) {
        guard let id = message["mob_id"] as? String, let mob = networkMobs[id], let pos = pointFrom(message["position"]) else { return }
        mob.position = CGPoint(x: mob.position.x + (pos.x - mob.position.x) * 0.45, y: mob.position.y + (pos.y - mob.position.y) * 0.45)
        mob.health = CGFloat(message["health"] as? Double ?? Double(mob.health))
    }

    private func applyMobDied(_ message: [String: Any]) {
        guard let id = message["mob_id"] as? String else { return }
        networkMobs[id]?.removeFromParent()
        networkMobs[id] = nil
    }

    private func applyRemoteProjectile(_ message: [String: Any]) {
        guard let pos = pointFrom(message["position"]) else { return }
        fireProjectile(local: false, position: pos, angle: CGFloat(message["rotation"] as? Double ?? 0), time: CACurrentMediaTime())
    }

    private func showPause() {
        isPausedOverlay = true
        AudioManager.shared.pause(true)
        makeOverlay(title: "Paused", lines: ["Esc: Resume", "S: Save Run", "Q: Quit to Title"])
    }

    private func showTutorial() {
        tutorialActive = true
        tutorialIndex = 0
        makeOverlay(title: "How To Play", lines: [tutorialSteps[tutorialIndex], "Press Enter for next tip."])
    }

    private func advanceTutorialOrClose() {
        if tutorialActive {
            tutorialIndex += 1
            if tutorialIndex >= tutorialSteps.count {
                SettingsStore.shared.markTutorialCompleted()
                tutorialActive = false
                overlay.removeFromParent()
            } else {
                makeOverlay(title: "How To Play", lines: [tutorialSteps[tutorialIndex], "Press Enter for next tip."])
            }
        }
    }

    private func clearOverlay() {
        if tutorialActive { return }
        isPausedOverlay = false
        overlay.removeFromParent()
        AudioManager.shared.pause(false)
    }

    private func showGameOver() {
        guard !coinsAwarded else { return }
        coinsAwarded = true
        isGameOver = true
        SettingsStore.shared.addCoins(gunScore)
        makeOverlay(title: "GAME OVER", lines: ["Score: \(score)", "Coins earned: \(gunScore)", "Total coins: \(SettingsStore.shared.profile.coins)", "Enter: New Run", "Q: Quit to Title"])
    }

    private func makeOverlay(title: String, lines: [String]) {
        overlay.removeAllChildren()
        overlay.removeFromParent()
        overlay.zPosition = 1000
        let shade = SKShapeNode(rect: CGRect(x: -size.width, y: -size.height, width: size.width * 2, height: size.height * 2))
        shade.fillColor = .black.withAlphaComponent(0.72)
        shade.strokeColor = .clear
        overlay.addChild(shade)
        let titleNode = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        titleNode.text = title
        titleNode.fontSize = 42
        titleNode.position = CGPoint(x: 0, y: 130)
        overlay.addChild(titleNode)
        var y: CGFloat = 65
        for line in lines {
            let node = SKLabelNode(fontNamed: "AvenirNext-Regular")
            node.text = line
            node.fontSize = 22
            node.position = CGPoint(x: 0, y: y)
            overlay.addChild(node)
            y -= 42
        }
        cameraNode.addChild(overlay)
    }

    private func handleChatKey(_ event: NSEvent) {
        if event.keyCode == 53 {
            chatActive = false
            player.controlsLocked = false
            chatText = ""
            updateChatLabel()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            let trimmed = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, CACurrentMediaTime() - lastChatSend > 0.5 {
                let text = String(trimmed.prefix(120))
                chatMessages.append((SettingsStore.shared.profile.username, text, CACurrentMediaTime()))
                MultiplayerClient.shared.sendWorldMessage("chat_message", ["username": SettingsStore.shared.profile.username, "text": text])
                lastChatSend = CACurrentMediaTime()
            }
            chatActive = false
            player.controlsLocked = false
            chatText = ""
            updateChatLabel()
            return
        }
        if event.keyCode == 51 {
            if !chatText.isEmpty { chatText.removeLast() }
            updateChatLabel()
            return
        }
        if let chars = event.characters, chatText.count < 120 {
            chatText += chars.filter { !$0.isNewline }
            updateChatLabel()
        }
    }

    private func pruneChat(time: TimeInterval) {
        if !chatActive {
            chatMessages.removeAll { time - $0.2 > 8 }
        }
        updateChatLabel()
    }

    private func updateChatLabel() {
        var lines = chatMessages.suffix(6).map { "\($0.0): \($0.1)" }
        if chatActive { lines.append("> \(chatText)") }
        chatLabel.text = lines.joined(separator: "\n")
    }

    private func updateHUD() {
        scoreLabel.text = "Score: \(score)"
        healthLabel.text = "Health: \(Int(player.currentHealth))/\(Int(player.maxHealth))"
        let remaining = max(0, 30 - Int(CACurrentMediaTime() - player.lastBombTime))
        bombLabel.text = player.canBomb(time: CACurrentMediaTime()) ? "Bomb: Ready" : "Bomb: \(remaining)s"
    }

    private func apply(run: RunState) {
        score = run.score
        gunScore = run.gunScore
        player.currentHealth = run.currentHealth
        player.maxHealth = run.maxHealth
        player.position = run.playerPosition.point
        runStartTime = CACurrentMediaTime() - run.elapsedRunTimeSec
    }

    private func exportRunState() -> RunState {
        RunState(
            score: score,
            gunScore: gunScore,
            currentHealth: player.currentHealth,
            maxHealth: player.maxHealth,
            playerPosition: Vec2(player.position),
            elapsedRunTimeSec: CACurrentMediaTime() - runStartTime
        )
    }

    private func localPlayerState() -> [String: Any] {
        [
            "position": pointPayload(player.position),
            "velocity": ["x": Double(player.velocity.dx), "y": Double(player.velocity.dy)],
            "username": SettingsStore.shared.profile.username,
            "skin_id": SettingsStore.shared.profile.equippedSkin,
            "animation": player.velocity.length > 1 ? "walk" : "idle",
            "aim_angle": Double(player.gun.zRotation),
            "gun_active": player.gunActive
        ]
    }

    private func mobPayload(id: String, mob: MobNode) -> [String: Any] {
        ["entity_type": "mob", "mob_id": id, "mob_kind": mob.kind.rawValue, "position": pointPayload(mob.position), "health": Double(mob.health)]
    }

    private func pointPayload(_ point: CGPoint) -> [String: Double] {
        ["x": Double(point.x), "y": Double(point.y)]
    }

    private func pointFrom(_ value: Any?) -> CGPoint? {
        guard let dict = value as? [String: Any] else { return nil }
        return CGPoint(x: CGFloat(dict["x"] as? Double ?? 0), y: CGFloat(dict["y"] as? Double ?? 0))
    }

    private func worldToChunk(_ point: CGPoint) -> (Int, Int) {
        (Int(floor(point.x / 900)), Int(floor(point.y / 900)))
    }

    private func spawnCenters() -> [CGPoint] {
        guard onlineRun, isHost else { return [player.position] }
        return [player.position] + remotePlayers.values.map(\.position)
    }

    private func nearestPlayer(to point: CGPoint) -> CGPoint {
        ([player.position] + remotePlayers.values.map(\.position)).min { distance($0, point) < distance($1, point) } ?? player.position
    }

    private func farSpawn(origin: CGPoint, salt: Int, minimum: CGFloat) -> CGPoint {
        for offset in 0..<8 {
            let point = seededPoint(origin: origin, salt: salt + offset)
            if spawnCenters().allSatisfy({ distance(point, $0) >= minimum }) {
                return point
            }
        }
        return seededPoint(origin: origin, salt: salt)
    }

    private func seededPoint(origin: CGPoint, salt: Int) -> CGPoint {
        let a = CGFloat(abs(sin(Double(origin.x + CGFloat(salt) * 91))) .truncatingRemainder(dividingBy: 1))
        let b = CGFloat(abs(cos(Double(origin.y + CGFloat(salt) * 57))) .truncatingRemainder(dividingBy: 1))
        return CGPoint(x: origin.x + a * 900, y: origin.y + b * 900)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
