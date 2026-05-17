/*
 * AI chat window (non-modal) — chat list, terminal interrupt, agent exec.
 */
module gx.aiterm.modern.aichat;

import std.algorithm;
import std.conv;
import std.datetime;
import std.string;
import std.json;

import gtk.Box;
import gtk.Button;
import gtk.ComboBoxText;
import gtk.Dialog;
import gtk.Entry;
import gtk.Label;
import gtk.ScrolledWindow;
import gtk.TextBuffer;
import gtk.TextIter;
import gtk.TextView;
import gtk.Widget;
import gtk.Window;
import gtk.c.types;

import gdk.Event;
import gdk.Keysyms;

import gx.aiterm.appwindow;
import gx.aiterm.common;
import gx.aiterm.modern.llm;
import gx.aiterm.modern.store;
import gx.aiterm.session;

private Window _chatWin;
private Entry _chatEntry;
private TextBuffer _chatBuf;
private ComboBoxText _chatSelector;
private Window _parentWin;
private bool _suppressChatSelect;
private ModernDataChangedFn _dataListener;

private void onExternalDataChanged() {
    refreshChatSelector();
}

private ITerminal activeTerminalFrom(Window win) {
    auto aw = cast(AppWindow)win;
    if (aw is null) return null;
    Session s = aw.getCurrentSession();
    if (s is null) return null;
    return s.getActiveTerminal();
}

private void appendLog(string line) {
    if (_chatBuf is null) return;
    TextIter end;
    _chatBuf.getEndIter(end);
    _chatBuf.insert(end, line ~ "\n");
}

void reloadAiChatFromStore() {
    if (_chatBuf is null) return;
    _chatBuf.setText("");
    ensureAiChatsCoherent();
    ModernAiChat* active;
    foreach (ref c; modernData().aiChats.chats) {
        if (c.id == modernData().aiChats.activeChatId) {
            active = &c;
            break;
        }
    }
    if (active is null) return;
    appendLog("— " ~ displayChatTitle(*active) ~ " —");
    foreach (t; active.turns) {
        if (t.type != JSONType.object) continue;
        string role = ("role" in t) ? t["role"].str : "";
        string content = ("content" in t) ? t["content"].str : "";
        if (role == "user") appendLog("You: " ~ content);
        else if (role == "assistant") appendLog("AI: " ~ content);
    }
}

private void refreshChatSelector() {
    if (_chatSelector is null) return;
    _suppressChatSelect = true;
    scope (exit) { _suppressChatSelect = false; }
    _chatSelector.removeAll();
    ensureAiChatsCoherent();
    string activeId = modernData().aiChats.activeChatId;
    ModernAiChat[] sorted = modernData().aiChats.chats.dup;
    sorted.sort!((a, b) => b.updatedAt < a.updatedAt);
    int sel = 0;
    int i = 0;
    foreach (chat; sorted) {
        _chatSelector.append(chat.id, displayChatTitle(chat));
        if (chat.id == activeId) sel = i;
        i++;
    }
    if (sorted.length > 0) _chatSelector.setActive(sel);
}

private void renameActiveChat() {
    string id = modernData().aiChats.activeChatId;
    if (id.length == 0) return;
    string currentTitle = "";
    foreach (c; modernData().aiChats.chats) {
        if (c.id == id) {
            currentTitle = c.title;
            break;
        }
    }
    auto dlg = new Dialog();
    dlg.setTitle("Rename chat");
    if (_chatWin !is null) dlg.setTransientFor(_chatWin);
    dlg.setModal(true);
    auto e = new Entry();
    e.setText(currentTitle);
    e.setPlaceholderText("Chat title (empty = auto from first message)");
    auto box = new Box(Orientation.VERTICAL, 8);
    box.setMarginStart(12);
    box.setMarginEnd(12);
    box.setMarginTop(12);
    box.setMarginBottom(12);
    box.packStart(e, false, false, 0);
    dlg.getContentArea().packStart(box, true, true, 0);
    dlg.addButton("Cancel", ResponseType.CANCEL);
    dlg.addButton("Save", ResponseType.OK);
    dlg.showAll();
    if (dlg.run() != ResponseType.OK) { dlg.destroy(); return; }
    foreach (ref c; modernData().aiChats.chats) {
        if (c.id == id) {
            c.title = e.getText().strip();
            break;
        }
    }
    saveModernStore();
    refreshChatSelector();
    reloadAiChatFromStore();
    notifyModernDataChanged();
    dlg.destroy();
}

private void deleteActiveChat() {
    string id = modernData().aiChats.activeChatId;
    if (id.length == 0) return;
    auto conf = new Dialog();
    conf.setTitle("Delete chat");
    if (_chatWin !is null) conf.setTransientFor(_chatWin);
    conf.setModal(true);
    conf.addButton("Cancel", ResponseType.CANCEL);
    conf.addButton("Delete", ResponseType.OK);
    auto lbl = new Label("Delete this chat permanently?");
    lbl.setMarginStart(12);
    lbl.setMarginEnd(12);
    lbl.setMarginTop(12);
    lbl.setMarginBottom(12);
    conf.getContentArea().packStart(lbl, false, false, 0);
    conf.showAll();
    if (conf.run() != ResponseType.OK) { conf.destroy(); return; }
    conf.destroy();
    ModernAiChat[] kept;
    foreach (c; modernData().aiChats.chats) if (c.id != id) kept ~= c;
    modernData().aiChats.chats = kept;
    if (modernData().aiChats.chats.length == 0) {
        auto nc = createBlankAiChat();
        modernData().aiChats.chats = [nc];
        modernData().aiChats.activeChatId = nc.id;
    } else {
        modernData().aiChats.activeChatId = modernData().aiChats.chats[0].id;
    }
    saveModernStore();
    refreshChatSelector();
    reloadAiChatFromStore();
    notifyModernDataChanged();
}

private void deleteAllChats() {
    auto conf = new Dialog();
    conf.setTitle("Delete all chats");
    if (_chatWin !is null) conf.setTransientFor(_chatWin);
    conf.setModal(true);
    conf.addButton("Cancel", ResponseType.CANCEL);
    conf.addButton("Delete all", ResponseType.OK);
    auto lbl = new Label("Remove all saved AI conversations?");
    lbl.setMarginStart(12);
    lbl.setMarginEnd(12);
    lbl.setMarginTop(12);
    lbl.setMarginBottom(12);
    conf.getContentArea().packStart(lbl, false, false, 0);
    conf.showAll();
    if (conf.run() != ResponseType.OK) { conf.destroy(); return; }
    conf.destroy();
    auto nc = createBlankAiChat();
    modernData().aiChats.chats = [nc];
    modernData().aiChats.activeChatId = nc.id;
    saveModernStore();
    refreshChatSelector();
    reloadAiChatFromStore();
    notifyModernDataChanged();
}

private string extractBashFence(string content) {
    import std.regex;
    auto re = regex(`(?s)` ~ "```{1,3}\\s*bash\\s*\\n(.*?)\\n```");
    auto m = matchFirst(content, re);
    if (!m.empty) return m[1].strip();
    return "";
}

void sendInterruptToActiveTerminal() {
    Window win = _parentWin !is null ? _parentWin : _chatWin;
    if (win is null) return;
    auto term = activeTerminalFrom(win);
    if (term !is null) term.sendInterrupt();
}

void startNewAiChat(Window parent, bool openWindow = true) {
    auto chat = createBlankAiChat();
    modernData().aiChats.chats ~= chat;
    modernData().aiChats.activeChatId = chat.id;
    saveModernStore();
    if (openWindow) {
        Window win = parent !is null ? parent : _parentWin;
        if (win !is null) showAiChatDialog(win);
    }
    refreshChatSelector();
    reloadAiChatFromStore();
    notifyModernDataChanged();
}

void showAiChatDialog(Window parent, string prefilled = "") {
    _parentWin = parent;
    if (_chatWin !is null) {
        _chatWin.present();
        refreshChatSelector();
        if (prefilled.length > 0 && _chatEntry !is null)
            _chatEntry.setText(prefilled);
        return;
    }

    auto win = new Window(GtkWindowType.TOPLEVEL);
    _chatWin = win;
    win.setTitle("AI Chat");
    win.setDefaultSize(680, 520);
    if (parent !is null) win.setTransientFor(parent);
    win.setDestroyWithParent(false);
    win.setTypeHint(WindowTypeHint.UTILITY);

    auto content = new Box(Orientation.VERTICAL, 8);
    content.setMarginStart(12);
    content.setMarginEnd(12);
    content.setMarginTop(12);
    content.setMarginBottom(12);
    win.add(content);

    auto chatRow = new Box(Orientation.HORIZONTAL, 6);
    chatRow.packStart(new Label("Chat:"), false, false, 0);
    _chatSelector = new ComboBoxText();
    _chatSelector.setHexpand(true);
    chatRow.packStart(_chatSelector, true, true, 0);
    auto btnNew = new Button("New");
    auto btnRen = new Button("Rename");
    auto btnDel = new Button("Delete");
    auto btnClear = new Button("Clear all");
    btnNew.setTooltipText("New empty chat");
    btnRen.setTooltipText("Rename current chat");
    btnDel.setTooltipText("Delete current chat");
    btnClear.setTooltipText("Delete all chats");
    chatRow.packStart(btnNew, false, false, 0);
    chatRow.packStart(btnRen, false, false, 0);
    chatRow.packStart(btnDel, false, false, 0);
    chatRow.packStart(btnClear, false, false, 0);
    content.packStart(chatRow, false, false, 0);

    _chatSelector.addOnChanged(delegate(ComboBoxText cb) {
        if (_suppressChatSelect) return;
        string id = cb.getActiveId();
        if (id.length == 0 || id == modernData().aiChats.activeChatId) return;
        setActiveAiChatId(id);
        reloadAiChatFromStore();
    });

    btnNew.addOnClicked(delegate(Button) { startNewAiChat(_parentWin, false); });
    btnRen.addOnClicked(delegate(Button) { renameActiveChat(); });
    btnDel.addOnClicked(delegate(Button) { deleteActiveChat(); });
    btnClear.addOnClicked(delegate(Button) { deleteAllChats(); });

    auto hint = new Label("Non-modal: focus terminal + Ctrl+C to stop commands. API: Preferences → Modern.");
    hint.setLineWrap(true);
    content.packStart(hint, false, false, 0);

    auto tv = new TextView();
    tv.setEditable(false);
    tv.setWrapMode(WrapMode.WORD);
    tv.setMonospace(true);
    _chatBuf = tv.getBuffer();
    auto scroll = new ScrolledWindow();
    scroll.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
    scroll.setMinContentHeight(280);
    scroll.add(tv);
    content.packStart(scroll, true, true, 0);

    _chatEntry = new Entry();
    _chatEntry.setPlaceholderText("Message…");
    if (prefilled.length > 0) _chatEntry.setText(prefilled);
    content.packStart(_chatEntry, false, false, 0);

    auto row = new Box(Orientation.HORIZONTAL, 6);
    auto btnStop = new Button("Stop in terminal (Ctrl+C)");
    auto btnSend = new Button("Send");
    auto btnClose = new Button("Close");
    row.packStart(btnStop, false, false, 0);
    row.packEnd(btnClose, false, false, 0);
    row.packEnd(btnSend, false, false, 0);
    content.packStart(row, false, false, 0);

    void sendMessage() {
        string line = _chatEntry.getText().strip();
        _chatEntry.setText("");
        if (line.length == 0) return;

        ModernAiChat* active;
        foreach (ref c; modernData().aiChats.chats) {
            if (c.id == modernData().aiChats.activeChatId) {
                active = &c;
                break;
            }
        }
        if (active is null && modernData().aiChats.chats.length > 0)
            active = &modernData().aiChats.chats[0];
        if (active is null) return;

        appendLog("You: " ~ line);
        active.turns ~= JSONValue(["role": JSONValue("user"), "content": JSONValue(line)]);
        JSONValue[] msgs = [JSONValue(["role": JSONValue("system"), "content": JSONValue(buildSystemPrompt())])];
        foreach (t; active.turns) msgs ~= t;

        appendLog("…");
        auto res = llmChat(msgs);
        if (!res.ok) {
            appendLog("Error: " ~ res.error);
            return;
        }
        appendLog("AI: " ~ res.content);
        active.turns ~= JSONValue(["role": JSONValue("assistant"), "content": JSONValue(res.content)]);
        active.updatedAt = Clock.currTime().toUnixTime();
        if (active.title.length == 0 && active.turns.length > 0) {
            string first = line;
            if (first.length > 48) first = first[0 .. 48] ~ "…";
            active.title = first;
        }

        if (modernData().ai.agentExec) {
            string body = extractBashFence(res.content);
            auto term = activeTerminalFrom(parent);
            if (body.length > 0 && term !is null) {
                string payload = body;
                if (!payload.endsWith("\n")) payload ~= "\n";
                term.injectCommand(payload);
                appendLog("[Ran commands in terminal — use Stop or Ctrl+C in terminal]");
            }
        }
        if (modernData().ai.persistHistory) saveModernStore();
        refreshChatSelector();
        notifyModernDataChanged();
    }

    btnSend.addOnClicked(delegate(Button) { sendMessage(); });
    btnStop.addOnClicked(delegate(Button) { sendInterruptToActiveTerminal(); });
    btnClose.addOnClicked(delegate(Button) { win.close(); });
    _chatEntry.addOnKeyPress(delegate(Event e, Widget w) {
        auto key = e.key.keyval;
        if (key == GdkKeysyms.GDK_Return || key == GdkKeysyms.GDK_KP_Enter) {
            sendMessage();
            return true;
        }
        return false;
    });

    _dataListener = delegate() { refreshChatSelector(); };
    addModernDataListener(_dataListener);

    win.addOnDelete(delegate(Event, Widget) {
        if (_dataListener !is null) {
            removeModernDataListener(_dataListener);
            _dataListener = null;
        }
        _chatWin = null;
        _chatEntry = null;
        _chatBuf = null;
        _chatSelector = null;
        return false;
    });

    refreshChatSelector();
    reloadAiChatFromStore();
    win.showAll();
}
