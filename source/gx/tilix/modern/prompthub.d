/*
 * AI prompt categories / templates editor.
 */
module gx.tilix.modern.prompthub;

import std.string;

import gtk.Box;
import gtk.Button;
import gtk.ComboBoxText;
import gtk.Dialog;
import gtk.Entry;
import gtk.Label;
import gtk.ListBox;
import gtk.ListBoxRow;
import gtk.ScrolledWindow;
import gtk.TextView;
import gtk.Widget;
import gtk.Window;
import gtk.TextIter;
import gtk.c.types;

import gx.gtk.util;
import gx.tilix.modern.store;

alias VoidFn = void delegate();

private ModernCategory* findPromptCategory(string id) {
    foreach (ref c; modernData().aiPrompts.categories) {
        if (c.id == id) return &c;
    }
    return null;
}

private ModernCommand* findPromptCommand(ModernCategory cat, string cmdId) {
    foreach (ref cmd; cat.commands) {
        if (cmd.id == cmdId) return &cmd;
    }
    return null;
}

void showAiPromptHubDialog(Window parent, VoidFn onChanged) {
    auto dlg = new Dialog();
    dlg.setTitle("AI prompts");
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

    auto hint = new Label("Categories group prompt templates. Text is inserted into the AI chat input or sent as a message.");
    hint.setLineWrap(true);
    content.packStart(hint, false, false, 0);

    auto scroll = new ScrolledWindow();
    scroll.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
    scroll.setMinContentHeight(240);
    auto list = new ListBox();
    list.setSelectionMode(SelectionMode.SINGLE);
    scroll.add(list);
    content.packStart(scroll, true, true, 0);

    void refreshList() {
        foreach (w; getChildren!Widget(list, false)) w.destroy();
        foreach (cat; modernData().aiPrompts.categories) {
            auto catRow = new ListBoxRow();
            catRow.setName("cat:" ~ cat.id);
            auto catLbl = new Label("▸ " ~ cat.name);
            catLbl.setXalign(0);
            catRow.add(catLbl);
            list.add(catRow);
            foreach (cmd; cat.commands) {
                string lab = cmd.label.length > 0 ? cmd.label : cmd.text;
                auto cmdRow = new ListBoxRow();
                cmdRow.setName("cmd:" ~ cat.id ~ ":" ~ cmd.id);
                auto cmdLbl = new Label("   • " ~ lab);
                cmdLbl.setXalign(0);
                cmdRow.add(cmdLbl);
                list.add(cmdRow);
            }
        }
        list.showAll();
    }

    void editCategory(string catId) {
        ModernCategory c;
        bool isNew = catId.length == 0;
        if (!isNew) {
            auto p = findPromptCategory(catId);
            if (p is null) return;
            c = *p;
        } else {
            c.id = genId();
        }
        auto ed = new Dialog();
        ed.setTitle(isNew ? "New category" : "Edit category");
        ed.setTransientFor(dlg);
        ed.setModal(true);
        auto eName = new Entry();
        eName.setText(c.name);
        eName.setPlaceholderText("e.g. General, DevOps");
        auto box = new Box(Orientation.VERTICAL, 8);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);
        box.packStart(new Label("Category name"), false, false, 0);
        box.packStart(eName, false, false, 0);
        ed.getContentArea().packStart(box, true, true, 0);
        ed.addButton("Cancel", ResponseType.CANCEL);
        ed.addButton("Save", ResponseType.OK);
        ed.showAll();
        if (ed.run() != ResponseType.OK) { ed.destroy(); return; }
        c.name = eName.getText().strip();
        if (isNew) modernData().aiPrompts.categories ~= c;
        else {
            foreach (ref cat; modernData().aiPrompts.categories) {
                if (cat.id == catId) {
                    cat.name = c.name;
                    break;
                }
            }
        }
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
        ed.destroy();
    }

    void editCommand(string catId, string cmdId) {
        auto cp = findPromptCategory(catId);
        if (cp is null && catId.length > 0) return;
        ModernCategory cat;
        if (cp !is null) cat = *cp;
        else {
            cat.id = catId.length > 0 ? catId : genId();
            if (catId.length == 0 && modernData().aiPrompts.categories.length > 0)
                cat.id = modernData().aiPrompts.categories[0].id;
        }
        ModernCommand cmd;
        bool isNew = cmdId.length == 0;
        if (!isNew && cp !is null) {
            auto p = findPromptCommand(*cp, cmdId);
            if (p is null) return;
            cmd = *p;
        } else {
            cmd.id = genId();
        }
        auto ed = new Dialog();
        ed.setTitle(isNew ? "New prompt" : "Edit prompt");
        ed.setTransientFor(dlg);
        ed.setModal(true);
        auto cbCat = new ComboBoxText();
        int sel = 0;
        int i = 0;
        foreach (c; modernData().aiPrompts.categories) {
            cbCat.append(c.id, c.name);
            if (c.id == cat.id) sel = i;
            i++;
        }
        if (modernData().aiPrompts.categories.length > 0)
            cbCat.setActive(sel);
        auto eLabel = new Entry();
        eLabel.setText(cmd.label);
        eLabel.setPlaceholderText("Short name in menus");
        auto tv = new TextView();
        tv.setWrapMode(WrapMode.WORD);
        tv.getBuffer().setText(cmd.text);
        tv.setSizeRequest(-1, 120);
        auto box = new Box(Orientation.VERTICAL, 8);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);
        box.packStart(new Label("Category"), false, false, 0);
        box.packStart(cbCat, false, false, 0);
        box.packStart(new Label("Label"), false, false, 0);
        box.packStart(eLabel, false, false, 0);
        box.packStart(new Label("Prompt text"), false, false, 0);
        box.packStart(tv, true, true, 0);
        ed.getContentArea().packStart(box, true, true, 0);
        ed.addButton("Cancel", ResponseType.CANCEL);
        ed.addButton("Save", ResponseType.OK);
        ed.showAll();
        if (ed.run() != ResponseType.OK) { ed.destroy(); return; }
        string targetCatId = cbCat.getActiveId();
        cmd.label = eLabel.getText().strip();
        TextIter s, e;
        tv.getBuffer().getBounds(s, e);
        cmd.text = tv.getBuffer().getText(s, e, true);
        foreach (ref c; modernData().aiPrompts.categories) {
            ModernCommand[] kept;
            foreach (x; c.commands) if (x.id != cmd.id) kept ~= x;
            c.commands = kept;
        }
        foreach (ref c; modernData().aiPrompts.categories) {
            if (c.id == targetCatId) {
                c.commands ~= cmd;
                break;
            }
        }
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
        ed.destroy();
    }

    auto rowBtns = new Box(Orientation.HORIZONTAL, 6);
    auto btnAddCat = new Button("Add category");
    auto btnAddCmd = new Button("Add prompt");
    auto btnEdit = new Button("Edit");
    auto btnDel = new Button("Delete");
    rowBtns.packStart(btnAddCat, false, false, 0);
    rowBtns.packStart(btnAddCmd, false, false, 0);
    rowBtns.packStart(btnEdit, false, false, 0);
    rowBtns.packStart(btnDel, false, false, 0);
    content.packStart(rowBtns, false, false, 0);

    btnAddCat.addOnClicked(delegate(Button) { editCategory(""); });
    btnAddCmd.addOnClicked(delegate(Button) {
        if (modernData().aiPrompts.categories.length == 0) {
            editCategory("");
            return;
        }
        editCommand(modernData().aiPrompts.categories[0].id, "");
    });
    btnEdit.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        string name = r.getName();
        if (name.startsWith("cat:")) editCategory(name[4 .. $]);
        else if (name.startsWith("cmd:")) {
            auto parts = name[4 .. $].split(":");
            if (parts.length >= 2) editCommand(parts[0], parts[1]);
        }
    });
    btnDel.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        string name = r.getName();
        if (name.startsWith("cat:")) {
            string id = name[4 .. $];
            ModernCategory[] next;
            foreach (c; modernData().aiPrompts.categories) if (c.id != id) next ~= c;
            modernData().aiPrompts.categories = next;
        } else if (name.startsWith("cmd:")) {
            auto parts = name[4 .. $].split(":");
            if (parts.length >= 2) {
                foreach (ref c; modernData().aiPrompts.categories) {
                    if (c.id != parts[0]) continue;
                    ModernCommand[] kept;
                    foreach (x; c.commands) if (x.id != parts[1]) kept ~= x;
                    c.commands = kept;
                    break;
                }
            }
        } else return;
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
    });

    dlg.addButton("Close", ResponseType.CLOSE);
    refreshList();
    dlg.showAll();
    dlg.run();
    dlg.destroy();
}
