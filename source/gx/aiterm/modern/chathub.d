/*
 * AI chat history manager (Preferences → AI, same data as AI Chat window).
 */
module gx.aiterm.modern.chathub;

import std.algorithm;
import std.datetime;
import std.string;

import gtk.Box;
import gtk.Button;
import gtk.Dialog;
import gtk.Entry;
import gtk.Label;
import gtk.ListBox;
import gtk.ListBoxRow;
import gtk.ScrolledWindow;
import gtk.Widget;
import gtk.Window;
import gtk.c.types;

import gx.gtk.util;
import gx.aiterm.modern.aichat;
import gx.aiterm.modern.store;

alias VoidFn = void delegate();

void showAiChatsHubDialog(Window parent, VoidFn onChanged) {
    auto dlg = new Dialog();
    dlg.setTitle("AI chats");
    if (parent !is null) dlg.setTransientFor(parent);
    dlg.setModal(true);
    dlg.setDefaultSize(560, 440);
    auto content = dlg.getContentArea();
    content.setOrientation(Orientation.VERTICAL);
    content.setSpacing(8);
    content.setMarginStart(12);
    content.setMarginEnd(12);
    content.setMarginTop(12);
    content.setMarginBottom(12);

    auto hint = new Label("Same chats as in the AI Chat window. Open switches the active chat.");
    hint.setLineWrap(true);
    content.packStart(hint, false, false, 0);

    auto scroll = new ScrolledWindow();
    scroll.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
    scroll.setMinContentHeight(260);
    auto list = new ListBox();
    list.setSelectionMode(SelectionMode.SINGLE);
    scroll.add(list);
    content.packStart(scroll, true, true, 0);

    void refreshList() {
        ensureAiChatsCoherent();
        foreach (w; getChildren!Widget(list, false)) w.destroy();
        ModernAiChat[] sorted = modernData().aiChats.chats.dup;
        sorted.sort!((a, b) => b.updatedAt < a.updatedAt);
        string activeId = modernData().aiChats.activeChatId;
        foreach (chat; sorted) {
            auto row = new ListBoxRow();
            row.setName(chat.id);
            auto rowBox = new Box(Orientation.HORIZONTAL, 8);
            auto main = new Box(Orientation.VERTICAL, 2);
            string prefix = chat.id == activeId ? "● " : "";
            auto titleLbl = new Label(prefix ~ displayChatTitle(chat));
            titleLbl.setXalign(0);
            main.packStart(titleLbl, false, false, 0);
            if (chat.updatedAt > 0) {
                auto dt = SysTime.fromUnixTime(chat.updatedAt).toLocalTime();
                auto meta = new Label(dt.toSimpleString());
                meta.setXalign(0);
                meta.getStyleContext().addClass("dim-label");
                main.packStart(meta, false, false, 0);
            }
            rowBox.packStart(main, true, true, 0);
            auto actions = new Box(Orientation.HORIZONTAL, 4);
            auto btnOpen = new Button("Open");
            auto btnRen = new Button("Rename");
            auto btnDel = new Button("Delete");
            string chatId = chat.id;
            btnOpen.addOnClicked(delegate(Button) {
                setActiveAiChatId(chatId);
                if (parent !is null) {
                    showAiChatDialog(parent);
                    reloadAiChatFromStore();
                }
                notifyModernDataChanged();
                refreshList();
                if (onChanged !is null) onChanged();
            });
            btnRen.addOnClicked(delegate(Button) {
                auto ed = new Dialog();
                ed.setTitle("Rename chat");
                ed.setTransientFor(dlg);
                ed.setModal(true);
                auto e = new Entry();
                e.setText(chat.title);
                e.setPlaceholderText("Chat title");
                auto box = new Box(Orientation.VERTICAL, 8);
                box.setMarginStart(12);
                box.setMarginEnd(12);
                box.setMarginTop(12);
                box.setMarginBottom(12);
                box.packStart(e, false, false, 0);
                ed.getContentArea().packStart(box, true, true, 0);
                ed.addButton("Cancel", ResponseType.CANCEL);
                ed.addButton("Save", ResponseType.OK);
                ed.showAll();
                if (ed.run() != ResponseType.OK) { ed.destroy(); return; }
                foreach (ref c; modernData().aiChats.chats) {
                    if (c.id == chatId) {
                        c.title = e.getText().strip();
                        break;
                    }
                }
                saveModernStore();
                notifyModernDataChanged();
                refreshList();
                if (onChanged !is null) onChanged();
                ed.destroy();
            });
            btnDel.addOnClicked(delegate(Button) {
                auto conf = new Dialog();
                conf.setTitle("Delete chat");
                conf.setTransientFor(dlg);
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
                bool wasActive = chatId == modernData().aiChats.activeChatId;
                ModernAiChat[] kept;
                foreach (c; modernData().aiChats.chats) if (c.id != chatId) kept ~= c;
                modernData().aiChats.chats = kept;
                if (modernData().aiChats.chats.length == 0) {
                    auto nc = createBlankAiChat();
                    modernData().aiChats.chats = [nc];
                    modernData().aiChats.activeChatId = nc.id;
                } else if (wasActive) {
                    modernData().aiChats.activeChatId = modernData().aiChats.chats[0].id;
                }
                saveModernStore();
                notifyModernDataChanged();
                refreshList();
                if (onChanged !is null) onChanged();
            });
            actions.packStart(btnOpen, false, false, 0);
            actions.packStart(btnRen, false, false, 0);
            actions.packStart(btnDel, false, false, 0);
            rowBox.packStart(actions, false, false, 0);
            row.add(rowBox);
            list.add(row);
        }
        list.showAll();
    }

    auto rowBtns = new Box(Orientation.HORIZONTAL, 6);
    auto btnNew = new Button("New chat");
    auto btnClear = new Button("Delete all");
    rowBtns.packStart(btnNew, false, false, 0);
    rowBtns.packStart(btnClear, false, false, 0);
    content.packStart(rowBtns, false, false, 0);

    btnNew.addOnClicked(delegate(Button) {
        startNewAiChat(parent, false);
        refreshList();
        if (onChanged !is null) onChanged();
    });
    btnClear.addOnClicked(delegate(Button) {
        auto conf = new Dialog();
        conf.setTitle("Delete all chats");
        conf.setTransientFor(dlg);
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
        notifyModernDataChanged();
        refreshList();
        if (onChanged !is null) onChanged();
    });

    dlg.addButton("Close", ResponseType.CLOSE);
    refreshList();
    dlg.showAll();
    dlg.run();
    dlg.destroy();
}
