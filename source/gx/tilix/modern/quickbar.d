/*
 * Modern Tilix toolbar: GTK dropdown menus (category → items) for quick data.
 * Manage lists in Preferences → Modern.
 */
module gx.tilix.modern.quickbar;

import std.algorithm;
import std.conv;
import std.format;

import gio.Menu : GMenu = Menu;
import gio.SimpleAction;
import gio.SimpleActionGroup;

import gtk.Box;
import gtk.Button;
import gtk.Label;
import gtk.MenuButton;
import gtk.Popover;
import gtk.Separator;
import gtk.ToggleButton;
import gtk.Widget;
import gtk.Window;
import gtk.c.types;

import gx.gtk.util;
import gx.tilix.modern.aichat;
import gx.tilix.modern.store;

alias TerminalFeedFn = void delegate(string text);

private enum ModernMenuAction { FEED, PROMPT, SSH }

class ModernQuickBar : Box {

private:
    TerminalFeedFn _feed;
    ToggleButton _btnAgent;
    SimpleActionGroup _actions;
    int _actionSeq;
    ModernCommand[] _pickFeed;
    ModernCommand[] _pickPrompt;
    ModernSshHost[] _pickSsh;

public:
    this(TerminalFeedFn feed) {
        super(Orientation.HORIZONTAL, 6);
        _feed = feed;
        getStyleContext().addClass("tilix-modern-quickbar");
        setMarginStart(6);
        setMarginEnd(6);
        setMarginTop(4);
        setMarginBottom(4);
        rebuild();
    }

    void rebuild() {
        foreach (w; gx.gtk.util.getChildren!Widget(this, false)) w.destroy();
        resetActions();
        auto d = modernData();
        _pickFeed = [];
        _pickPrompt = [];
        _pickSsh = [];

        auto lbl = new Label("Quick:");
        lbl.setMarginEnd(4);
        packStart(lbl, false, false, 0);

        if (hasAnyCommands(d.quick.categories))
            packStart(createMenuButton("Commands", buildCategoryRootMenu(d.quick.categories, ModernMenuAction.FEED)), false, false, 0);

        packStart(createMenuButton("SSH", buildSshMenu()), false, false, 0);

        if (hasAnyCommands(d.aiPrompts.categories))
            packStart(createMenuButton("Prompts", buildCategoryRootMenu(d.aiPrompts.categories, ModernMenuAction.PROMPT)), false, false, 0);

        packStart(new Separator(Orientation.VERTICAL), false, false, 0);

        _btnAgent = new ToggleButton("⚡ Agent");
        _btnAgent.setTooltipText("Run AI ```bash``` blocks in the active terminal");
        _btnAgent.setActive(d.ai.agentExec);
        _btnAgent.addOnToggled(delegate(ToggleButton b) {
            modernData().ai.agentExec = b.getActive();
            saveModernStore();
        });
        packStart(_btnAgent, false, false, 0);

        auto btnAi = new Button("AI Chat");
        btnAi.setTooltipText("Open AI chat window");
        btnAi.addOnClicked(delegate(Button) {
            auto win = cast(Window)getToplevel();
            if (win !is null) {
                showAiChatDialog(win);
                reloadAiChatFromStore();
            }
        });
        packStart(btnAi, false, false, 0);

        showAll();
    }

private:
    void resetActions() {
        _actions = new SimpleActionGroup();
        _actionSeq = 0;
        auto noop = new SimpleAction("noop", null);
        noop.addOnActivate(delegate(GVariant, SimpleAction) { });
        _actions.addAction(noop);
    }

    string bindMenuAction(ModernMenuAction kind, uint idx) {
        string name = format("m%d", _actionSeq++);
        auto action = new SimpleAction(name, null);
        ModernMenuAction k = kind;
        uint i = idx;
        action.addOnActivate(delegate(GVariant, SimpleAction) { onMenuPick(k, i); });
        _actions.addAction(action);
        return "modern." ~ name;
    }

    void onMenuPick(ModernMenuAction kind, uint idx) {
        switch (kind) {
        case ModernMenuAction.FEED:
            if (_feed !is null && idx < _pickFeed.length) {
                string t = _pickFeed[idx].text;
                if (t.length > 0) _feed(t);
            }
            break;
        case ModernMenuAction.PROMPT:
            if (idx < _pickPrompt.length) {
                auto win = cast(Window)getToplevel();
                if (win !is null) showAiChatDialog(win, _pickPrompt[idx].text);
            }
            break;
        case ModernMenuAction.SSH:
            if (_feed !is null && idx < _pickSsh.length)
                _feed(buildSshCommand(_pickSsh[idx]));
            break;
        default:
            break;
        }
    }

    MenuButton createMenuButton(string title, GMenu model) {
        auto mb = new MenuButton();
        mb.setLabel(title);
        mb.setUsePopover(true);
        mb.insertActionGroup("modern", _actions);
        mb.setPopover(new Popover(mb, model));
        return mb;
    }

    bool hasAnyCommands(ModernCategory[] cats) {
        foreach (c; cats) if (c.commands.length > 0) return true;
        return false;
    }

    GMenu buildCategoryRootMenu(ModernCategory[] categories, ModernMenuAction kind) {
        auto root = new GMenu();
        foreach (cat; categories) {
            if (cat.commands.length == 0) continue;
            auto sub = new GMenu();
            foreach (cmd; cat.commands) {
                string lab = cmd.label.length > 0 ? cmd.label : cmd.text;
                uint idx = registerPick(kind, cmd);
                sub.append(lab, bindMenuAction(kind, idx));
            }
            root.appendSubmenu(cat.name, sub);
        }
        return root;
    }

    uint registerPick(ModernMenuAction kind, ModernCommand cmd) {
        switch (kind) {
        case ModernMenuAction.FEED:
            _pickFeed ~= cmd;
            return cast(uint)(_pickFeed.length - 1);
        case ModernMenuAction.PROMPT:
            _pickPrompt ~= cmd;
            return cast(uint)(_pickPrompt.length - 1);
        default:
            return 0;
        }
    }

    GMenu buildSshMenu() {
        auto root = new GMenu();
        foreach (h; modernData().sshHosts) {
            string lab = h.label.length > 0 ? h.label : h.host;
            _pickSsh ~= h;
            uint idx = cast(uint)(_pickSsh.length - 1);
            root.append(lab, bindMenuAction(ModernMenuAction.SSH, idx));
        }
        if (modernData().sshHosts.length == 0)
            root.append("(no servers — Preferences → Modern)", "modern.noop");
        return root;
    }

}
