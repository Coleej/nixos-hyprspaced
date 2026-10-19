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

// Do NOT delete prefs.js without preserving this pref.
// Each extension's data lives in storage/default/moz-extension+++<uuid>, and
// this map is the only pointer to it. If it is lost, Firefox assigns fresh
// uuids on the next start, every storage directory is orphaned, and all your
// extensions silently lose their settings, tokens and logins while still
// reporting themselves as enabled in about:addons. It lives in user.js so that
// a prefs.js wipe or a Home Manager rebuild cannot drop it again.
user_pref("extensions.webextensions.uuids", "{\"formautofill@mozilla.org\": \"21b2467f-c5c0-4a3e-8db2-19143b851928\", \"ipp-activator@mozilla.com\": \"2334579b-a8e5-445c-92b9-6ba88e0e7ff7\", \"pictureinpicture@mozilla.org\": \"1f3061a0-5fc9-40f3-9638-36dcf6a91a82\", \"addons-search-detection@mozilla.com\": \"b66d1c62-071f-49c2-9f2c-b90ebfd43453\", \"webcompat@mozilla.org\": \"9a310967-e580-48bf-b3e8-4eafebbc122d\", \"FirefoxColor@mozilla.com\": \"14163feb-0390-48b9-b2bd-5c252a08a988\", \"addon@karakeep.app\": \"a837b415-df7a-4c1b-8a3c-c167baf10bbc\", \"default-theme@mozilla.org\": \"706ae857-ccb7-4635-abc1-b1d26d35974b\", \"enhancerforyoutube@maximerf.addons.mozilla.org\": \"3b62ce38-ce9b-41ad-bae3-27de6403d462\", \"newtab@mozilla.org\": \"5c810091-b967-4145-af95-4b8031973c1d\", \"support@opportunitycost.app\": \"f13c5825-4acd-447f-8f09-52698e70be38\", \"{446900e4-71c2-419f-a6a7-df9c091e268b}\": \"186eeb53-f7c1-4c6b-9445-579a62ab1a50\", \"{a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7}\": \"7e52f0f5-3f82-467e-84a7-21a357b380e9\", \"{cd7e22de-2e34-40f0-aeff-cec824cbccac}\": \"38e348f1-0853-4f55-8b5d-0b1e8bc7f482\", \"{d7742d87-e61d-4b78-b8a1-b469842139fa}\": \"709129f9-27b4-45ab-9852-b6f44858c60c\", \"firefox-compact-dark@mozilla.org\": \"1daf3ae7-2837-4cde-8315-cafb12ef81c1\"}");
