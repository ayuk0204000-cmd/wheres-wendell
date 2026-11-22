module WendellStripes

// The interaction prompt. It is written to the UI interactions blackboard, the same data
// that the game uses for its own prompts, so it looks like a normal interaction.
public abstract class WendellStripesPrompt {

    public static func HubId() -> Int32 = -7741;

    // Returns false if a prompt of the game is active at this time. That prompt has priority.
    // `choices` and `actions` have the same size. `renew` writes the prompt again when ours is shown
    // with other choices.
    public static func Show(game: GameInstance, title: String, choices: array<String>, actions: array<CName>, renew: Bool) -> Bool {
        let defs = GetAllBlackboardDefs();
        let bb = GameInstance.GetBlackboardSystem(game).Get(defs.UIInteractions);
        let current: InteractionChoiceHubData = FromVariant<InteractionChoiceHubData>(bb.GetVariant(defs.UIInteractions.InteractionChoiceHub));
        if current.active && current.id != WendellStripesPrompt.HubId() {
            return false;
        }
        if current.active && current.id == WendellStripesPrompt.HubId() && !renew {
            return true;
        }

        let choiceType: ChoiceTypeWrapper;
        ChoiceTypeWrapper.SetType(choiceType, gameinteractionsChoiceType.QuestImportant);
        let list: array<InteractionChoiceData>;
        let i: Int32 = 0;
        while i < ArraySize(choices) {
            let data: InteractionChoiceData;
            data.inputAction = actions[i];
            data.isHoldAction = false;
            data.localizedName = choices[i];
            data.type = choiceType;
            ArrayPush(list, data);
            i += 1;
        }

        let hub: InteractionChoiceHubData;
        hub.id = WendellStripesPrompt.HubId();
        hub.active = true;
        hub.title = title;
        hub.flags = EVisualizerDefinitionFlags.None;
        hub.choices = list;

        let vis: VisualizersInfo;
        vis.activeVisId = hub.id;
        vis.visIds = [hub.id];

        bb.SetVariant(defs.UIInteractions.InteractionChoiceHub, ToVariant(hub), true);
        bb.SetVariant(defs.UIInteractions.VisualizersInfo, ToVariant(vis), true);
        return true;
    }

    public static func Hide(game: GameInstance) -> Void {
        let defs = GetAllBlackboardDefs();
        let bb = GameInstance.GetBlackboardSystem(game).Get(defs.UIInteractions);
        let hub: InteractionChoiceHubData = FromVariant<InteractionChoiceHubData>(bb.GetVariant(defs.UIInteractions.InteractionChoiceHub));
        if hub.id == WendellStripesPrompt.HubId() {
            hub.active = false;
            let vis: VisualizersInfo;
            bb.SetVariant(defs.UIInteractions.InteractionChoiceHub, ToVariant(hub), true);
            bb.SetVariant(defs.UIInteractions.VisualizersInfo, ToVariant(vis), true);
        }
    }
}
