module WendellStripes

@if(ModuleExists("RedLogger"))
import RedLogger.*

// ModLog (Codeware) goes to the game console only. If the RedLogger mod is installed,
// lines also go to r6/logs/mods/WendellStripes__<date>.log. RedLogger is optional.
@if(ModuleExists("RedLogger"))
public func WendellStripesLog(text: String) -> Void {
    ModLog(n"WendellStripes", text);
    RedLog.AppendLevel("WendellStripes", "INFO", text);
}

@if(!ModuleExists("RedLogger"))
public func WendellStripesLog(text: String) -> Void {
    ModLog(n"WendellStripes", text);
}
