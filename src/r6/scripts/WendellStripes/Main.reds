module WendellStripes

public class WendellStripesTick extends DelayCallback {
    public let system: wref<WendellStripesSystem>;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.OnTick();
        }
    }
}

// Phase 3: spawn out of view next to a pedestrian, walk, delete rules, and a test of the interaction prompt.
// The character is still a base-game placeholder.
public class WendellStripesSystem extends ScriptableSystem {

    private let m_loopStarted: Bool;
    // Failed rolls since the last appearance. Kept in the save. Used by the increasing-chance setting.
    private persistent let m_failedRolls: Int32;
    private let m_lastDelay: Float;
    // Seconds since the last roll or skipped roll.
    private let m_sinceRoll: Float;

    // Spawn tries that remain after a successful roll found no valid point.
    private let m_retries: Int32;
    private let m_retryTimer: Float;

    private let m_entityID: EntityID;
    private let m_hasEntity: Bool;
    // True after he was seen in the world.
    private let m_setupDone: Bool;
    private let m_age: Float;
    // Seconds since he came into the world.
    private let m_worldTime: Float;
    private let m_spawnForward: Vector4;

    // Walk state.
    private let m_command: ref<AIMoveToCommand>;
    private let m_hasTarget: Bool;
    private let m_target: Vector4;
    private let m_direction: Vector4;
    // True after he went past V. From then on he keeps his direction.
    private let m_passed: Bool;
    private let m_walkTimer: Float;
    private let m_stuckTimer: Float;
    private let m_stuckPosition: Vector4;
    private let m_lastPosition: Vector4;
    private let m_legs: Int32;

    private let m_promptShown: Bool;
    // Stage of the talk, see UpdatePrompt.
    private let m_stage: Int32;
    private let m_shownStage: Int32;
    private let m_stageTimer: Float;
    // The entity is the custom character (not the placeholder of a missing install).
    private let m_custom: Bool;
    private let m_line: scnDialogLineData;
    private let m_lineShown: Bool;
    private let m_lineTimer: Float;
    private let m_lineNumber: Int32;
    // Number of meetings in which V talked to him. Kept in the save.
    private persistent let m_finds: Int32;

    // He stands still: V is in his way, the prompt is shown, or the interaction was used a moment ago.
    private let m_holding: Bool;
    private let m_holdTimer: Float;
    private let m_holdAfterUse: Float;

    private let m_statusTimer: Float;
    private let m_statusPosition: Vector4;

    public static func IdleTick() -> Float = 2.0;
    public static func ActiveTick() -> Float = 0.25;
    public static func MaxLife() -> Float = 180.0;
    // Debug mode: shorter, so that the next forced roll is not blocked for 3 minutes.
    public static func MaxLifeDebug() -> Float = 90.0;
    public static func MaxDistanceFoot() -> Float = 100.0;
    public static func MaxDistanceVehicle() -> Float = 200.0;
    public static func PromptDistance() -> Float = 3.5;
    // V is in his way if V is nearer than this and in his walk direction.
    public static func BlockDistance() -> Float = 2.5;
    // Nearer than this he is not deleted for his life time, also if cover hides him for a moment.
    public static func NearDistance() -> Float = 30.0;
    // After the maximum life time he stays until V does not see him, but not longer than this.
    public static func MaxExtraLife() -> Float = 120.0;
    public static func CharacterRecord() -> TweakDBID = t"Character.WendellStripes";
    // After he gave the cane to V: the same character with no cane in his hand.
    public static func NoCaneRecord() -> TweakDBID = t"Character.WendellStripes_NoCane";
    public static func NoCaneAppearance() -> CName = n"stripes_no_cane";
    // The talk ends when V gives no answer to the second prompt for this time.
    public static func AnswerTime() -> Float = 20.0;
    public static func PlaceholderRecord() -> TweakDBID = t"Character.LowlifeMaleDE";
    // Debug mode: a monk, so that the tester knows which pedestrian he is.
    public static func DebugRecord() -> TweakDBID = t"Character.MonkDE";
    public static func Tag() -> CName = n"WendellStripes";

    private func OnAttach() -> Void {
        GameInstance.GetCallbackSystem()
            .RegisterCallback(n"Session/Ready", this, n"OnSessionReady")
            .SetLifetime(CallbackLifetime.Forever);
    }

    protected cb func OnSessionReady(event: ref<GameSessionEvent>) -> Void {
        if event.IsPreGame() || this.m_loopStarted {
            return;
        }
        this.m_loopStarted = true;
        WendellStripesLog("session ready, tick loop started");
        this.ScheduleTick();
    }

    private func ScheduleTick() -> Void {
        let cb: ref<WendellStripesTick> = new WendellStripesTick();
        cb.system = this;
        this.m_lastDelay = this.m_hasEntity ? WendellStripesSystem.ActiveTick() : WendellStripesSystem.IdleTick();
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, this.m_lastDelay, false);
    }

    public func OnTick() -> Void {
        let settings: ref<WendellStripesSettings> = new WendellStripesSettings();
        let dt: Float = this.m_lastDelay;

        if !settings.enabled {
            if this.m_hasEntity {
                this.Despawn("mod is off");
            }
            this.m_sinceRoll = 0.0;
            this.m_retries = 0;
            this.ScheduleTick();
            return;
        }

        if settings.forgetMeetings && this.m_finds != 0 {
            WendellStripesLog(s"debug: meetings forgotten (finds was \(this.m_finds))");
            this.m_finds = 0;
        }

        if this.m_hasEntity {
            this.UpdateEntity(dt, settings);
        }

        if this.m_retries > 0 && !this.m_hasEntity {
            this.m_retryTimer += dt;
            if this.m_retryTimer >= 2.0 {
                this.m_retryTimer = 0.0;
                this.m_retries -= 1;
                this.TrySpawn(settings.debugMode);
            }
        }

        // The interval is read at each tick, so a menu change applies immediately.
        this.m_sinceRoll += dt;
        if this.m_sinceRoll >= Cast<Float>(settings.interval) {
            this.m_sinceRoll = 0.0;
            this.Roll(settings);
        }

        this.ScheduleTick();
    }

    private func Roll(settings: ref<WendellStripesSettings>) -> Void {
        let game: GameInstance = this.GetGameInstance();
        let debug: Bool = settings.debugMode;

        let reason: String = WendellStripesConditions.BlockReason(game);
        if NotEquals(reason, "") {
            if debug { WendellStripesLog(s"roll skipped: \(reason)"); }
            return;
        }
        if this.m_hasEntity {
            if debug { WendellStripesLog("roll skipped: he is already in the world"); }
            return;
        }
        if settings.nightOnly && !WendellStripesConditions.IsNight(game) {
            if debug { WendellStripesLog("roll skipped: night only, and it is day"); }
            return;
        }

        let inVehicle: Bool = WendellStripesConditions.IsInVehicle(game);
        let others: Int32;
        let crowd: Int32 = WendellStripesConditions.CountCrowd(game, WendellStripesConditions.CrowdRadius(), others);
        let busy: Bool = crowd >= WendellStripesConditions.CrowdMinimum();
        // In debug mode the busy-area check is logged but does not block.
        if !busy && !debug {
            return;
        }

        // Increasing chance: +5% of the value for each failed roll, not more than 10 times the value.
        let chance: Float = settings.chance;
        if settings.increasingChance {
            chance = settings.chance * MinF(1.0 + 0.05 * Cast<Float>(this.m_failedRolls), 10.0);
        }
        let value: Float = RandF() * 100.0;
        let success: Bool = debug || value < chance;
        if debug {
            WendellStripesLog(s"roll: value \(value), chance \(chance) (setting \(settings.chance), failed rolls \(this.m_failedRolls)), forced by debug mode, in vehicle: \(inVehicle), crowd NPCs in 30 m: \(crowd) (busy: \(busy)), other NPCs: \(others)");
        }
        if !success {
            this.m_failedRolls += 1;
            return;
        }
        if !debug {
            this.m_failedRolls = 0;
        }

        this.m_retries = 3;
        this.m_retryTimer = 0.0;
        if this.TrySpawn(debug) {
            this.m_retries = 0;
        }
    }

    private func TrySpawn(debug: Bool) -> Bool {
        let game: GameInstance = this.GetGameInstance();
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();

        if NotEquals(WendellStripesConditions.BlockReason(game), "") {
            return false;
        }
        if !des.IsReady() {
            WendellStripesLog("spawn cancelled: DynamicEntitySystem is not ready");
            return false;
        }

        let point: ref<WendellStripesSpawnPoint> = WendellStripesSpawnSearch.Find(game);
        if debug || point.found {
            WendellStripesLog(s"spawn search: found \(point.found); crowd NPCs in range \(point.crowdTotal), farthest \(point.crowdFarthest) m; valid points \(point.candidates); rejected: distance or direction \(point.rejectedRange), in view \(point.rejectedView), too few neighbors \(point.rejectedNeighbors), no path to V \(point.rejectedPath); tries left \(this.m_retries)");
        }
        if !point.found {
            return false;
        }

        // The custom character. If its record is not there (TweakXL file or archive not installed),
        // use a base-game pedestrian: a monk in debug mode, so that the tester can find him.
        let record: TweakDBID = this.m_finds > 0 ? WendellStripesSystem.NoCaneRecord() : WendellStripesSystem.CharacterRecord();
        let custom: Bool = IsDefined(TweakDBInterface.GetCharacterRecord(record));
        if !custom {
            record = WendellStripesSystem.PlaceholderRecord();
            if debug && IsDefined(TweakDBInterface.GetCharacterRecord(WendellStripesSystem.DebugRecord())) {
                record = WendellStripesSystem.DebugRecord();
            }
        }

        let spec: ref<DynamicEntitySpec> = new DynamicEntitySpec();
        spec.recordID = record;
        spec.position = point.position;
        spec.orientation = point.orientation;
        spec.persistState = false;
        spec.persistSpawn = false;
        spec.alwaysSpawned = false;
        spec.spawnInView = true;
        spec.tags = [WendellStripesSystem.Tag()];

        this.m_entityID = des.CreateEntity(spec);
        this.m_hasEntity = true;
        this.m_setupDone = false;
        this.m_age = 0.0;
        this.m_worldTime = 0.0;
        this.m_stage = 0;
        this.m_shownStage = -1;
        this.m_custom = custom;
        this.m_hasTarget = false;
        this.m_passed = false;
        this.m_legs = 0;
        this.m_walkTimer = 2.0;
        this.m_holding = false;
        this.m_holdAfterUse = 0.0;
        this.m_spawnForward = point.forward;
        this.m_statusTimer = 0.0;
        this.m_statusPosition = point.position;
        this.m_lastPosition = point.position;
        this.m_retries = 0;

        let bearing: String = this.Bearing(point.position);
        WendellStripesLog(s"spawn: \(point.distance) m from V (\(bearing)), \(point.neighbors) crowd NPCs within 10 m, at \(point.position.X), \(point.position.Y), \(point.position.Z); custom character: \(custom), with cane: \(this.m_finds == 0)");
        if debug {
            this.ShowDebugMessage(custom ? s"Stripes test: he came in \(RoundF(point.distance)) m \(bearing)" : s"Stripes test: a monk came in \(RoundF(point.distance)) m \(bearing) (custom character not found)");
        }
        return true;
    }

    // Where a position is, as seen from V: "ahead", "behind", "to the left" or "to the right".
    private func Bearing(position: Vector4) -> String {
        let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(this.GetGameInstance());
        let fwd: Vector4 = player.GetWorldForward();
        let to: Vector4 = position - player.GetWorldPosition();
        let along: Float = fwd.X * to.X + fwd.Y * to.Y;
        let side: Float = fwd.X * to.Y - fwd.Y * to.X;
        if AbsF(along) >= AbsF(side) {
            return along >= 0.0 ? "ahead" : "behind";
        }
        return side >= 0.0 ? "to the left" : "to the right";
    }

    private func ShowDebugMessage(text: String) -> Void {
        let defs = GetAllBlackboardDefs();
        let message: SimpleScreenMessage;
        message.isShown = true;
        message.duration = 6.0;
        message.message = text;
        GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(defs.UI_Notifications).SetVariant(defs.UI_Notifications.WarningMessage, ToVariant(message), true);
    }

    private func UpdateEntity(dt: Float, settings: ref<WendellStripesSettings>) -> Void {
        let game: GameInstance = this.GetGameInstance();
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(game);
        this.m_age += dt;

        let reason: String = WendellStripesConditions.BlockReason(game);
        if Equals(reason, "menu") || Equals(reason, "braindance") || Equals(reason, "cutscene") || Equals(reason, "no player") {
            this.Despawn(s"\(reason) started");
            return;
        }
        let maxLife: Float = settings.debugMode ? WendellStripesSystem.MaxLifeDebug() : WendellStripesSystem.MaxLife();
        if this.m_age >= maxLife + WendellStripesSystem.MaxExtraLife() {
            this.Despawn("maximum life time and the extra time are over");
            return;
        }

        let npc: ref<NPCPuppet> = des.GetEntity(this.m_entityID) as NPCPuppet;
        if !IsDefined(npc) {
            if this.m_setupDone {
                this.Despawn("he is no longer in the world (streamed out)");
            } else {
                if this.m_age > 10.0 {
                    this.Despawn("he did not come into the world in 10 s");
                }
            }
            return;
        }

        let inVehicle: Bool = WendellStripesConditions.IsInVehicle(game);
        let position: Vector4 = npc.GetWorldPosition();
        let distance: Float = Vector4.Distance(player.GetWorldPosition(), position);
        let limit: Float = inVehicle ? WendellStripesSystem.MaxDistanceVehicle() : WendellStripesSystem.MaxDistanceFoot();
        if distance > limit {
            this.Despawn(s"\(distance) m from V, limit \(limit) m");
            return;
        }
        // He never goes away while V can see him.
        if this.m_age >= maxLife && distance > WendellStripesSystem.NearDistance() && !this.IsInView(position, distance) {
            this.Despawn("maximum life time, V does not see him");
            return;
        }

        if !this.m_setupDone {
            this.m_setupDone = true;
            this.m_worldTime = 0.0;
            this.m_stuckTimer = 0.0;
            this.m_stuckPosition = position;
            if inVehicle {
                // From a vehicle he walks with the crowd, in the direction of the pedestrian that he came in behind.
                this.m_passed = true;
                this.m_direction = new Vector4(this.m_spawnForward.X, this.m_spawnForward.Y, 0.0, 0.0);
            }
            let god: Bool = GameInstance.GetGodModeSystem(game).AddGodMode(npc.GetEntityID(), gameGodModeType.Invulnerable, WendellStripesSystem.Tag());
            WendellStripesLog(s"setup: he is in the world; invulnerable: \(god)");
        }
        this.m_worldTime += dt;

        let step: Float = Vector4.Distance(position, this.m_lastPosition);
        if step > 4.0 && this.m_worldTime > 0.5 {
            WendellStripesLog(s"jump: he moved \(step) m in one tick (teleport), now \(distance) m from V");
        }
        this.m_lastPosition = position;

        this.UpdatePrompt(npc, distance, inVehicle, reason, dt);

        if this.m_holdAfterUse > 0.0 {
            this.m_holdAfterUse -= dt;
        }
        let toV: Vector4 = player.GetWorldPosition() - position;
        let blocked: Bool = !inVehicle && distance <= WendellStripesSystem.BlockDistance() && distance > 0.01
            && (this.m_direction.X * toV.X + this.m_direction.Y * toV.Y) / distance >= 0.5;
        let talking: Bool = this.m_stage == 1 || this.m_stage == 2;
        if this.m_promptShown || talking || this.m_holdAfterUse > 0.0 || blocked {
            this.UpdateHold(npc, dt, this.m_promptShown ? "prompt" : (talking ? "talk" : (blocked ? "V is in his way" : "after the interaction")));
        } else {
            if this.m_holding {
                this.m_holding = false;
                this.m_hasTarget = false;
                this.m_walkTimer = 2.0;
                WendellStripesLog("hold: over, he walks again");
            }
            // The first command comes 1 s after he came into the world.
            if this.m_worldTime >= 1.0 {
                this.UpdateWalk(npc, player, position, dt);
            }
        }

        if settings.debugMode {
            this.m_statusTimer += dt;
            if this.m_statusTimer >= 10.0 {
                let moved: Float = Vector4.Distance(position, this.m_statusPosition);
                WendellStripesLog(s"status: age \(this.m_age) s, \(distance) m from V (\(this.Bearing(position))), moved \(moved) m in the last 10 s, legs \(this.m_legs), passed V: \(this.m_passed), in combat: \(NPCPuppet.IsInCombat(npc))");
                this.m_statusTimer = 0.0;
                this.m_statusPosition = position;
            }
        }
    }

    // Gives him the next walk target when he has none, when he reached it, or when he does not move.
    private func UpdateWalk(npc: ref<NPCPuppet>, player: ref<PlayerPuppet>, position: Vector4, dt: Float) -> Void {
        let game: GameInstance = this.GetGameInstance();
        let need: Bool = false;
        let why: String = "";

        if !this.m_hasTarget {
            this.m_walkTimer += dt;
            if this.m_walkTimer >= 2.0 {
                need = true;
                why = "no target";
            }
        } else {
            if Vector4.Distance(position, this.m_target) < 2.5 {
                need = true;
                why = "target reached";
            } else {
                this.m_stuckTimer += dt;
                if this.m_stuckTimer >= 6.0 {
                    if Vector4.Distance(position, this.m_stuckPosition) < 0.5 {
                        need = true;
                        why = "no movement in 6 s";
                    }
                    this.m_stuckTimer = 0.0;
                    this.m_stuckPosition = position;
                }
            }
        }
        if !need {
            return;
        }
        this.m_walkTimer = 0.0;

        let target: Vector4;
        let found: Bool = false;
        let label: String = "";

        if !this.m_passed {
            let to: Vector4 = player.GetWorldPosition();
            let dx: Float = to.X - position.X;
            let dy: Float = to.Y - position.Y;
            let length: Float = SqrtF(dx * dx + dy * dy);
            if length > 0.1 {
                dx = dx / length;
                dy = dy / length;
            }
            this.m_direction = new Vector4(dx, dy, 0.0, 0.0);
            if length > 18.0 {
                // Go from pedestrian to pedestrian in the direction of V.
                found = WendellStripesSpawnSearch.FindWalkTarget(game, position, this.m_direction, 10.0, 28.0, 0.75, target);
                label = "to V, by a pedestrian";
                if !found {
                    found = this.Snap(position, new Vector4(position.X + dx * 14.0, position.Y + dy * 14.0, position.Z, 1.0), target);
                    label = "to V, by the navmesh";
                }
            } else {
                // Go past V at a distance of 3 m.
                found = this.Snap(position, new Vector4(to.X - dy * 3.0 + dx * 12.0, to.Y + dx * 3.0 + dy * 12.0, to.Z, 1.0), target);
                label = "past V";
                this.m_passed = true;
            }
        } else {
            found = WendellStripesSpawnSearch.FindWalkTarget(game, position, this.m_direction, 10.0, 30.0, 0.75, target);
            label = "away, by a pedestrian";
            if !found {
                found = this.Snap(position, new Vector4(position.X + this.m_direction.X * 14.0, position.Y + this.m_direction.Y * 14.0, position.Z, 1.0), target);
                label = "away, by the navmesh";
            }
        }

        if !found {
            // Last try: a pedestrian in any direction, the nearest to his direction first.
            found = WendellStripesSpawnSearch.FindWalkTarget(game, position, this.m_direction, 8.0, 30.0, -1.0, target);
            label = "any pedestrian";
        }
        if !found {
            // Very last try: a navmesh point 12 m away, his direction first, then turned in steps of 45 degrees.
            let step: Int32 = 0;
            while !found && step < 8 {
                // 0, +45, -45, +90, -90, +135, -135, 180 degrees.
                let angle: Float = Deg2Rad(45.0 * Cast<Float>((step + 1) / 2)) * (step % 2 == 0 ? -1.0 : 1.0);
                let ax: Float = this.m_direction.X * CosF(angle) - this.m_direction.Y * SinF(angle);
                let ay: Float = this.m_direction.X * SinF(angle) + this.m_direction.Y * CosF(angle);
                found = this.Snap(position, new Vector4(position.X + ax * 12.0, position.Y + ay * 12.0, position.Z, 1.0), target);
                if found {
                    this.m_direction = new Vector4(ax, ay, 0.0, 0.0);
                }
                step += 1;
            }
            label = "navmesh, turned";
        }
        if !found {
            this.m_hasTarget = false;
            WendellStripesLog(s"walk (\(why)): no target found; new try in 2 s");
            return;
        }
        this.SendWalk(npc, target, s"\(why); \(label)");
    }

    // Puts a position on the pedestrian navmesh. The search goes down from 3 m above the position.
    // False if there is no navmesh there or if he cannot walk to it from `from`.
    private func Snap(from: Vector4, wanted: Vector4, out target: Vector4) -> Bool {
        target = GameInstance.GetNavigationSystem(this.GetGameInstance()).GetNearestNavmeshPointBelowOnlyHumanNavmesh(new Vector4(wanted.X, wanted.Y, wanted.Z + 3.0, 1.0), 1.0, 8);
        return !Vector4.IsZero(target) && WendellStripesSpawnSearch.PathOk(this.GetGameInstance(), from, target);
    }

    private func SendWalk(npc: ref<NPCPuppet>, target: Vector4, label: String) -> Void {
        this.CancelWalk(npc);

        let command: ref<AIMoveToCommand> = new AIMoveToCommand();
        let worldPosition: WorldPosition;
        WorldPosition.SetVector4(worldPosition, target);
        AIPositionSpec.SetWorldPosition(command.movementTarget, worldPosition);
        command.movementType = moveMovementType.Walk;
        command.ignoreNavigation = false;
        command.rotateEntityTowardsFacingTarget = false;
        command.desiredDistanceFromTarget = 1.0;
        command.finishWhenDestinationReached = true;

        let sent: Bool = npc.GetAIControllerComponent().SendCommand(command);
        let position: Vector4 = npc.GetWorldPosition();
        this.m_command = command;
        this.m_target = target;
        this.m_hasTarget = sent;
        this.m_legs += 1;
        this.m_stuckTimer = 0.0;
        this.m_stuckPosition = position;
        WendellStripesLog(s"walk leg \(this.m_legs) (\(label)): sent \(sent), target \(Vector4.Distance(position, target)) m away");
    }

    // Makes him stand still. The hold command is sent again before it ends.
    private func UpdateHold(npc: ref<NPCPuppet>, dt: Float, reason: String) -> Void {
        this.m_holdTimer -= dt;
        if this.m_holding && this.m_holdTimer > 0.0 {
            return;
        }
        if !this.m_holding {
            WendellStripesLog(s"hold: he stops (\(reason))");
        }
        this.CancelWalk(npc);
        let hold: ref<AIHoldPositionCommand> = new AIHoldPositionCommand();
        hold.duration = 3.0;
        npc.GetAIControllerComponent().SendCommand(hold);
        this.m_holding = true;
        this.m_holdTimer = 2.5;
    }

    // True if V can see the position: in the view cone, nearer than 80 m and not behind static cover.
    private func IsInView(position: Vector4, distance: Float) -> Bool {
        let game: GameInstance = this.GetGameInstance();
        if distance > 80.0 {
            return false;
        }
        let cs: ref<CameraSystem> = GameInstance.GetCameraSystem(game);
        let cam: Transform;
        cs.GetActiveCameraWorldTransform(cam);
        let eye: Vector4 = Transform.GetPosition(cam);
        let look: Vector4 = cs.GetActiveCameraForward();
        let to: Vector4 = position - eye;
        let ll: Float = SqrtF(look.X * look.X + look.Y * look.Y);
        let tl: Float = SqrtF(to.X * to.X + to.Y * to.Y);
        if ll <= 0.0 || tl <= 0.0 {
            return true;
        }
        if (look.X * to.X + look.Y * to.Y) / (ll * tl) < CosF(Deg2Rad(WendellStripesSpawnSearch.ViewHalfAngle())) {
            return false;
        }
        let head: Vector4 = position;
        head.Z += 1.6;
        let hit: TraceResult;
        return !GameInstance.GetSpatialQueriesSystem(game).SyncRaycastByCollisionGroup(eye, head, n"Static", hit, true, false);
    }

    private func CancelWalk(npc: ref<NPCPuppet>) -> Void {
        if IsDefined(this.m_command) {
            let ai = npc.GetAIControllerComponent();
            ai.StopExecutingCommand(this.m_command, true);
            ai.CancelCommand(this.m_command);
            this.m_command = null;
        }
        this.m_hasTarget = false;
    }

    // The talk with V. V speaks through the prompt; he answers with subtitle lines.
    // Stage 0: the first prompt. First meeting: he gives the cane. Later meetings: he pays a part
    //          of the debt, or says a line when the debt is paid; then the talk is over.
    // Stage 1 (first meeting only): he speaks, no prompt.
    // Stage 2 (first meeting only): the second prompt of V. Stage 3: the talk is over.
    private func UpdatePrompt(npc: ref<NPCPuppet>, distance: Float, inVehicle: Bool, reason: String, dt: Float) -> Void {
        let game: GameInstance = this.GetGameInstance();

        this.UpdateLine(dt);
        if this.m_stage == 1 {
            this.m_stageTimer -= dt;
            if this.m_stageTimer <= 0.0 {
                this.m_stage = 2;
                this.m_stageTimer = WendellStripesSystem.AnswerTime();
            }
        }

        let want: Bool = (this.m_stage == 0 || this.m_stage == 2) && !inVehicle && Equals(reason, "") && distance <= WendellStripesSystem.PromptDistance();

        if want {
            // V must look at him.
            let cs: ref<CameraSystem> = GameInstance.GetCameraSystem(game);
            let cam: Transform;
            cs.GetActiveCameraWorldTransform(cam);
            let look: Vector4 = cs.GetActiveCameraForward();
            let to: Vector4 = npc.GetWorldPosition() - Transform.GetPosition(cam);
            let ll: Float = SqrtF(look.X * look.X + look.Y * look.Y);
            let tl: Float = SqrtF(to.X * to.X + to.Y * to.Y);
            want = ll > 0.0 && tl > 0.0 && (look.X * to.X + look.Y * to.Y) / (ll * tl) >= 0.8;
        }

        if this.m_stage == 2 && !want {
            // V goes away and gives no answer: the talk is over.
            this.m_stageTimer -= dt;
            if this.m_stageTimer <= 0.0 {
                this.EndTalk("V gave no answer", 0.0);
            }
        }

        if want {
            let text: String;
            if this.m_stage == 2 {
                text = WendellStripesReward.VNextTime();
            } else {
                if this.m_finds == 0 {
                    text = WendellStripesReward.VFirst(WendellStripesConditions.HeistDone(game));
                } else {
                    text = WendellStripesReward.Payment(this.m_finds) > 0 ? WendellStripesReward.VAgain() : WendellStripesReward.VHey();
                }
            }
            let choices: array<String> = [text];
            let actions: array<CName> = [n"Choice1"];
            let shown: Bool = WendellStripesPrompt.Show(game, WendellStripesReward.PromptTitle(), choices, actions, this.m_shownStage != this.m_stage);
            if shown {
                this.m_shownStage = this.m_stage;
            }
            if shown && !this.m_promptShown {
                this.m_promptShown = true;
                let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(game);
                player.RegisterInputListener(this, n"Choice1");
                player.RegisterInputListener(this, n"ChoiceApply");
                if this.m_custom && this.m_stage == 0 && this.m_finds == 0 {
                    // Load his look with no cane now, so that the cane goes away with no delay.
                    npc.PrefetchAppearanceChange(WendellStripesSystem.NoCaneAppearance());
                }
                WendellStripesLog(s"prompt: shown at \(distance) m, stage \(this.m_stage), finds \(this.m_finds)");
            }
        } else {
            if this.m_promptShown {
                this.HidePrompt("V is too far, looks away, or interaction is blocked");
            }
        }
    }

    private func HidePrompt(reason: String) -> Void {
        if !this.m_promptShown {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        this.m_promptShown = false;
        this.m_shownStage = -1;
        this.m_walkTimer = 2.0;
        WendellStripesPrompt.Hide(game);
        let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(game);
        if IsDefined(player) {
            player.UnregisterInputListener(this, n"Choice1");
            player.UnregisterInputListener(this, n"ChoiceApply");
        }
        WendellStripesLog(s"prompt: hidden (\(reason))");
    }

    protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
        if !this.m_promptShown || !ListenerAction.IsButtonJustReleased(action) {
            return false;
        }
        let name: CName = ListenerAction.GetName(action);
        if !Equals(name, n"Choice1") && !Equals(name, n"ChoiceApply") {
            return false;
        }
        if this.m_stage != 0 && this.m_stage != 2 {
            return false;
        }
        let game: GameInstance = this.GetGameInstance();
        let npc: ref<NPCPuppet> = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_entityID) as NPCPuppet;
        WendellStripesLog(s"interaction: input action \(NameToString(name)), stage \(this.m_stage), finds \(this.m_finds)");

        if this.m_stage == 2 {
            // First meeting, the last line of V.
            this.Say(npc, WendellStripesReward.StripesNextTime(WendellStripesConditions.HeistDone(game)), 5.0);
            this.EndTalk("V said the last line", 5.0);
        } else {
            if this.m_finds == 0 {
                // First meeting: he has no money and gives his cane. The cane goes out of his hand.
                WendellStripesReward.Give(game, WendellStripesReward.Cane(), 1, "cane");
                if this.m_custom && IsDefined(npc) {
                    npc.ScheduleAppearanceChange(WendellStripesSystem.NoCaneAppearance());
                }
                this.m_finds = 1;
                WendellStripesLog(s"first meeting: Heist done: \(WendellStripesConditions.HeistDone(game))");
                this.Say(npc, WendellStripesReward.StripesNoMoney(WendellStripesConditions.HeistDone(game)), 7.0);
                this.m_stage = 1;
                this.m_stageTimer = 4.0;
            } else {
                let amount: Int32 = WendellStripesReward.Payment(this.m_finds);
                if amount > 0 {
                    // He pays a part of the debt.
                    WendellStripesReward.Give(game, WendellStripesReward.Money(), amount, "money");
                    this.Say(npc, WendellStripesReward.StripesPays(this.m_finds), 5.0);
                    WendellStripesLog(s"payback: \(amount) at meeting \(this.m_finds + 1); paid in total \(WendellStripesReward.PaidAfter(this.m_finds))");
                    this.m_finds += 1;
                    this.EndTalk("he paid", 4.0);
                } else {
                    // The debt is paid: one of his lines, no money.
                    let index: Int32 = RandRange(0, WendellStripesReward.BrokeLines());
                    this.Say(npc, WendellStripesReward.StripesBroke(index), 5.0);
                    this.m_finds += 1;
                    this.EndTalk(s"the debt is paid, line \(index)", 4.0);
                }
            }
        }
        this.HidePrompt("line used");
        return false;
    }

    // `hold`: he stands still for this time, in seconds, while he says his line.
    private func EndTalk(reason: String, hold: Float) -> Void {
        this.m_stage = 3;
        this.m_holdAfterUse = hold;
        WendellStripesLog(s"talk: over (\(reason)); finds \(this.m_finds)");
    }

    private func Say(npc: ref<NPCPuppet>, text: String, duration: Float) -> Void {
        let game: GameInstance = this.GetGameInstance();
        if this.m_lineShown {
            WendellStripesReward.Unsay(game, this.m_line);
        }
        this.m_lineNumber += 1;
        this.m_line = WendellStripesReward.Say(game, npc, text, duration, this.m_lineNumber);
        this.m_lineShown = true;
        this.m_lineTimer = duration;
    }

    private func UpdateLine(dt: Float) -> Void {
        if !this.m_lineShown {
            return;
        }
        this.m_lineTimer -= dt;
        if this.m_lineTimer <= 0.0 {
            WendellStripesReward.Unsay(this.GetGameInstance(), this.m_line);
            this.m_lineShown = false;
        }
    }

    private func Despawn(reason: String) -> Void {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        this.HidePrompt("he is deleted");
        if this.m_lineShown {
            WendellStripesReward.Unsay(this.GetGameInstance(), this.m_line);
            this.m_lineShown = false;
        }
        let wasSpawned: Bool = des.IsSpawned(this.m_entityID);
        let deleted: Bool = des.DeleteEntity(this.m_entityID);
        this.m_hasEntity = false;
        this.m_setupDone = false;
        this.m_command = null;
        this.m_hasTarget = false;
        WendellStripesLog(s"delete: \(reason); age \(this.m_age) s; was in the world: \(wasSpawned); deleted: \(deleted)");
    }
}
