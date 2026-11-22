module WendellStripes

public class WendellStripesSpawnPoint {
    public let found: Bool;
    public let position: Vector4;
    public let orientation: Quaternion;
    // Direction in which the pedestrian next to the point walks.
    public let forward: Vector4;
    // Crowd NPCs within NeighborRadius of the point.
    public let neighbors: Int32;
    public let distance: Float;
    // For the log.
    public let crowdTotal: Int32;
    public let crowdFarthest: Float;
    public let candidates: Int32;
    public let rejectedRange: Int32;
    public let rejectedView: Int32;
    public let rejectedNeighbors: Int32;
    public let rejectedPath: Int32;
}

// Finds a spawn point directly behind a walking crowd pedestrian. That place is on the
// pavement, is free (the pedestrian just walked through it) and is near other NPCs.
public abstract class WendellStripesSpawnSearch {

    public static func NeighborRadius() -> Float = 10.0;
    public static func NeighborMinimum() -> Int32 = 3;
    public static func BehindDistance() -> Float = 1.5;
    public static func FootMin() -> Float = 30.0;
    public static func FootMax() -> Float = 60.0;
    public static func VehicleMin() -> Float = 80.0;
    public static func VehicleMax() -> Float = 150.0;
    // Half angle of the cone in front of the camera in which a spawn is not permitted.
    public static func ViewHalfAngle() -> Float = 65.0;

    // True if he can walk from `from` to `to`: a path on the pedestrian navmesh exists, it is not a
    // long way round (a wall, a fence or a median is between the points), and it does not cross traffic lanes.
    // A move command to a target with no path teleports the NPC, so each target must pass this test.
    public static func PathOk(game: GameInstance, from: Vector4, to: Vector4) -> Bool {
        let path: ref<NavigationPath> = GameInstance.GetNavigationSystem(game).CalculatePathOnlyHumanNavmesh(from, to, NavGenAgentSize.Human, 1.0);
        if !IsDefined(path) || ArraySize(path.path) < 2 {
            return false;
        }
        let direct: Float = Vector4.Distance(from, to);
        if path.CalculateLength() > MaxF(direct * 1.6, direct + 6.0) {
            return false;
        }
        let crossing: Vector4;
        return !GameInstance.GetTrafficSystem(game).IsPathIntersectingWithTraffic(path.path, 0.5, crossing);
    }

    // Finds the next walk target: the position of a crowd pedestrian that is `minDistance` to
    // `maxDistance` from `from`, in the direction `direction`. A pedestrian position is on the
    // pavement and on the navmesh. Returns false if there is none.
    public static func FindWalkTarget(game: GameInstance, from: Vector4, direction: Vector4, minDistance: Float, maxDistance: Float, minCos: Float, out target: Vector4) -> Bool {
        let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(game);
        let dl: Float = SqrtF(direction.X * direction.X + direction.Y * direction.Y);
        if !IsDefined(player) || dl <= 0.0 {
            return false;
        }

        let query: TargetSearchQuery = TSQ_NPC();
        query.maxDistance = 120.0;
        query.filterObjectByDistance = true;
        query.testedSet = TargetingSet.Complete;
        query.includeSecondaryTargets = false;
        let parts: array<TS_TargetPartInfo>;
        GameInstance.GetTargetingSystem(game).GetTargetParts(player, query, parts);

        // minCos 0.75: only pedestrians in the direction. minCos -1.0: a pedestrian in any direction, the best direction first.
        let positions: array<Vector4>;
        let cosines: array<Float>;
        for part in parts {
            let npc: ref<ScriptedPuppet> = TS_TargetPartInfo.GetComponent(part).GetEntity() as ScriptedPuppet;
            if IsDefined(npc) && npc.IsCrowd() && npc.IsActive() {
                let pos: Vector4 = npc.GetWorldPosition();
                let dx: Float = pos.X - from.X;
                let dy: Float = pos.Y - from.Y;
                let dist: Float = SqrtF(dx * dx + dy * dy);
                // Not a target on a different level (bridge, underpass).
                if dist >= minDistance && dist <= maxDistance && AbsF(pos.Z - from.Z) < 3.0 {
                    let cos: Float = (dx * direction.X + dy * direction.Y) / (dist * dl);
                    if cos > minCos {
                        ArrayPush(positions, pos);
                        ArrayPush(cosines, cos);
                    }
                }
            }
        }

        // The best direction first. Not more than 6 path tests.
        let tries: Int32 = 0;
        while tries < 6 && ArraySize(positions) > 0 {
            let best: Int32 = 0;
            let i: Int32 = 1;
            while i < ArraySize(cosines) {
                if cosines[i] > cosines[best] {
                    best = i;
                }
                i += 1;
            }
            if WendellStripesSpawnSearch.PathOk(game, from, positions[best]) {
                target = positions[best];
                return true;
            }
            ArrayErase(positions, best);
            ArrayErase(cosines, best);
            tries += 1;
        }
        return false;
    }

    // Puts a position on the pedestrian navmesh (the search goes down from 3 m above it).
    // False if there is no navmesh there or if an NPC cannot walk to it from `from`.
    public static func SnapReachable(game: GameInstance, from: Vector4, wanted: Vector4, out target: Vector4) -> Bool {
        target = GameInstance.GetNavigationSystem(game).GetNearestNavmeshPointBelowOnlyHumanNavmesh(new Vector4(wanted.X, wanted.Y, wanted.Z + 3.0, 1.0), 1.0, 8);
        return !Vector4.IsZero(target) && WendellStripesSpawnSearch.PathOk(game, from, target);
    }

    // True if V can see the position: in the view cone, nearer than 80 m and not behind static cover.
    public static func IsInView(game: GameInstance, position: Vector4, distance: Float) -> Bool {
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

    public static func Find(game: GameInstance) -> ref<WendellStripesSpawnPoint> {
        let result: ref<WendellStripesSpawnPoint> = new WendellStripesSpawnPoint();
        let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(game);
        if !IsDefined(player) {
            return result;
        }

        let origin: Vector4 = player.GetWorldPosition();
        let vehicle = player.GetMountedVehicle();
        let inVehicle: Bool = IsDefined(vehicle);
        let minDistance: Float = WendellStripesSpawnSearch.FootMin();
        let maxDistance: Float = WendellStripesSpawnSearch.FootMax();
        let travel: Vector4 = player.GetWorldForward();
        if inVehicle {
            // 80 m at low speed, up to 120 m at 30 m/s and more.
            let velocity: Vector4 = vehicle.GetLinearVelocity();
            let speed: Float = SqrtF(velocity.X * velocity.X + velocity.Y * velocity.Y);
            minDistance = WendellStripesSpawnSearch.VehicleMin() + ClampF(speed - 10.0, 0.0, 20.0) * 2.0;
            maxDistance = WendellStripesSpawnSearch.VehicleMax();
            travel = vehicle.GetWorldForward();
        }

        let cs: ref<CameraSystem> = GameInstance.GetCameraSystem(game);
        let cam: Transform;
        cs.GetActiveCameraWorldTransform(cam);
        let eye: Vector4 = Transform.GetPosition(cam);
        let look: Vector4 = cs.GetActiveCameraForward();
        let viewCos: Float = CosF(Deg2Rad(WendellStripesSpawnSearch.ViewHalfAngle()));

        // All active crowd pedestrians up to the maximum distance.
        let query: TargetSearchQuery = TSQ_NPC();
        query.maxDistance = maxDistance + WendellStripesSpawnSearch.NeighborRadius();
        query.filterObjectByDistance = true;
        query.testedSet = TargetingSet.Complete;
        query.includeSecondaryTargets = false;
        let parts: array<TS_TargetPartInfo>;
        GameInstance.GetTargetingSystem(game).GetTargetParts(player, query, parts);

        let crowd: array<ref<ScriptedPuppet>>;
        let done: array<Uint64>;
        for part in parts {
            let npc: ref<ScriptedPuppet> = TS_TargetPartInfo.GetComponent(part).GetEntity() as ScriptedPuppet;
            if IsDefined(npc) {
                let id: Uint64 = Cast<Uint64>(EntityID.GetHash(npc.GetEntityID()));
                if !ArrayContains(done, id) {
                    ArrayPush(done, id);
                    if npc.IsCrowd() && npc.IsActive() {
                        ArrayPush(crowd, npc);
                        let far: Float = Vector4.Distance(origin, npc.GetWorldPosition());
                        if far > result.crowdFarthest {
                            result.crowdFarthest = far;
                        }
                    }
                }
            }
        }
        result.crowdTotal = ArraySize(crowd);

        let spatial = GameInstance.GetSpatialQueriesSystem(game);
        let candidates: array<ref<ScriptedPuppet>>;
        let candidateNear: array<Int32>;
        let candidateDistance: array<Float>;
        for npc in crowd {
            let pos: Vector4 = npc.GetWorldPosition();
            let to: Vector4 = pos - origin;
            let dist: Float = SqrtF(to.X * to.X + to.Y * to.Y);
            let ok: Bool = dist >= minDistance && dist <= maxDistance;
            if ok && inVehicle {
                // Ahead of the vehicle, along its direction of travel.
                let tl: Float = SqrtF(travel.X * travel.X + travel.Y * travel.Y);
                ok = tl > 0.0 && (travel.X * to.X + travel.Y * to.Y) / (tl * dist) >= 0.7;
            }
            if !ok {
                result.rejectedRange += 1;
            }

            if ok && !inVehicle {
                // Outside the view cone, or behind static cover.
                let fromEye: Vector4 = pos - eye;
                let el: Float = SqrtF(fromEye.X * fromEye.X + fromEye.Y * fromEye.Y);
                let ll: Float = SqrtF(look.X * look.X + look.Y * look.Y);
                let inCone: Bool = el > 0.0 && ll > 0.0 && (look.X * fromEye.X + look.Y * fromEye.Y) / (ll * el) >= viewCos;
                if inCone {
                    let head: Vector4 = pos;
                    head.Z += 1.6;
                    let hit: TraceResult;
                    let covered: Bool = spatial.SyncRaycastByCollisionGroup(eye, head, n"Static", hit, true, false);
                    if !covered {
                        ok = false;
                        result.rejectedView += 1;
                    }
                }
            }

            if ok {
                let near: Int32 = 0;
                for other in crowd {
                    if Vector4.Distance(pos, other.GetWorldPosition()) <= WendellStripesSpawnSearch.NeighborRadius() {
                        near += 1;
                    }
                }
                if near < WendellStripesSpawnSearch.NeighborMinimum() {
                    result.rejectedNeighbors += 1;
                } else {
                    result.candidates += 1;
                    ArrayPush(candidates, npc);
                    ArrayPush(candidateNear, near);
                    ArrayPush(candidateDistance, dist);
                }
            }
        }

        // The point with the most NPCs near it first. On foot he must be able to walk to V on the pavement:
        // no spawn on the other side of a road, a wall or a fence. Not more than 8 path tests.
        let tries: Int32 = 0;
        while tries < 8 && ArraySize(candidates) > 0 {
            let pick: Int32 = 0;
            let i: Int32 = 1;
            while i < ArraySize(candidateNear) {
                if candidateNear[i] > candidateNear[pick] {
                    pick = i;
                }
                i += 1;
            }
            let fwd: Vector4 = candidates[pick].GetWorldForward();
            let at: Vector4 = candidates[pick].GetWorldPosition();
            let back: Float = WendellStripesSpawnSearch.BehindDistance();
            let position: Vector4 = new Vector4(at.X - fwd.X * back, at.Y - fwd.Y * back, at.Z, 1.0);
            if inVehicle || WendellStripesSpawnSearch.PathOk(game, position, origin) {
                result.found = true;
                result.position = position;
                result.orientation = candidates[pick].GetWorldOrientation();
                result.forward = fwd;
                result.neighbors = candidateNear[pick];
                result.distance = candidateDistance[pick];
                return result;
            }
            result.rejectedPath += 1;
            ArrayErase(candidates, pick);
            ArrayErase(candidateNear, pick);
            ArrayErase(candidateDistance, pick);
            tries += 1;
        }
        return result;
    }
}
