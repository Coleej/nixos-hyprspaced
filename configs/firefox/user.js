// DankMaterialShell / Material Fox chrome theming.
// Installed into the default Firefox profile by modules/home/dankshell.nix.
// user.js is re-read on every start, so these override prefs.js.

// Material Fox needs legacy stylesheets and context-property support.
user_pref("toolkit.legacyuserprofilecustomizations.stylesheets", true);
user_pref("svg.context-properties.content.enabled", true);

// Enables the Material 3 variable palette in theme-material-blue.css, which
// DankMaterialShell regenerates on every theme switch.
user_pref("userChrome.theme-material", true);

// Use the built-in theme that follows the system colour scheme, so Firefox
// picks up the org.gnome.desktop.interface color-scheme that DankMaterialShell
// writes and selects the matching Material Fox palette.
//
// This is load-bearing: an active WebExtension theme (the firefox-compact-*
// builtins) pins prefers-color-scheme and overrides
// widget.systemUsesDarkTheme entirely, which is what kept Firefox dark
// regardless of the desktop scheme. Switch the active theme to the default one
// in about:addons -> Themes if this ever stops taking effect.
user_pref("extensions.activeThemeID", "default-theme@mozilla.org");

// Do not restore a crash session. A stored session re-applies whichever theme
// was active when it was written, re-pinning the dark theme on every start and
// defeating the activeThemeID pref above.
user_pref("toolkit.startup.max_resumed_crashes", 0);
user_pref("browser.sessionstore.resume_from_crash", false);

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