// DankMaterialShell / Material Fox chrome theming.
// Installed into the default Firefox profile by modules/home/dankshell.nix.
// user.js is re-read on every start, so these override prefs.js.

// Material Fox needs legacy stylesheets and context-property support.
user_pref("toolkit.legacyuserprofilecustomizations.stylesheets", true);
user_pref("svg.context-properties.content.enabled", true);

// Enables the Material 3 variable palette in theme-material-blue.css, which
// DankMaterialShell regenerates on every theme switch.
user_pref("userChrome.theme-material", true);

// Theme selection is deliberately NOT pinned here. The active theme is owned
// by Firefox's add-on database and its addonStartup.json.lz4 cache, not by
// the extensions.activeThemeID pref, and Firefox Sync is stopped from changing
// it by the locked services.sync.prefs.sync.extensions.activeThemeID pref in
// modules/home/packages.nix. Select "System theme -- auto" in about:addons ->
// Themes; any other theme (including a Firefox Color theme) pins
// prefers-color-scheme and ignores the desktop. See docs/dev/dms-theme-sync.md.

// NOTE: extensions.webextensions.uuids is deliberately NOT in this file.
//
// It maps each extension ID to the UUID that names its storage directory
// (storage/default/moz-extension+++<uuid>), and it is the only pointer to
// that data. Those UUIDs are per-machine and per-install: shipping x1's map
// would repoint a different machine's extensions at storage paths that do not
// exist there, silently emptying their settings, tokens and logins while
// about:addons still reports them as enabled.
//
// The activation hook instead preserves whatever map the destination profile
// already has. If it ever is lost, restoring it means pairing each extension
// ID with the UUID of an existing moz-extension+++ storage directory.
