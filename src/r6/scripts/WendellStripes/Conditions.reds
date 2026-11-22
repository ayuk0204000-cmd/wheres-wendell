module WendellStripes

// Checks that permit or block a roll. Engine-dependent reads are kept in this file.
public abstract class WendellStripesConditions {

    public static func CrowdRadius() -> Float = 30.0;
    public static func CrowdMinimum() -> Int32 = 8;

    public static func GetPlayerPuppet(game: GameInstance) -> ref<PlayerPuppet> {
        return GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
    }

    // True when the Heist is done, that is, after Jackie's death. It does not block him: it only
    // selects the lines of the first meeting. The game's own scripts read this fact in the same
    // way (rpgManager).
    public static func HeistDone(game: GameInstance) -> Bool {
        return GameInstance.GetQuestsSystem(game).GetFact(n"q005_done") > 0;
    }

    // Returns "" if a roll is permitted, or the reason why it is not.
    // The crowd check and the "already in the world" check are not here.
    public static func BlockReason(game: GameInstance) -> String {
        let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(game);
        if !IsDefined(player) {
            return "no player";
        }

        let defs = GetAllBlackboardDefs();
        let boards = GameInstance.GetBlackboardSystem(game);

        if boards.Get(defs.UI_System).GetBool(defs.UI_System.IsInMenu) {
            return "menu";
        }
        if boards.Get(defs.Braindance).GetBool(defs.Braindance.IsActive) {
            return "braindance";
        }
        if player.IsInCombat() {
            return "combat";
        }

        let psm = boards.GetLocalInstanced(player.GetEntityID(), defs.PlayerStateMachine);
        if !IsDefined(psm) {
            return "no player state";
        }
        // Tiers 4 and 5 are cinematics without free camera. Tiers 1 to 3 include missions and walk-and-talk scenes.
        let tier: Int32 = psm.GetInt(defs.PlayerStateMachine.SceneTier);
        if tier > 3 {
            return "cutscene";
        }

        let vehicle = player.GetMountedVehicle();
        if IsDefined(vehicle) && Equals(vehicle.GetRecordID(), t"Vehicle.ue_metro_train") {
            return "metro";
        }

        return "";
    }

    // Night is from 20:00 to 06:00 game time.
    public static func IsNight(game: GameInstance) -> Bool {
        let hour: Int32 = GameTime.Hours(GameInstance.GetTimeSystem(game).GetGameTime());
        return hour >= 20 || hour < 6;
    }

    public static func IsInVehicle(game: GameInstance) -> Bool {
        let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(game);
        return IsDefined(player) && VehicleComponent.IsMountedToVehicle(game, player);
    }

    // Number of active crowd pedestrians within `radius` of the player.
    // `others` gets the number of other NPCs (not crowd) in the same radius, for the log.
    public static func CountCrowd(game: GameInstance, radius: Float, out others: Int32) -> Int32 {
        let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(game);
        let count: Int32 = 0;
        others = 0;
        if !IsDefined(player) {
            return 0;
        }

        let query: TargetSearchQuery = TSQ_NPC();
        query.maxDistance = radius;
        query.filterObjectByDistance = true;
        query.testedSet = TargetingSet.Complete;
        query.includeSecondaryTargets = false;
        let parts: array<TS_TargetPartInfo>;
        GameInstance.GetTargetingSystem(game).GetTargetParts(player, query, parts);

        let done: array<Uint64>;
        for part in parts {
            let npc: ref<ScriptedPuppet> = TS_TargetPartInfo.GetComponent(part).GetEntity() as ScriptedPuppet;
            if IsDefined(npc) {
                let id: Uint64 = Cast<Uint64>(EntityID.GetHash(npc.GetEntityID()));
                if !ArrayContains(done, id) {
                    ArrayPush(done, id);
                    if npc.IsCrowd() && npc.IsActive() {
                        count += 1;
                    } else {
                        others += 1;
                    }
                }
            }
        }
        return count;
    }
}
