package com.dsh.gateway;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStreamReader;

public class MainActivity extends Activity {

    private WebView web;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private File hbFile;
    private volatile boolean beating = false;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        hbFile = new File(getFilesDir(), "heartbeat");

        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#0d1117"));
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);
        web.setWebViewClient(new WebViewClient());
        web.addJavascriptInterface(new Bridge(), "Native");
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        setContentView(web);
        web.loadUrl("file:///android_asset/index.html");

        try {
            startForegroundService(new android.content.Intent(this, HeartbeatService.class));
        } catch (Exception ignored) {
        }
    }

    @Override
    protected void onStart() {
        super.onStart();
        startBeat();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopBeat();
        try {
            stopService(new android.content.Intent(this, HeartbeatService.class));
        } catch (Exception ignored) {
        }
    }

    private void startBeat() {
        beating = true;
        ui.removeCallbacks(beat);
        ui.post(beat);
    }

    private void stopBeat() {
        beating = false;
        ui.removeCallbacks(beat);
    }

    private final Runnable beat = new Runnable() {
        @Override
        public void run() {
            if (!beating) return;
            try (FileOutputStream out = new FileOutputStream(hbFile)) {
                out.write(String.valueOf(System.currentTimeMillis()).getBytes());
            } catch (Exception ignored) {
            }
            ui.postDelayed(this, 3000);
        }
    };

    private static final String[] SU_CANDIDATES = {
            "/system/bin/su", "/system/xbin/su", "/debug_ramdisk/su",
            "/data/adb/ksu/bin/su", "/data/adb/magisk/su", "/sbin/su", "su"
    };

    private String findSu() {
        for (String p : SU_CANDIDATES) {
            if (p.equals("su") || new File(p).exists()) return p;
        }
        return "su";
    }

    private String exec(String cmd) {
        StringBuilder sb = new StringBuilder();
        try {
            String su = findSu();
            Process p = Runtime.getRuntime().exec(new String[]{su, "-c", cmd});
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = r.readLine()) != null) sb.append(line).append('\n');
            BufferedReader e = new BufferedReader(new InputStreamReader(p.getErrorStream()));
            while ((line = e.readLine()) != null) sb.append(line).append('\n');
            p.waitFor();
        } catch (Exception ex) {
            return "ERR su=" + findSu() + " -> " + ex;
        }
        return sb.toString().trim();
    }

    public class Bridge {

        @JavascriptInterface
        public String sh(String cmd) {
            return exec(cmd);
        }

        @JavascriptInterface
        public void shAsync(final String cmd, final int id) {
            new Thread(new Runnable() {
                @Override
                public void run() {
                    final String out = exec(cmd);
                    ui.post(new Runnable() {
                        @Override
                        public void run() {
                            try {
                                String js = "window.__cb(" + id + "," + JSONObject.quote(out) + ")";
                                web.evaluateJavascript(js, null);
                            } catch (Exception ignored) {
                            }
                        }
                    });
                }
            }).start();
        }


        private long seq = 0;

        private String readFile(File f) {
            try (BufferedReader r = new BufferedReader(new java.io.FileReader(f))) {
                StringBuilder sb = new StringBuilder();
                String l;
                while ((l = r.readLine()) != null) sb.append(l).append('\n');
                return sb.toString();
            } catch (Exception e) {
                return null;
            }
        }

        private void writeFile(File f, String s) {
            try (FileOutputStream o = new FileOutputStream(f)) {
                o.write(s.getBytes());
            } catch (Exception ignored) {
            }
        }

        @JavascriptInterface
        public void cmd(final String c, final int id) {
            new Thread(new Runnable() {
                @Override
                public void run() {
                    String out = null;
                    long my = System.currentTimeMillis();
                    writeFile(new File(getFilesDir(), "cmd"), c);
                    writeFile(new File(getFilesDir(), "seq"), String.valueOf(my));
                    long t0 = System.currentTimeMillis();
                    while (System.currentTimeMillis() - t0 < 120000) {
                        String d = readFile(new File(getFilesDir(), "done"));
                        if (d != null && d.trim().equals(String.valueOf(my))) {
                            out = readFile(new File(getFilesDir(), "out"));
                            break;
                        }
                        try { Thread.sleep(150); } catch (InterruptedException ignored) {}
                    }
                    if (out == null) out = "TIMEOUT 守护进程无响应，请确认 /data/adb/gateway/daemon.sh 在运行";
                    final String r = out;
                    ui.post(new Runnable() {
                        @Override
                        public void run() {
                            try {
                                web.evaluateJavascript("window.__cb(" + id + "," + JSONObject.quote(r) + ")", null);
                            } catch (Exception ignored) {}
                        }
                    });
                }
            }).start();
        }


        @JavascriptInterface
        public String saveLocal(String name, String content) {
            try {
                File f = new File(getFilesDir(), name);
                try (FileOutputStream o = new FileOutputStream(f)) {
                    o.write(content.getBytes("UTF-8"));
                }
                return "OK " + f.getAbsolutePath();
            } catch (Exception e) {
                return "ERR " + e;
            }
        }

        @JavascriptInterface
        public String readLocal(String name) {
            String r = readFile(new File(getFilesDir(), name));
            return r == null ? "" : r;
        }

        @JavascriptInterface
        public String heartbeatFile() {
            return hbFile.getAbsolutePath();
        }

        @JavascriptInterface
        public void keepAlive(boolean on) {
            if (on) startBeat(); else stopBeat();
        }
    }
}
