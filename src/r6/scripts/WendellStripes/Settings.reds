module WendellStripes

// Mod Settings menu. Read with `new WendellStripesSettings()` at each use:
// Mod Settings keeps the default values of this class equal to the menu values.
public class WendellStripesSettings {

    @runtimeProperty("ModSettings.mod", "Where's Wendell")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Mod enabled")
    @runtimeProperty("ModSettings.description", "Turns the mod on or off. Off: no rolls and no appearances.")
    public let enabled: Bool = true;

    @runtimeProperty("ModSettings.mod", "Where's Wendell")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Chance for each roll (%)")
    @runtimeProperty("ModSettings.description", "The chance that he appears at each roll. With a roll each 60 seconds, 0.5 gives an average of 3.3 hours between appearances. The real time is longer: there is no roll in combat, in quiet areas, in menus and in cutscenes.")
    @runtimeProperty("ModSettings.step", "0.1")
    @runtimeProperty("ModSettings.min", "0.1")
    @runtimeProperty("ModSettings.max", "5.0")
    public let chance: Float = 0.5;

    @runtimeProperty("ModSettings.mod", "Where's Wendell")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Roll interval (seconds)")
    @runtimeProperty("ModSettings.description", "The time between two rolls.")
    @runtimeProperty("ModSettings.step", "10")
    @runtimeProperty("ModSettings.min", "30")
    @runtimeProperty("ModSettings.max", "300")
    public let interval: Int32 = 60;

    @runtimeProperty("ModSettings.mod", "Where's Wendell")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Increasing chance")
    @runtimeProperty("ModSettings.description", "Each failed roll increases the chance by 5% of its value, to a maximum of 10 times the value. An appearance sets it back. The number of failed rolls is kept in the save.")
    public let increasingChance: Bool = false;

    @runtimeProperty("ModSettings.mod", "Where's Wendell")
    @runtimeProperty("ModSettings.category", "General")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Night only")
    @runtimeProperty("ModSettings.description", "He appears only between 20:00 and 06:00 game time.")
    public let nightOnly: Bool = false;

    @runtimeProperty("ModSettings.mod", "Where's Wendell")
    @runtimeProperty("ModSettings.category", "Debug")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Debug mode")
    @runtimeProperty("ModSettings.description", "For tests only. Each roll is a success, a quiet area does not block the roll, a message on the screen tells where he came in, and all events are written to the log.")
    public let debugMode: Bool = false;

    @runtimeProperty("ModSettings.mod", "Where's Wendell")
    @runtimeProperty("ModSettings.category", "Debug")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Forget meetings")
    @runtimeProperty("ModSettings.description", "For tests only. While this is on, the mod forgets that V met him, so each meeting is the first meeting (he has the cane and gives it) and the payback starts again. Turn it off to test the payments and for normal play.")
    public let forgetMeetings: Bool = false;
}