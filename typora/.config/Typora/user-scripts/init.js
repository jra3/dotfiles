// Entry point for user scripts. typora-inject-user-scripts adds a tag for this
// one file to Typora's window.html; everything else loads from here, so adding
// a script means editing this list, not re-patching a root-owned file.

(() => {
    // Shared logger: Typora's console is only reachable with debugging on, so
    // scripts also append to ~/.config/Typora/user-scripts.log.
    const fs = window.reqnode && window.reqnode("fs");
    const logFile = window.reqnode &&
        window.reqnode("path").join(window.reqnode("os").homedir(), ".config", "Typora", "user-scripts.log");
    window.userScriptLog = (...args) => {
        const line = `${new Date().toISOString()} ${args.join(" ")}`;
        console.log(line);
        try { fs && fs.appendFileSync(logFile, line + "\n"); } catch (e) {}
    };
    window.addEventListener("error", (e) => {
        if (/user-scripts/.test(e.filename || "")) window.userScriptLog(`error: ${e.message} at ${e.filename}:${e.lineno}`);
    });

    const SCRIPTS = [
        "frontmatter-highlight.js",
        "theme-live-reload.js",
    ];
    for (const name of SCRIPTS) {
        const s = document.createElement("script");
        s.src = `typora://app/userData/user-scripts/${name}`;
        s.onload = () => window.userScriptLog(`loaded ${name}`);
        s.onerror = () => window.userScriptLog(`failed to load ${name}`);
        document.head.appendChild(s);
    }
})();
