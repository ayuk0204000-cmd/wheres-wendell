module WendellStripes

// The talk with V, the cane and the money.
public abstract class WendellStripesReward {

    public static func Cane() -> TweakDBID = t"Items.WendellStripes_Cane";
    public static func Money() -> TweakDBID = t"Items.money";

    // The payback, 100,000 in total (user decision 2026-11-21). `finds` is the number of meetings
    // before this one: the first meeting gives the cane, the next four pay 50,000, 25,000, 15,000
    // and 10,000. Returns 0 when the debt is paid.
    public static func Payment(finds: Int32) -> Int32 {
        switch finds {
            case 1: return 50000;
            case 2: return 25000;
            case 3: return 15000;
            case 4: return 10000;
        }
        return 0;
    }

    // The sum of the payments up to and with the meeting that has this `finds` value.
    public static func PaidAfter(finds: Int32) -> Int32 {
        let total: Int32 = 0;
        let i: Int32 = 1;
        while i <= finds {
            total += WendellStripesReward.Payment(i);
            i += 1;
        }
        return total;
    }

    // Lines. V speaks through the prompt; his answers are subtitles.
    public static func PromptTitle() -> String = "Wendell \"Stripes\" Strypovski";
    // First meeting.
    // He owed Jackie 100,000 for a gig and disappeared; V collects the debt. `heistDone` selects
    // the lines: before the Heist Jackie is alive, after it he is dead.
    public static func VFirst(heistDone: Bool) -> String {
        if heistDone {
            return "Wendell. You owe Jackie a hundred grand. I'm collecting.";
        }
        return "Wendell. Jackie wants his hundred grand. I'm collecting.";
    }
    public static func StripesNoMoney(heistDone: Bool) -> String {
        if heistDone {
            return "V! Hey... I heard about Jackie. Damn shame. I'm tapped out, choom. Not one eddie on me. Here, take the cane. It's worth more than what I owe.";
        }
        return "V! Hey... Tell Jackie I didn't forget. I'm tapped out, choom. Not one eddie on me. Here, take the cane. It's worth more than what I owe.";
    }
    public static func VNextTime() -> String = "Next time I see you, you better have some eddies.";
    public static func StripesNextTime(heistDone: Bool) -> String {
        if heistDone {
            return "You got it, V. Every eddie. For Jackie.";
        }
        return "You got it, V. Every eddie. Tell Jackie we're good.";
    }
    // The meetings in which he pays.
    public static func VAgain() -> String = "Pay up.";
    public static func StripesPays(finds: Int32) -> String {
        switch finds {
            case 1: return "Yeah, yeah. Had a good week. Here. That's half.";
            case 2: return "Slow week, V. Here's what I got.";
            case 3: return "Marks are getting careful. Take it.";
        }
        return "That's the last of it. We're square, V.";
    }
    // The meetings after the debt is paid: one of these lines, picked at random.
    public static func VHey() -> String = "Hey, Wendell.";
    public static func BrokeLines() -> Int32 = 4;
    public static func StripesBroke(index: Int32) -> String {
        switch index {
            case 0: return "We're square, V. Count it again if you want.";
            case 1: return "Nothing left to skim off me, choom. Go find yourself a corpo.";
            case 2: return "Still breathing, still broke. Good to see you, V.";
        }
        return "Keep walking, V. You're scaring off my marks.";
    }

    public static func Give(game: GameInstance, item: TweakDBID, amount: Int32, label: String) -> Bool {
        let player: ref<PlayerPuppet> = WendellStripesConditions.GetPlayerPuppet(game);
        let record: Bool = IsDefined(TweakDBInterface.GetItemRecord(item));
        let given: Bool = GameInstance.GetTransactionSystem(game).GiveItemByTDBID(player, item, amount);
        WendellStripesLog(s"reward: \(label) x\(amount), record found: \(record), given: \(given)");
        return given;
    }

    // Shows one subtitle line of him. Returns the line, to hide it later.
    public static func Say(game: GameInstance, speaker: wref<GameObject>, text: String, duration: Float, number: Int32) -> scnDialogLineData {
        let defs = GetAllBlackboardDefs();
        let line: scnDialogLineData;
        line.id = HashToCRUID(Cast<Uint64>(77410000 + number));
        line.text = text;
        line.type = scnDialogLineType.Regular;
        line.speaker = speaker;
        line.speakerName = "Stripes";
        line.isPersistent = false;
        line.duration = duration;
        let lines: array<scnDialogLineData> = [line];
        GameInstance.GetBlackboardSystem(game).Get(defs.UIGameData).SetVariant(defs.UIGameData.ShowDialogLine, ToVariant(lines), true);
        WendellStripesLog(s"line: \(text)");
        return line;
    }

    public static func Unsay(game: GameInstance, line: scnDialogLineData) -> Void {
        let defs = GetAllBlackboardDefs();
        let lines: array<scnDialogLineData> = [line];
        GameInstance.GetBlackboardSystem(game).Get(defs.UIGameData).SetVariant(defs.UIGameData.HideDialogLineByData, ToVariant(lines), true);
    }
}
