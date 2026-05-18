/*
 * Bash / shell command snippets for the quick panel «Commands» menu.
 * Supports nested categories (e.g. Apps → Docker → commands).
 */
module gx.aiterm.modern.bashhub;

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
import gx.aiterm.modern.store;

alias VoidFn = void delegate();

private ref ModernCategory[] bashCategories() {
    return modernData().bashSnippets;
}

private ModernCategory* findBashCategoryIn(ref ModernCategory[] cats, string id) {
    foreach (ref c; cats) {
        if (c.id == id) return &c;
        auto p = findBashCategoryIn(c.children, id);
        if (p !is null) return p;
    }
    return null;
}

private ModernCategory* findBashCategory(string id) {
    return findBashCategoryIn(bashCategories(), id);
}

private ModernCommand* findBashCommand(ModernCategory cat, string cmdId) {
    foreach (ref cmd; cat.commands) {
        if (cmd.id == cmdId) return &cmd;
    }
    return null;
}

private bool removeBashCategoryById(ref ModernCategory[] cats, string id) {
    ModernCategory[] kept;
    bool removed;
    foreach (ref c; cats) {
        if (c.id == id) {
            removed = true;
            continue;
        }
        if (removeBashCategoryById(c.children, id))
            removed = true;
        kept ~= c;
    }
    cats = kept;
    return removed;
}

private void removeBashCommandById(string cmdId) {
    void strip(ref ModernCategory c) {
        ModernCommand[] kept;
        foreach (x; c.commands) if (x.id != cmdId) kept ~= x;
        c.commands = kept;
        foreach (ref ch; c.children) strip(ch);
    }
    foreach (ref c; bashCategories()) strip(c);
}

private void fillCategoryCombo(ComboBoxText cb) {
    cb.removeAll();
    foreach (ref c; bashCategories()) {
        if (c.children.length == 0)
            cb.append(c.id, c.name);
        foreach (ref ch; c.children)
            cb.append(ch.id, c.name ~ " / " ~ ch.name);
    }
}

void showBashCommandsHubDialog(Window parent, VoidFn onChanged) {
    ensureDefaults(modernData());
    auto dlg = new Dialog();
    dlg.setTitle("Bash commands");
    if (parent !is null) dlg.setTransientFor(parent);
    dlg.setModal(true);
    dlg.setDefaultSize(560, 480);
    auto content = dlg.getContentArea();
    content.setOrientation(Orientation.VERTICAL);
    content.setSpacing(8);
    content.setMarginStart(12);
    content.setMarginEnd(12);
    content.setMarginTop(12);
    content.setMarginBottom(12);

    auto hint = new Label(
        "Categories and commands for the quick bar «Commands» menu. "
        ~ "Top-level categories may contain subcategories (e.g. Apps → Docker). "
        ~ "Selecting a command runs it in the active terminal.");
    hint.setLineWrap(true);
    hint.setXalign(0);
    content.packStart(hint, false, false, 0);

    auto scroll = new ScrolledWindow();
    scroll.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
    scroll.setMinContentHeight(260);
    auto list = new ListBox();
    list.setSelectionMode(SelectionMode.SINGLE);
    scroll.add(list);
    content.packStart(scroll, true, true, 0);

    void addCategoryRows(ModernCategory cat, string indent, string rowPrefix) {
        auto catRow = new ListBoxRow();
        catRow.setName(rowPrefix ~ cat.id);
        auto catLbl = new Label(indent ~ "▸ " ~ cat.name);
        catLbl.setXalign(0);
        catRow.add(catLbl);
        list.add(catRow);
        foreach (cmd; cat.commands) {
            string lab = cmd.label.length > 0 ? cmd.label : cmd.text;
            auto cmdRow = new ListBoxRow();
            cmdRow.setName("cmd:" ~ cat.id ~ ":" ~ cmd.id);
            auto cmdLbl = new Label(indent ~ "   • " ~ lab);
            cmdLbl.setXalign(0);
            cmdRow.add(cmdLbl);
            list.add(cmdRow);
        }
        foreach (ch; cat.children) {
            addCategoryRows(ch, indent ~ "  ", "sub:");
        }
    }

    void refreshList() {
        foreach (w; getChildren!Widget(list, false)) w.destroy();
        foreach (cat; bashCategories())
            addCategoryRows(cat, "", "cat:");
        list.showAll();
    }

    void editCategory(string catId, string parentId = "") {
        ModernCategory c;
        bool isNew = catId.length == 0;
        if (!isNew) {
            auto p = findBashCategory(catId);
            if (p is null) return;
            c = *p;
        } else {
            c.id = genId();
        }
        auto ed = new Dialog();
        ed.setTitle(isNew ? (parentId.length > 0 ? "New subcategory" : "New category")
                         : "Edit category");
        ed.setTransientFor(dlg);
        ed.setModal(true);
        auto eName = new Entry();
        eName.setText(c.name);
        eName.setPlaceholderText(parentId.length > 0 ? "e.g. Docker, Git" : "e.g. Network, Apps");
        auto box = new Box(Orientation.VERTICAL, 8);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);
        if (parentId.length > 0) {
            auto pp = findBashCategory(parentId);
            string parentName = pp !is null ? pp.name : "";
            auto lblParent = new Label("Parent: " ~ parentName);
            lblParent.setXalign(0);
            box.packStart(lblParent, false, false, 0);
        }
        box.packStart(new Label("Category name"), false, false, 0);
        box.packStart(eName, false, false, 0);
        ed.getContentArea().packStart(box, true, true, 0);
        ed.addButton("Cancel", ResponseType.CANCEL);
        ed.addButton("Save", ResponseType.OK);
        ed.showAll();
        if (ed.run() != ResponseType.OK) {
            ed.destroy();
            return;
        }
        c.name = eName.getText().strip();
        if (isNew) {
            if (parentId.length > 0) {
                auto pp = findBashCategory(parentId);
                if (pp !is null) pp.children ~= c;
            } else {
                bashCategories() ~= c;
            }
        } else {
            auto p = findBashCategory(catId);
            if (p !is null) p.name = c.name;
        }
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
        ed.destroy();
    }

    void editCommand(string catId, string cmdId) {
        auto cp = findBashCategory(catId);
        if (cp is null && catId.length > 0) return;
        ModernCommand cmd;
        bool isNew = cmdId.length == 0;
        if (!isNew && cp !is null) {
            auto p = findBashCommand(*cp, cmdId);
            if (p is null) return;
            cmd = *p;
        } else {
            cmd.id = genId();
        }
        auto ed = new Dialog();
        ed.setTitle(isNew ? "New command" : "Edit command");
        ed.setTransientFor(dlg);
        ed.setModal(true);
        auto cbCat = new ComboBoxText();
        fillCategoryCombo(cbCat);
        if (catId.length > 0) cbCat.setActiveId(catId);
        auto eLabel = new Entry();
        eLabel.setText(cmd.label);
        eLabel.setPlaceholderText("Short name in menus");
        auto tv = new TextView();
        tv.setWrapMode(WrapMode.WORD);
        tv.setMonospace(true);
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
        box.packStart(new Label("Command (sent to terminal)"), false, false, 0);
        box.packStart(tv, true, true, 0);
        ed.getContentArea().packStart(box, true, true, 0);
        ed.addButton("Cancel", ResponseType.CANCEL);
        ed.addButton("Save", ResponseType.OK);
        ed.showAll();
        if (ed.run() != ResponseType.OK) {
            ed.destroy();
            return;
        }
        string targetCatId = cbCat.getActiveId();
        if (targetCatId.length == 0) {
            ed.destroy();
            return;
        }
        cmd.label = eLabel.getText().strip();
        TextIter s, e;
        tv.getBuffer().getBounds(s, e);
        cmd.text = tv.getBuffer().getText(s, e, true);
        removeBashCommandById(cmd.id);
        auto tp = findBashCategory(targetCatId);
        if (tp !is null) tp.commands ~= cmd;
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
        ed.destroy();
    }

    auto rowBtns = new Box(Orientation.HORIZONTAL, 6);
    auto btnAddCat = new Button("Add category");
    auto btnAddSub = new Button("Add subcategory");
    auto btnAddCmd = new Button("Add command");
    auto btnEdit = new Button("Edit");
    auto btnDel = new Button("Delete");
    rowBtns.packStart(btnAddCat, false, false, 0);
    rowBtns.packStart(btnAddSub, false, false, 0);
    rowBtns.packStart(btnAddCmd, false, false, 0);
    rowBtns.packStart(btnEdit, false, false, 0);
    rowBtns.packStart(btnDel, false, false, 0);
    content.packStart(rowBtns, false, false, 0);

    btnAddCat.addOnClicked(delegate(Button) { editCategory("", ""); });
    btnAddSub.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        string parentId = "";
        if (r !is null && r.getName().startsWith("cat:"))
            parentId = r.getName()[4 .. $];
        else if (bashCategories().length > 0)
            parentId = bashCategories()[0].id;
        editCategory("", parentId);
    });
    btnAddCmd.addOnClicked(delegate(Button) {
        string catId = "";
        auto r = list.getSelectedRow();
        if (r !is null) {
            string name = r.getName();
            if (name.startsWith("cmd:")) {
                auto parts = name[4 .. $].split(":");
                if (parts.length >= 1) catId = parts[0];
            } else if (name.startsWith("sub:"))
                catId = name[4 .. $];
            else if (name.startsWith("cat:"))
                catId = name[4 .. $];
        }
        if (catId.length == 0) {
            foreach (ref c; bashCategories()) {
                if (c.children.length > 0) {
                    catId = c.children[0].id;
                    break;
                }
                catId = c.id;
                break;
            }
        }
        editCommand(catId, "");
    });
    btnEdit.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        string name = r.getName();
        if (name.startsWith("cat:")) editCategory(name[4 .. $], "");
        else if (name.startsWith("sub:")) editCategory(name[4 .. $], "");
        else if (name.startsWith("cmd:")) {
            auto parts = name[4 .. $].split(":");
            if (parts.length >= 2) editCommand(parts[0], parts[1]);
        }
    });
    btnDel.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        string name = r.getName();
        if (name.startsWith("cat:") || name.startsWith("sub:")) {
            string id = name[4 .. $];
            removeBashCategoryById(bashCategories(), id);
        } else if (name.startsWith("cmd:")) {
            auto parts = name[4 .. $].split(":");
            if (parts.length >= 2) {
                auto cp = findBashCategory(parts[0]);
                if (cp !is null) {
                    ModernCommand[] kept;
                    foreach (x; cp.commands) if (x.id != parts[1]) kept ~= x;
                    cp.commands = kept;
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
