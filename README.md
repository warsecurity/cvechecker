# CVE Checker (LSPosed module)

Build (Termux): pkg install openjdk-17 aapt2 apksigner zipalign zip, get an android.jar (API 33+), then
    ANDROID_JAR=/path/to/android.jar ./build.sh
Install cve-checker.apk, then in LSPosed enable the module, tick System Framework and CVE Checker, reboot.

How it works
- Hook.java loads SysScanner inside system_server. An alarm wakes it every interval. It asks NVD for CVEs
  published since the last cycle and notifies for watchlist matches.
- It reads settings from the app through ConfigProvider (system uid only) and delivers alerts the same way.
  Android starts the app process on demand. If the app cannot be reached, the alert is posted by the system.
- State lives in /data/system/cvewatch_state.json. Delete it to reset.
- On ColorOS also enable Auto-start for the app, and set battery to Unrestricted.
- assets/index.html also opens in a normal browser with sample data, for UI work.
