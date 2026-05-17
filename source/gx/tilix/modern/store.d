/*
 * Persistent data for Modern Tilix (quick commands, bash snippets, AI prompts/chats, SSH hosts).
 * Ported from Win Tileterm JSON layout; stored under ~/.config/tilix/modern.json
 */
module gx.tilix.modern.store;

import std.algorithm;
import std.conv;
import std.exception;
import std.file;
import std.json;
import std.path;
import std.string;
import std.uuid;

import gx.tilix.modern.aiproviders;

struct ModernCommand {
    string id;
    string label;
    string text;
}

struct ModernCategory {
    string id;
    string name;
    ModernCommand[] commands;
}

struct ModernQuickData {
    ModernCategory[] categories;
}

struct ModernPromptData {
    ModernCategory[] categories;
}

struct ModernSshHost {
    string id;
    string label;
    string host;
    string user;
    int port = 22;
    string identityFile;
    bool useAgent;
    bool keyOnly;
    string extraArgs;
}

struct ModernAiSettings {
    string provider = "lmstudio";
    string baseUrl = "";
    string model = "";
    string apiKey = "";
    bool persistHistory = true;
    bool agentExec = false;
}

struct ModernAiChat {
    string id;
    string title;
    long updatedAt;
    JSONValue[] turns;
}

struct ModernAiChatsStore {
    string activeChatId;
    ModernAiChat[] chats;
}

struct ModernStore {
    ModernQuickData quick;
    ModernCategory[] bashSnippets;
    ModernPromptData aiPrompts;
    ModernAiChatsStore aiChats;
    ModernSshHost[] sshHosts;
    ModernAiSettings ai;
}

private ModernStore _data;
private bool _loaded;

alias ModernDataChangedFn = void delegate();
private ModernDataChangedFn[] _dataListeners;

void addModernDataListener(ModernDataChangedFn fn) {
    if (fn is null) return;
    _dataListeners ~= fn;
}

void removeModernDataListener(ModernDataChangedFn fn) {
    ModernDataChangedFn[] next;
    foreach (f; _dataListeners) if (f != fn) next ~= f;
    _dataListeners = next;
}

void notifyModernDataChanged() {
    foreach (f; _dataListeners) f();
}

string modernConfigPath() {
    return buildPath(expandTilde("~/.config/tilix"), "modern.json");
}

string genId() {
    return randomUUID().toString();
}

private ModernCommand makeCommand(string label, string text) {
    ModernCommand c;
    c.id = genId();
    c.label = label;
    c.text = text;
    return c;
}

private ModernCommand parseCommand(JSONValue v) {
    ModernCommand c;
    if (v.type != JSONType.object) return c;
    c.id = ("id" in v) ? v["id"].str : genId();
    c.label = ("label" in v) ? v["label"].str : "";
    c.text = ("text" in v) ? v["text"].str : "";
    return c;
}

private ModernCategory[] parseCategories(JSONValue root) {
    ModernCategory[] cats;
    if (root.type != JSONType.object || !("categories" in root)) return cats;
    foreach (cat; root["categories"].array) {
        if (cat.type != JSONType.object) continue;
        ModernCategory c;
        c.id = ("id" in cat) ? cat["id"].str : genId();
        c.name = ("name" in cat) ? cat["name"].str : "";
        if ("commands" in cat) {
            foreach (cmd; cat["commands"].array) {
                auto parsed = parseCommand(cmd);
                if (parsed.text.length > 0) c.commands ~= parsed;
            }
        }
        cats ~= c;
    }
    return cats;
}

private JSONValue serializeCategories(ModernCategory[] cats) {
    JSONValue[] arr;
    foreach (c; cats) {
        JSONValue[] cmds;
        foreach (cmd; c.commands) {
            cmds ~= JSONValue([
                "id": JSONValue(cmd.id),
                "label": JSONValue(cmd.label),
                "text": JSONValue(cmd.text),
            ]);
        }
        arr ~= JSONValue([
            "id": JSONValue(c.id),
            "name": JSONValue(c.name),
            "commands": JSONValue(cmds),
        ]);
    }
    return JSONValue(["categories": JSONValue(arr)]);
}

ModernCategory[] defaultBashSnippets() {
    ModernCategory net;
    net.id = genId();
    net.name = "Network";
    net.commands = [
        makeCommand("IP (summary)", "ip -br a\n"),
        makeCommand("IP (all)", "ip a\n"),
        makeCommand("Listening ports", "ss -tulpn\n"),
        makeCommand("Routes", "ip route\n"),
        makeCommand("Ping 8.8.8.8", "ping -c 4 8.8.8.8\n"),
        makeCommand("Traceroute", "traceroute 8.8.8.8\n"),
        makeCommand("DNS lookup", "dig google.com\n"),
    ];
    ModernCategory files;
    files.id = genId();
    files.name = "Files & folders";
    files.commands = [
        makeCommand("List", "ls -la\n"),
        makeCommand("Home", "cd ~\n"),
        makeCommand("Parent", "cd ..\n"),
        makeCommand("Clear", "clear\n"),
    ];
    ModernCategory sys;
    sys.id = genId();
    sys.name = "System";
    sys.commands = [
        makeCommand("Who am I", "whoami\n"),
        makeCommand("Uptime", "uptime\n"),
        makeCommand("Disk usage", "df -h\n"),
    ];
    return [net, files, sys];
}

void ensureDefaults(ref ModernStore d) {
    if (d.bashSnippets.length == 0) d.bashSnippets = defaultBashSnippets();
    if (d.aiPrompts.categories.length == 0) {
        ModernCategory c;
        c.id = genId();
        c.name = "General";
        c.commands = [makeCommand("Explain command", "Explain what this shell command does:\n")];
        d.aiPrompts.categories = [c];
    }
    if (d.aiChats.chats.length == 0) {
        ModernAiChat chat;
        chat.id = genId();
        chat.title = "";
        chat.updatedAt = 0;
        chat.turns = [];
        d.aiChats.chats = [chat];
        d.aiChats.activeChatId = chat.id;
    }
}

void loadModernStore() {
    _loaded = true;
    _data = ModernStore.init;
    string path = modernConfigPath();
    if (!exists(path)) {
        ensureDefaults(_data);
        saveModernStore();
        return;
    }
    try {
        auto root = parseJSON(readText(path));
        if (root.type != JSONType.object) {
            ensureDefaults(_data);
            return;
        }
        if ("quick" in root) _data.quick.categories = parseCategories(root["quick"]);
        if ("bashSnippets" in root) _data.bashSnippets = parseCategories(root["bashSnippets"]);
        if ("aiPrompts" in root) _data.aiPrompts.categories = parseCategories(root["aiPrompts"]);
        if ("sshHosts" in root && root["sshHosts"].type == JSONType.array) {
            foreach (h; root["sshHosts"].array) {
                if (h.type != JSONType.object) continue;
                ModernSshHost host;
                host.id = ("id" in h) ? h["id"].str : genId();
                host.label = ("label" in h) ? h["label"].str : "";
                host.host = ("host" in h) ? h["host"].str : "";
                host.user = ("user" in h) ? h["user"].str : "";
                host.port = cast(int)(("port" in h) ? h["port"].integer : 22);
                host.identityFile = ("identityFile" in h) ? h["identityFile"].str : "";
                host.useAgent = ("useAgent" in h) ? h["useAgent"].boolean : false;
                host.keyOnly = ("keyOnly" in h) ? h["keyOnly"].boolean : false;
                host.extraArgs = ("extraArgs" in h) ? h["extraArgs"].str : "";
                if (host.host.length > 0) _data.sshHosts ~= host;
            }
        }
        if ("ai" in root && root["ai"].type == JSONType.object) {
            auto a = root["ai"];
            if ("provider" in a) _data.ai.provider = a["provider"].str;
            if ("baseUrl" in a) _data.ai.baseUrl = a["baseUrl"].str;
            if ("model" in a) _data.ai.model = a["model"].str;
            if ("apiKey" in a) _data.ai.apiKey = a["apiKey"].str;
            if ("persistHistory" in a) _data.ai.persistHistory = a["persistHistory"].boolean;
            if ("agentExec" in a) _data.ai.agentExec = a["agentExec"].boolean;
            _data.ai.provider = normalizeProviderId(_data.ai.provider);
        }
        if ("aiChats" in root && root["aiChats"].type == JSONType.object) {
            auto ac = root["aiChats"];
            if ("activeChatId" in ac) _data.aiChats.activeChatId = ac["activeChatId"].str;
            if ("chats" in ac && ac["chats"].type == JSONType.array) {
                foreach (ch; ac["chats"].array) {
                    if (ch.type != JSONType.object) continue;
                    ModernAiChat chat;
                    chat.id = ("id" in ch) ? ch["id"].str : genId();
                    chat.title = ("title" in ch) ? ch["title"].str : "";
                    chat.updatedAt = ("updatedAt" in ch) ? ch["updatedAt"].integer : 0;
                    if ("turns" in ch && ch["turns"].type == JSONType.array)
                        chat.turns = ch["turns"].array;
                    _data.aiChats.chats ~= chat;
                }
            }
        }
        ensureDefaults(_data);
    } catch (Exception e) {
        ensureDefaults(_data);
    }
}

void saveModernStore() {
    if (!_loaded) loadModernStore();
    string dir = dirName(modernConfigPath());
    if (!exists(dir)) mkdirRecurse(dir);
    JSONValue root = parseJSON("{}");
    root["quick"] = serializeCategories(_data.quick.categories);
    root["bashSnippets"] = serializeCategories(_data.bashSnippets);
    root["aiPrompts"] = serializeCategories(_data.aiPrompts.categories);
    JSONValue[] hosts;
    foreach (h; _data.sshHosts) {
        hosts ~= JSONValue([
            "id": JSONValue(h.id),
            "label": JSONValue(h.label),
            "host": JSONValue(h.host),
            "user": JSONValue(h.user),
            "port": JSONValue(h.port),
            "identityFile": JSONValue(h.identityFile),
            "useAgent": JSONValue(h.useAgent),
            "keyOnly": JSONValue(h.keyOnly),
            "extraArgs": JSONValue(h.extraArgs),
        ]);
    }
    root["sshHosts"] = JSONValue(hosts);
    root["ai"] = JSONValue([
        "provider": JSONValue(_data.ai.provider),
        "baseUrl": JSONValue(_data.ai.baseUrl),
        "model": JSONValue(_data.ai.model),
        "apiKey": JSONValue(_data.ai.apiKey),
        "persistHistory": JSONValue(_data.ai.persistHistory),
        "agentExec": JSONValue(_data.ai.agentExec),
    ]);
    JSONValue[] chats;
    foreach (c; _data.aiChats.chats) {
        chats ~= JSONValue([
            "id": JSONValue(c.id),
            "title": JSONValue(c.title),
            "updatedAt": JSONValue(c.updatedAt),
            "turns": JSONValue(c.turns),
        ]);
    }
    root["aiChats"] = JSONValue([
        "activeChatId": JSONValue(_data.aiChats.activeChatId),
        "chats": JSONValue(chats),
    ]);
    write(modernConfigPath(), root.toPrettyString());
}

ref ModernStore modernData() {
    if (!_loaded) loadModernStore();
    return _data;
}

string displayChatTitle(ModernAiChat chat) {
    string s = chat.title.strip();
    if (s.length > 0) return s;
    return "Untitled chat";
}

ModernAiChat createBlankAiChat() {
    ModernAiChat c;
    c.id = genId();
    c.title = "";
    c.updatedAt = 0;
    c.turns = [];
    return c;
}

void ensureAiChatsCoherent() {
    auto st = &modernData().aiChats;
    if (st.chats.length == 0) {
        auto c = createBlankAiChat();
        st.chats = [c];
        st.activeChatId = c.id;
        return;
    }
    bool found;
    foreach (c; st.chats) if (c.id == st.activeChatId) found = true;
    if (!found) st.activeChatId = st.chats[0].id;
}

void setActiveAiChatId(string id) {
    ensureAiChatsCoherent();
    modernData().aiChats.activeChatId = id;
    saveModernStore();
}

string buildSshCommand(ModernSshHost host) {
    string[] args = ["ssh", "-t"];
    if (host.port > 0 && host.port < 65536) args ~= ["-p", to!string(host.port)];
    if (host.identityFile.length > 0) args ~= ["-i", host.identityFile];
    if (host.keyOnly) {
        args ~= ["-o", "BatchMode=yes", "-o", "PreferredAuthentications=publickey"];
    }
    if (host.extraArgs.length > 0) {
        foreach (tok; host.extraArgs.split()) {
            if (tok.length > 0) args ~= tok;
        }
    }
    string target = host.host;
    if (host.user.length > 0) target = host.user ~ "@" ~ host.host;
    args ~= target;
    string cmd = args.join(" ");
    if (!cmd.endsWith("\n")) cmd ~= "\n";
    return cmd;
}
