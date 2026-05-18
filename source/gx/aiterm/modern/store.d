/*
 * Persistent data for Aiterm (bash snippets, AI prompts/chats, SSH hosts).
 * Ported from Win Tileterm JSON layout; stored under ~/.config/aiterm/modern.json
 */
module gx.aiterm.modern.store;

import std.algorithm;
import std.conv;
import std.exception;
import std.file;
import std.json;
import std.path;
import std.string;
import std.uuid;

import gx.aiterm.modern.agentprompts;
import gx.aiterm.modern.aiproviders;

struct ModernCommand {
    string id;
    string label;
    string text;
}

struct ModernCategory {
    string id;
    string name;
    ModernCommand[] commands;
    ModernCategory[] children;
    /** SSH quick-bar tree: hosts in this category (see sshSnippets). */
    ModernSshHost[] sshHosts;
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

struct ModernAiServer {
    string id;
    string label;
    string provider;
    string baseUrl;
    string defaultModel;
}

struct ModernAiSettings {
    string provider = "lmstudio";
    string baseUrl = "";
    string model = "";
    string apiKey = "";
    bool persistHistory = true;
    bool agentExec = false;
    string activeAiServerId = "";
    string agentPromptTier = "medium";
    bool agentPromptLocked = true;
    string agentPromptCustom = "";
}

/** Which quick-bar buttons are shown on the terminal panel. */
struct ModernQuickBarUi {
    bool showSsh = false;
    bool showBashCheat = false;
    bool showPrompts = false;
    bool showAgent = false;
    bool showAiChat = false;
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
    ModernCategory[] bashSnippets;
    ModernPromptData aiPrompts;
    ModernAiChatsStore aiChats;
    ModernCategory[] sshSnippets;
    /** Legacy flat list; migrated into sshSnippets on load. */
    ModernSshHost[] sshHosts;
    ModernAiServer[] aiServers;
    string[string] agentPromptOverrides;
    ModernAiSettings ai;
    ModernQuickBarUi quickBar;
}

private ModernStore _data;
private bool _loaded;

/** Bump when on-disk layout or defaults change (triggers one-time migration). */
private enum MODERN_CONFIG_VERSION = 4;

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
    return buildPath(expandTilde("~/.config/aiterm"), "modern.json");
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

bool modernCategoryHasContent(ModernCategory c) {
    if (c.commands.length > 0) return true;
    if (c.sshHosts.length > 0) return true;
    foreach (ch; c.children)
        if (modernCategoryHasContent(ch)) return true;
    return false;
}

int modernCountCategories(ModernCategory[] cats) {
    int n;
    void walk(ModernCategory c) {
        n++;
        foreach (ch; c.children) walk(ch);
    }
    foreach (c; cats) walk(c);
    return n;
}

int modernCountCommands(ModernCategory[] cats) {
    int n;
    void walk(ModernCategory c) {
        n += cast(int)c.commands.length;
        foreach (ch; c.children) walk(ch);
    }
    foreach (c; cats) walk(c);
    return n;
}

int modernCountSshHosts(ModernCategory[] cats) {
    int n;
    void walk(ModernCategory c) {
        n += cast(int)c.sshHosts.length;
        foreach (ch; c.children) walk(ch);
    }
    foreach (c; cats) walk(c);
    return n;
}

ModernSshHost* findSshHostById(string id) {
    return findSshHostInTree(modernData().sshSnippets, id);
}

ModernSshHost* findSshHostInTree(ref ModernCategory[] cats, string id) {
    if (id.length == 0) return null;
    foreach (ref c; cats) {
        foreach (ref h; c.sshHosts)
            if (h.id == id) return &h;
        auto p = findSshHostInTree(c.children, id);
        if (p !is null) return p;
    }
    return null;
}

private void migrateFlatSshHosts(ref ModernStore d) {
    if (d.sshSnippets.length > 0 || d.sshHosts.length == 0) return;
    ModernCategory servers;
    servers.id = genId();
    servers.name = "Servers";
    servers.sshHosts = d.sshHosts;
    d.sshSnippets = [servers];
    d.sshHosts = [];
}

private ModernSshHost parseSshHostNode(JSONValue h) {
    ModernSshHost host;
    if (h.type != JSONType.object) return host;
    host.id = ("id" in h) ? h["id"].str : genId();
    host.label = ("label" in h) ? h["label"].str : "";
    host.host = ("host" in h) ? h["host"].str : "";
    host.user = ("user" in h) ? h["user"].str : "";
    host.port = cast(int)(("port" in h) ? h["port"].integer : 22);
    host.identityFile = ("identityFile" in h) ? h["identityFile"].str : "";
    host.useAgent = ("useAgent" in h) ? h["useAgent"].boolean : false;
    host.keyOnly = ("keyOnly" in h) ? h["keyOnly"].boolean : false;
    host.extraArgs = ("extraArgs" in h) ? h["extraArgs"].str : "";
    return host;
}

private ModernCategory parseCategoryNode(JSONValue cat) {
    ModernCategory c;
    if (cat.type != JSONType.object) return c;
    c.id = ("id" in cat) ? cat["id"].str : genId();
    c.name = ("name" in cat) ? cat["name"].str : "";
    if ("commands" in cat) {
        foreach (cmd; cat["commands"].array) {
            auto parsed = parseCommand(cmd);
            if (parsed.text.length > 0) c.commands ~= parsed;
        }
    }
    if ("children" in cat && cat["children"].type == JSONType.array) {
        foreach (ch; cat["children"].array)
            c.children ~= parseCategoryNode(ch);
    }
    if ("sshHosts" in cat && cat["sshHosts"].type == JSONType.array) {
        foreach (h; cat["sshHosts"].array) {
            auto host = parseSshHostNode(h);
            if (host.host.length > 0) c.sshHosts ~= host;
        }
    }
    return c;
}

private ModernCategory[] parseCategories(JSONValue root) {
    ModernCategory[] cats;
    if (root.type != JSONType.object || !("categories" in root)) return cats;
    foreach (cat; root["categories"].array)
        cats ~= parseCategoryNode(cat);
    return cats;
}

private JSONValue serializeCategoryNode(ModernCategory c) {
    JSONValue[] cmds;
    foreach (cmd; c.commands) {
        cmds ~= JSONValue([
            "id": JSONValue(cmd.id),
            "label": JSONValue(cmd.label),
            "text": JSONValue(cmd.text),
        ]);
    }
    JSONValue[] childArr;
    foreach (ch; c.children)
        childArr ~= serializeCategoryNode(ch);
    JSONValue[] hostArr;
    foreach (h; c.sshHosts) {
        hostArr ~= JSONValue([
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
    JSONValue node = [
        "id": JSONValue(c.id),
        "name": JSONValue(c.name),
        "commands": JSONValue(cmds),
    ];
    if (childArr.length > 0)
        node["children"] = JSONValue(childArr);
    if (hostArr.length > 0)
        node["sshHosts"] = JSONValue(hostArr);
    return JSONValue(node);
}

private JSONValue serializeCategories(ModernCategory[] cats) {
    JSONValue[] arr;
    foreach (c; cats)
        arr ~= serializeCategoryNode(c);
    return JSONValue(["categories": JSONValue(arr)]);
}

private ModernCategory makeSubcategory(string name, ModernCommand[] commands) {
    ModernCategory c;
    c.id = genId();
    c.name = name;
    c.commands = commands;
    return c;
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
    ModernCategory apps;
    apps.id = genId();
    apps.name = "Apps";
    apps.children = [
        makeSubcategory("Docker", [
            makeCommand("ps", "docker ps\n"),
            makeCommand("ps -a", "docker ps -a\n"),
            makeCommand("images", "docker images\n"),
            makeCommand("compose ps", "docker compose ps\n"),
            makeCommand("compose up", "docker compose up -d\n"),
        ]),
        makeSubcategory("Ollama", [
            makeCommand("list", "ollama list\n"),
            makeCommand("ps", "ollama ps\n"),
            makeCommand("run", "ollama run \n"),
            makeCommand("pull", "ollama pull \n"),
        ]),
        makeSubcategory("Git", [
            makeCommand("status", "git status\n"),
            makeCommand("pull", "git pull\n"),
            makeCommand("log", "git log --oneline -15\n"),
            makeCommand("diff", "git diff\n"),
        ]),
        makeSubcategory("systemd", [
            makeCommand("failed", "systemctl --failed\n"),
            makeCommand("journal", "journalctl -xe --no-pager | tail -50\n"),
        ]),
        makeSubcategory("Python", [
            makeCommand("version", "python3 --version\n"),
            makeCommand("pip list", "pip list\n"),
            makeCommand("venv", "python3 -m venv .venv\n"),
        ]),
        makeSubcategory("Terraform", [
            makeCommand("version", "terraform version\n"),
            makeCommand("init", "terraform init\n"),
            makeCommand("plan", "terraform plan\n"),
            makeCommand("apply", "terraform apply\n"),
        ]),
        makeSubcategory("gcloud", [
            makeCommand("version", "gcloud --version\n"),
            makeCommand("auth list", "gcloud auth list\n"),
            makeCommand("config", "gcloud config list\n"),
            makeCommand("projects", "gcloud projects list\n"),
            makeCommand("instances", "gcloud compute instances list\n"),
        ]),
    ];
    return [net, files, sys, apps];
}

void restoreDefaultBashSnippets() {
    modernData().bashSnippets = defaultBashSnippets();
    saveModernStore();
    notifyModernDataChanged();
}

ModernCategory[] defaultAiPrompts() {
    ModernCategory srv;
    srv.id = genId();
    srv.name = "Server administration";
    srv.commands = [
        makeCommand("Service failed",
            "A Linux service failed to start. Ask me for the service name and logs, then suggest "
            ~ "diagnostic commands (systemctl, journalctl) and likely fixes:\n"),
        makeCommand("Disk space",
            "The server is low on disk space. Suggest commands to find large files and directories "
            ~ "(df, du, ncdu), safe cleanup steps, and what to avoid deleting:\n"),
        makeCommand("High CPU / memory",
            "The server has high CPU or memory usage. Suggest commands to identify top processes "
            ~ "(top, ps, htop-style) and next troubleshooting steps:\n"),
        makeCommand("Package upgrade",
            "I need to upgrade packages safely on this server. Outline pre-checks, upgrade commands "
            ~ "for Debian/Ubuntu or RHEL-style systems, and rollback considerations:\n"),
        makeCommand("User & permissions",
            "Help with Linux users, groups, and file permissions. I will paste the situation; "
            ~ "suggest chmod/chown/usermod commands and explain the security impact:\n"),
        makeCommand("Cron / timers",
            "Help debug a cron job or systemd timer that does not run as expected. "
            ~ "Suggest how to verify schedule, environment, and logs:\n"),
    ];

    ModernCategory net;
    net.id = genId();
    net.name = "Network administration";
    net.commands = [
        makeCommand("No connectivity",
            "This host cannot reach the network or internet. Suggest a step-by-step check "
            ~ "(ip link, ip addr, route, ping, DNS, firewall) with specific commands:\n"),
        makeCommand("DNS issues",
            "DNS resolution is failing or slow. Suggest diagnostics using dig, nslookup, "
            ~ "resolvectl/systemd-resolved, and /etc/resolv.conf checks:\n"),
        makeCommand("Open ports",
            "I need to verify which ports are listening and whether a port is reachable. "
            ~ "Suggest ss/netstat, nc, and curl/telnet checks:\n"),
        makeCommand("Firewall rules",
            "Help review or draft firewall rules (iptables/nftables/ufw). I will describe the "
            ~ "traffic I need; explain commands and a minimal safe ruleset:\n"),
        makeCommand("Routing",
            "Routing on this Linux host seems wrong. Suggest ip route, traceroute, and "
            ~ "how to interpret the output; ask for my ip route output if needed:\n"),
        makeCommand("SSH access",
            "SSH login or key authentication fails. Suggest server-side checks "
            ~ "(sshd config, permissions, logs, firewall) and client-side tests:\n"),
    ];

    ModernCategory test;
    test.id = genId();
    test.name = "Testing & diagnostics";
    test.commands = [
        makeCommand("Ping / reachability",
            "I want to test reachability to a host or IP. Suggest ping, mtr, and arp "
            ~ "commands with useful flags; I will provide the target:\n"),
        makeCommand("HTTP / API check",
            "I need to test an HTTP or HTTPS endpoint. Suggest curl commands (headers, status, "
            ~ "timing, TLS) and how to interpret common failures:\n"),
        makeCommand("Port scan (local)",
            "Suggest safe commands to test TCP/UDP ports on a given host from this machine "
            ~ "(nc, nmap with conservative options). Remind about authorized use only:\n"),
        makeCommand("Bandwidth / latency",
            "Suggest ways to measure network latency and basic throughput from Linux "
            ~ "(ping stats, iperf3 if available, curl download timing):\n"),
        makeCommand("SSL / TLS",
            "I need to check a TLS certificate or HTTPS setup. Suggest openssl s_client, "
            ~ "curl -v, and what to look for in the output:\n"),
        makeCommand("Log a test run",
            "I will paste command output from a test. Summarize pass/fail, anomalies, "
            ~ "and recommended follow-up commands:\n"),
    ];

    ModernCategory general;
    general.id = genId();
    general.name = "General";
    general.commands = [
        makeCommand("Explain command",
            "Explain what this shell command does and whether it is safe to run:\n"),
        makeCommand("One-liner",
            "Turn my goal into a single safe bash one-liner. Ask for details if needed:\n"),
    ];

    return [srv, net, test, general];
}

void restoreDefaultAiPrompts() {
    modernData().aiPrompts.categories = defaultAiPrompts();
    saveModernStore();
    notifyModernDataChanged();
}

void restoreDefaultSshSnippets() {
    modernData().sshSnippets = [];
    modernData().sshHosts = [];
    saveModernStore();
    notifyModernDataChanged();
}

/** Fresh install defaults: built-in templates, no user data, quick bar buttons off. */
ModernStore factoryModernStore() {
    ModernStore d = ModernStore.init;
    d.bashSnippets = defaultBashSnippets();
    d.aiPrompts.categories = defaultAiPrompts();
    d.sshSnippets = [];
    d.sshHosts = [];
    d.aiServers = [];
    d.agentPromptOverrides = null;
    d.ai = ModernAiSettings.init;
    d.ai.persistHistory = false;
    d.ai.agentExec = false;
    d.ai.apiKey = "";
    d.ai.baseUrl = "";
    d.ai.model = "";
    d.ai.activeAiServerId = "";
    d.quickBar = ModernQuickBarUi.init;
    ModernAiChat chat;
    chat.id = genId();
    chat.title = "";
    chat.updatedAt = 0;
    chat.turns = [];
    d.aiChats.chats = [chat];
    d.aiChats.activeChatId = chat.id;
    return d;
}

void resetModernStoreToFactory() {
    _data = factoryModernStore();
    _loaded = true;
    saveModernStore();
    notifyModernDataChanged();
}

void ensureDefaults(ref ModernStore d) {
    if (d.bashSnippets.length == 0) d.bashSnippets = defaultBashSnippets();
    if (d.aiPrompts.categories.length == 0)
        d.aiPrompts.categories = defaultAiPrompts();
    if (d.aiChats.chats.length == 0) {
        ModernAiChat chat;
        chat.id = genId();
        chat.title = "";
        chat.updatedAt = 0;
        chat.turns = [];
        d.aiChats.chats = [chat];
        d.aiChats.activeChatId = chat.id;
    }
    if (d.ai.agentPromptTier.length == 0)
        d.ai.agentPromptTier = AGENT_TIER_MEDIUM;
}

void loadModernStore() {
    _loaded = true;
    _data = ModernStore.init;
    string path = modernConfigPath();
    bool migrated;
    if (!exists(path)) {
        _data = factoryModernStore();
        saveModernStore();
        return;
    }
    try {
        auto root = parseJSON(readText(path));
        if (root.type != JSONType.object) {
            _data = factoryModernStore();
            saveModernStore();
            return;
        }
        int configVersion = 0;
        if ("configVersion" in root) configVersion = cast(int)root["configVersion"].integer;
        bool legacyQuickBar = configVersion < 1;
        bool migrateAgentTiers = configVersion < 2;
        string legacyAgentPromptId;
        bool loadedAgentTier;
        if ("bashSnippets" in root) _data.bashSnippets = parseCategories(root["bashSnippets"]);
        if ("aiPrompts" in root) _data.aiPrompts.categories = parseCategories(root["aiPrompts"]);
        if ("sshSnippets" in root)
            _data.sshSnippets = parseCategories(root["sshSnippets"]);
        if ("sshHosts" in root && root["sshHosts"].type == JSONType.array) {
            foreach (h; root["sshHosts"].array) {
                auto host = parseSshHostNode(h);
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
            if ("activeAiServerId" in a) _data.ai.activeAiServerId = a["activeAiServerId"].str;
            if ("agentPromptTier" in a) {
                _data.ai.agentPromptTier = normalizeAgentPromptTier(a["agentPromptTier"].str);
                loadedAgentTier = true;
            }
            if ("agentPromptLocked" in a)
                _data.ai.agentPromptLocked = a["agentPromptLocked"].boolean;
            if ("agentPromptCustom" in a)
                _data.ai.agentPromptCustom = a["agentPromptCustom"].str;
            if ("activeAgentPromptId" in a)
                legacyAgentPromptId = a["activeAgentPromptId"].str;
            _data.ai.provider = normalizeProviderId(_data.ai.provider);
        }
        if ("agentPromptOverrides" in root && root["agentPromptOverrides"].type == JSONType.object) {
            foreach (k, v; root["agentPromptOverrides"].object) {
                if (v.type == JSONType.string)
                    _data.agentPromptOverrides[k] = v.str;
            }
        }
        if ("agentPrompts" in root && root["agentPrompts"].type == JSONType.array) {
            foreach (p; root["agentPrompts"].array) {
                if (p.type != JSONType.object) continue;
                string pid = ("id" in p) ? p["id"].str : "";
                string ptext = ("text" in p) ? p["text"].str : "";
                if (ptext.length == 0) continue;
                string tier = tierFromLegacyPromptId(pid);
                if (ptext != defaultAgentPromptForTier(tier))
                    _data.agentPromptOverrides[tier] = ptext;
            }
        }
        if ("aiServers" in root && root["aiServers"].type == JSONType.array) {
            foreach (s; root["aiServers"].array) {
                if (s.type != JSONType.object) continue;
                ModernAiServer srv;
                srv.id = ("id" in s) ? s["id"].str : genId();
                srv.label = ("label" in s) ? s["label"].str : "";
                srv.provider = normalizeProviderId(("provider" in s) ? s["provider"].str : "lmstudio");
                srv.baseUrl = ("baseUrl" in s) ? s["baseUrl"].str : "";
                srv.defaultModel = ("defaultModel" in s) ? s["defaultModel"].str : "";
                if (srv.baseUrl.length > 0)
                    _data.aiServers ~= srv;
            }
        }
        if (!legacyQuickBar && "quickBar" in root && root["quickBar"].type == JSONType.object) {
            auto qb = root["quickBar"];
            if ("showSsh" in qb) _data.quickBar.showSsh = qb["showSsh"].boolean;
            if ("showBashCheat" in qb) _data.quickBar.showBashCheat = qb["showBashCheat"].boolean;
            if ("showPrompts" in qb) _data.quickBar.showPrompts = qb["showPrompts"].boolean;
            if ("showAgent" in qb) _data.quickBar.showAgent = qb["showAgent"].boolean;
            if ("showAiChat" in qb) _data.quickBar.showAiChat = qb["showAiChat"].boolean;
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
        if (configVersion < 4) {
            migrateFlatSshHosts(_data);
            migrated = true;
        }
        if (legacyQuickBar) {
            _data.quickBar = ModernQuickBarUi.init;
            migrated = true;
        }
        if (migrateAgentTiers && !loadedAgentTier) {
            _data.ai.agentPromptTier = tierFromLegacyPromptId(legacyAgentPromptId);
            migrated = true;
        }
    } catch (Exception e) {
        _data = factoryModernStore();
        saveModernStore();
        return;
    }
    if (migrated) saveModernStore();
}

void saveModernStore() {
    if (!_loaded) loadModernStore();
    string dir = dirName(modernConfigPath());
    if (!exists(dir)) mkdirRecurse(dir);
    JSONValue root = parseJSON("{}");
    root["bashSnippets"] = serializeCategories(_data.bashSnippets);
    root["aiPrompts"] = serializeCategories(_data.aiPrompts.categories);
    root["sshSnippets"] = serializeCategories(_data.sshSnippets);
    JSONValue[] aiSrv;
    foreach (s; _data.aiServers) {
        aiSrv ~= JSONValue([
            "id": JSONValue(s.id),
            "label": JSONValue(s.label),
            "provider": JSONValue(s.provider),
            "baseUrl": JSONValue(s.baseUrl),
            "defaultModel": JSONValue(s.defaultModel),
        ]);
    }
    root["aiServers"] = JSONValue(aiSrv);
    JSONValue[string] promptOv;
    foreach (k, v; _data.agentPromptOverrides)
        promptOv[k] = JSONValue(v);
    root["agentPromptOverrides"] = JSONValue(promptOv);
    root["ai"] = JSONValue([
        "provider": JSONValue(_data.ai.provider),
        "baseUrl": JSONValue(_data.ai.baseUrl),
        "model": JSONValue(_data.ai.model),
        "apiKey": JSONValue(_data.ai.apiKey),
        "persistHistory": JSONValue(_data.ai.persistHistory),
        "agentExec": JSONValue(_data.ai.agentExec),
        "activeAiServerId": JSONValue(_data.ai.activeAiServerId),
        "agentPromptTier": JSONValue(_data.ai.agentPromptTier),
        "agentPromptLocked": JSONValue(_data.ai.agentPromptLocked),
        "agentPromptCustom": JSONValue(_data.ai.agentPromptCustom),
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
    root["configVersion"] = JSONValue(MODERN_CONFIG_VERSION);
    root["quickBar"] = JSONValue([
        "showSsh": JSONValue(_data.quickBar.showSsh),
        "showBashCheat": JSONValue(_data.quickBar.showBashCheat),
        "showPrompts": JSONValue(_data.quickBar.showPrompts),
        "showAgent": JSONValue(_data.quickBar.showAgent),
        "showAiChat": JSONValue(_data.quickBar.showAiChat),
    ]);
    write(modernConfigPath(), root.toPrettyString());
}

/** True if at least one quick-bar control should be visible. */
bool modernQuickBarHasItems() {
    auto qb = modernData().quickBar;
    if (qb.showSsh) return true;
    if (qb.showBashCheat) return true;
    if (qb.showPrompts) return true;
    if (qb.showAgent) return true;
    if (qb.showAiChat) return true;
    return false;
}

ref ModernStore modernData() {
    if (!_loaded) loadModernStore();
    return _data;
}

ModernAiServer* findAiServerById(string id) {
    if (id.length == 0) return null;
    foreach (ref s; modernData().aiServers) {
        if (s.id == id) return &s;
    }
    return null;
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
