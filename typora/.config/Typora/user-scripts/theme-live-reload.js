// Apply edits to the current theme's CSS without restarting Typora.
//
// Typora reads theme files once, at startup or on a Themes-menu switch, and
// re-requesting the same URL is served from cache (File.setTheme was tried; it
// re-applies the stale copy). A cache-busting ?v= on the <link> would work but
// breaks export, which turns that href into a file path.
//
// So the <link>s keep their hrefs. On a change this reads the file from disk,
// puts its text in a <style> right after the matching <link>, and disables the
// <link>, so the fresh copy replaces it outright (deleted rules go away too).
// A Themes-menu switch re-enables the links and drops the <style>s.
//
// fs.watchFile polls stat() rather than using inotify: the theme is a stow
// symlink into ~/.dotfiles, stat() follows it to the real file, and polling
// survives editors that save by rename.

(() => {
    const req = window.reqnode;
    const log = (...a) => (window.userScriptLog || console.log)("theme-live-reload:", ...a);
    if (!req) return log("no reqnode; disabled");
    const fs = req("fs");
    const path = req("path");
    const themes = path.join(req("os").homedir(), ".config", "Typora", "themes");
    const themesUrl = "typora://app/userData/themes/";
    const POLL_MS = 500;

    const currentTheme = () =>
        ((window.File && File.option && File.option.curTheme) || "").replace(/\.css$/, "");

    // Each watched file, and the <link> its live <style> goes after.
    const targets = (name) => [
        { file: `${name}.css`, after: "theme_css" },
        { file: "base.user.css", after: "base_user_css" },
        { file: `${name}.user.css`, after: "theme_user_css" },
    ];

    function apply({ file, after }) {
        let css;
        try {
            css = fs.readFileSync(path.join(themes, file), "utf8");
        } catch (e) {
            return log(`cannot read ${file}: ${e.message}`);
        }
        // Relative @import and url() paths would resolve against window.html
        // here, not the themes dir; make them absolute.
        css = css
            .replace(/@import\s+(['"])(?![a-z][a-z0-9+.-]*:|\/)/gi, `@import $1${themesUrl}`)
            .replace(/url\(\s*(['"]?)(?![a-z][a-z0-9+.-]*:|\/|#)/gi, `url($1${themesUrl}`);

        const id = `live-${after}`;
        let style = document.getElementById(id);
        if (!style) {
            style = document.createElement("style");
            style.id = id;
            document.getElementById(after).after(style);
        }
        style.textContent = css;
        document.getElementById(after).disabled = true;
        // CodeMirror caches char width and line height; after a font or size
        // change its cursor lands in the wrong place until it re-measures.
        requestAnimationFrame(() => {
            document.querySelectorAll(".CodeMirror").forEach((el) => el.CodeMirror && el.CodeMirror.refresh());
        });
        log(`applied ${file}`);
    }

    let watched = [];
    function watch() {
        const name = currentTheme();
        if (name === watched.name) return;
        for (const f of watched) fs.unwatchFile(f);
        // A menu switch loads the new theme fresh; drop overrides for the old.
        document.querySelectorAll("style[id^='live-']").forEach((s) => {
            s.remove();
            const link = document.getElementById(s.id.replace(/^live-/, ""));
            if (link) link.disabled = false;
        });
        watched = [];
        watched.name = name;
        if (!name) return;
        for (const t of targets(name)) {
            const f = path.join(themes, t.file);
            watched.push(f);
            fs.watchFile(f, { interval: POLL_MS }, (cur, prev) => {
                if (cur.mtimeMs !== prev.mtimeMs && cur.mtimeMs) apply(t);
            });
        }
        log(`watching ${name}`);
    }

    // The theme can be switched from the menu at any time; follow it.
    watch();
    setInterval(watch, 2000);
})();
