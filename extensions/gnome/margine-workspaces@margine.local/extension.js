import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const WORKSPACE_COUNT = 10;

class Indicator extends PanelMenu.Button {
    static {
        GObject.registerClass(this);
    }

    constructor(extension) {
        super(0.0, _('Margine Workspaces'), true);

        this._extension = extension;
        this._workspaceManager = global.workspace_manager;
        this._signals = [];

        this._label = new St.Label({
            style_class: 'margine-workspaces-indicator-label',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this._label);

        this._connect(this._workspaceManager, 'active-workspace-changed',
            () => this._sync());
        this._connect(this._workspaceManager, 'notify::n-workspaces',
            () => this._sync());
        this._connect(this._workspaceManager, 'workspace-added',
            () => this._sync());
        this._connect(this._workspaceManager, 'workspace-removed',
            () => this._sync());

        this._sync();
    }

    _connect(object, signal, callback) {
        this._signals.push([object, object.connect(signal, callback)]);
    }

    _disconnectSignals() {
        for (const [object, id] of this._signals)
            object.disconnect(id);
        this._signals = [];
    }

    _sync() {
        const active = this._workspaceManager.get_active_workspace_index();
        const label = `${active + 1}`;

        this._label.set_text(label);
        this.accessible_name = _('Workspace %s').format(label);
        this._rebuildMenu(active);
    }

    _rebuildMenu(active) {
        this.menu.removeAll();

        for (let i = 0; i < WORKSPACE_COUNT; i++) {
            const item = new PopupMenu.PopupMenuItem(`${i + 1}`);
            if (i === active)
                item.setOrnament(PopupMenu.Ornament.CHECK);
            item.connect('activate', () => this._extension.jumpToWorkspace(i));
            this.menu.addMenuItem(item);
        }
    }

    destroy() {
        this._disconnectSignals();
        super.destroy();
    }
}

export default class MargineWorkspacesExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._indicator = new Indicator(this);
        this._bindings = [];

        Main.panel.addToStatusArea(
            'margine-workspaces',
            this._indicator,
            1,
            'left');

        for (let i = 1; i <= WORKSPACE_COUNT; i++) {
            this._addKeybinding(`jump-to-workspace-${i}`,
                () => this.jumpToWorkspace(i - 1));
            this._addKeybinding(`move-to-workspace-${i}`,
                () => this.moveFocusedWindowToWorkspace(i - 1));
        }
    }

    disable() {
        for (const name of this._bindings)
            Main.wm.removeKeybinding(name);
        this._bindings = [];

        this._indicator?.destroy();
        this._indicator = null;
        this._settings = null;
    }

    _addKeybinding(name, callback) {
        Main.wm.addKeybinding(
            name,
            this._settings,
            Meta.KeyBindingFlags.NONE,
            Shell.ActionMode.NORMAL,
            callback);
        this._bindings.push(name);
    }

    _ensureWorkspace(index) {
        const workspaceManager = global.workspace_manager;
        const time = global.display.get_current_time();

        while (workspaceManager.get_n_workspaces() <= index)
            workspaceManager.append_new_workspace(false, time);

        return workspaceManager.get_workspace_by_index(index);
    }

    jumpToWorkspace(index) {
        const workspace = this._ensureWorkspace(index);
        workspace?.activate(global.display.get_current_time());
    }

    moveFocusedWindowToWorkspace(index) {
        const window = global.display.focus_window;
        if (!window || window.skip_taskbar)
            return;

        const workspace = this._ensureWorkspace(index);
        if (!workspace)
            return;

        window.change_workspace_by_index(index, false);
        workspace.activate_with_focus(window, global.display.get_current_time());
    }
}
