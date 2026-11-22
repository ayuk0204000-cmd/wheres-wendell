module WendellStripes

// Vanish, the iconic effect of the cane: a hit has a chance to trigger Reboot Optics on the target,
// the same status effect that the quickhack applies.
public abstract class WendellStripesVanish {

    public static func Chance() -> Float = 0.10;
    public static func Effect() -> TweakDBID = t"BaseStatusEffect.QuickHackBlind";

    public static func OnNpcHit(target: ref<NPCPuppet>, evt: ref<gameHitEvent>) -> Void {
        if !IsDefined(evt) || !IsDefined(evt.attackData) {
            return;
        }
        let instigator: wref<GameObject> = evt.attackData.GetInstigator();
        let weapon: wref<WeaponObject> = evt.attackData.GetWeapon();
        if !IsDefined(instigator) || !instigator.IsPlayer() || !IsDefined(weapon) {
            return;
        }
        if NotEquals(ItemID.GetTDBID(weapon.GetItemID()), WendellStripesReward.Cane()) {
            return;
        }
        let roll: Float = RandF();
        let applied: Bool = false;
        if roll < WendellStripesVanish.Chance() {
            applied = StatusEffectHelper.ApplyStatusEffect(target, WendellStripesVanish.Effect(), instigator.GetEntityID());
        }
        if (new WendellStripesSettings()).debugMode {
            WendellStripesLog(s"vanish: cane hit, roll \(roll), effect applied: \(applied)");
        }
    }
}

@wrapMethod(NPCPuppet)
protected cb func OnHit(evt: ref<gameHitEvent>) -> Bool {
    let result: Bool = wrappedMethod(evt);
    WendellStripesVanish.OnNpcHit(this, evt);
    return result;
}
