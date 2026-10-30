package com.cvewatch.app;

import android.content.Context;
import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;
import java.lang.reflect.Field;

/** LSPosed entry point. Two jobs: start the scanner in system_server, and tell the app the module is active. */
public class Hook implements IXposedHookLoadPackage {
    private static final String SELF = "com.cvewatch.app";

    @Override public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lp) {
        try {
            if (SELF.equals(lp.packageName)) hookSelf(lp);
            else if ("android".equals(lp.packageName)) hookSystemServer(lp);
        } catch (Throwable t) {
            XposedBridge.log("CVEChecker: " + t);
        }
    }

    private void hookSelf(XC_LoadPackage.LoadPackageParam lp) {
        XposedHelpers.findAndHookMethod(SELF + ".MainActivity", lp.classLoader, "isModuleActive", new XC_MethodHook() {
            @Override protected void beforeHookedMethod(MethodHookParam param) { param.setResult(true); }
        });
    }

    /** systemReady runs once when the system finishes booting. It has several signatures across Android versions, so hook them all. */
    private void hookSystemServer(XC_LoadPackage.LoadPackageParam lp) {
        Class<?> ams = XposedHelpers.findClass("com.android.server.am.ActivityManagerService", lp.classLoader);
        XposedBridge.hookAllMethods(ams, "systemReady", new XC_MethodHook() {
            @Override protected void afterHookedMethod(MethodHookParam param) {
                try {
                    SysScanner.start(systemContext(param.thisObject));
                } catch (Throwable t) {
                    XposedBridge.log("CVEChecker: could not start scanner: " + t);
                }
            }
        });
    }

    private static Context systemContext(Object ams) throws Exception {
        try {
            Field f = ams.getClass().getDeclaredField("mContext");
            f.setAccessible(true);
            return (Context) f.get(ams);
        } catch (Throwable t) {
            Class<?> thread = Class.forName("android.app.ActivityThread");
            Object current = thread.getMethod("currentActivityThread").invoke(null);
            return (Context) thread.getMethod("getSystemContext").invoke(current);
        }
    }
}
