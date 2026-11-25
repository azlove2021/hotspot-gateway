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
        web.setWebChromeClient(new android.webkit.WebChromeClient() {
            @Override
            public boolean onConsoleMessage(android.webkit.ConsoleMessage cm) {
                android.util.Log.e("GWJS", cm.message() + " @" + cm.lineNumber() + ":" + cm.sourceId());
                return true;
            }
        });
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


        /** 本机所有 IPv4 地址（不需要 root） */
        @JavascriptInterface
        public String localIps() {
            StringBuilder sb = new StringBuilder("[");
            boolean first = true;
            try {
                java.util.Enumeration<java.net.NetworkInterface> nis =
                        java.net.NetworkInterface.getNetworkInterfaces();
                while (nis != null && nis.hasMoreElements()) {
                    java.net.NetworkInterface ni = nis.nextElement();
                    if (!ni.isUp() || ni.isLoopback()) continue;
                    for (java.net.InterfaceAddress ia : ni.getInterfaceAddresses()) {
                        java.net.InetAddress a = ia.getAddress();
                        if (a == null || a.getAddress().length != 4) continue;
                        if (!first) sb.append(",");
                        first = false;
                        sb.append("{\"n\":\"").append(ni.getName())
                          .append("\",\"ip\":\"").append(a.getHostAddress())
                          .append("\",\"prefix\":").append(ia.getNetworkPrefixLength()).append("}");
                    }
                }
            } catch (Exception ignored) {
            }
            return sb.append("]").toString();
        }

        /** TCP 端口探测（不需要 root），返回 true/false */
        @JavascriptInterface
        public boolean probe(String host, int port) {
            java.net.Socket sock = new java.net.Socket();
            try {
                sock.connect(new java.net.InetSocketAddress(host, port), 1200);
                return true;
            } catch (Exception e) {
                return false;
            } finally {
                try { sock.close(); } catch (Exception ignored) {}
            }
        }

        /** 守护进程是否活着：写探针命令，3 秒内有无回执 */
        @JavascriptInterface
        public boolean daemonAlive() {
            File seqF = new File(getFilesDir(), "seq");
            File cmdF = new File(getFilesDir(), "cmd");
            File doneF = new File(getFilesDir(), "done");
            try {
                long probe = System.currentTimeMillis();
                writeFile(cmdF, "echo __probe__");
                writeFile(seqF, String.valueOf(probe));
                long t0 = System.currentTimeMillis();
                while (System.currentTimeMillis() - t0 < 3000) {
                    String d = readFile(doneF);
                    if (d != null && d.trim().equals(String.valueOf(probe))) {
                        String out = readFile(new File(getFilesDir(), "out"));
                        return out != null && out.contains("__probe__");
                    }
                    Thread.sleep(150);
                }
            } catch (Exception ignored) {
            }
            return false;
        }


        /** 首次部署：内置种子解压 → su 复制到 /data/adb/gateway → 起守护 */
        @JavascriptInterface
        public String provision() {
            // 1) 测 root
            String id = exec("id");
            if (id == null || !id.contains("uid=0")) {
                return "NO_ROOT|" + (id == null ? "su 不可用" : id.replace("\n", " "));
            }
            // 2) 已部署？
            String chk = exec("test -f /data/adb/gateway/mihomo && echo DEPLOYED || echo MISSING");
            if (chk != null && chk.contains("DEPLOYED")) {
                startDaemon();
                return "OK|already";
            }
            // 3) 从已下载的 module.zip 解压
            File zip = new File(getFilesDir(), "module.zip");
            if (!zip.exists() || zip.length() < 1024 * 1024) {
                return "NEED_DOWNLOAD|" + zip.length();
            }
            File seedDir = new File(getFilesDir(), "seed");
            try {
                unzipFile(zip, seedDir);
            } catch (Exception e) {
                return "ERR|解压失败: " + e;
            }
            // 4) 用 su 部署
            String cmd =
                "mkdir -p /data/adb/gateway; " +
                "cp -f " + seedDir.getAbsolutePath() + "/* /data/adb/gateway/ 2>/dev/null; " +
                "chmod 755 /data/adb/gateway/mihomo /data/adb/gateway/*.sh 2>/dev/null; " +
                "[ -f /data/adb/gateway/config.yaml ] || cp -f /data/adb/gateway/config.template.yaml /data/adb/gateway/config.yaml; " +
                "chmod 600 /data/adb/gateway/config.yaml; " +
                "mkdir -p /data/adb/service.d; " +
                "cp -f " + seedDir.getAbsolutePath() + "/service_daemon.sh /data/adb/service.d/gw_daemon.sh; " +
                "chmod 755 /data/adb/service.d/gw_daemon.sh; " +
                "echo PROVISIONED";
            String out = exec(cmd);
            // 5) 起守护
            startDaemon();
            if (out != null && out.contains("PROVISIONED")) return "OK|deployed";
            return "ERR|" + (out == null ? "复制失败" : out.replace("\n", " "));
        }

        private void startDaemon() {
            exec("(setsid sh /data/adb/gateway/daemon.sh >/dev/null 2>&1 &); echo started");
        }

        private void unzipFile(File zip, File targetDir) throws Exception {
            targetDir.mkdirs();
            try (java.util.zip.ZipInputStream zis =
                     new java.util.zip.ZipInputStream(new java.io.FileInputStream(zip))) {
                java.util.zip.ZipEntry e;
                byte[] buf = new byte[65536];
                while ((e = zis.getNextEntry()) != null) {
                    if (e.isDirectory()) continue;
                    String name = e.getName();
                    if (name.startsWith("files/")) name = name.substring(6);
                    else if (!name.endsWith(".sh") && !name.endsWith(".yaml") && !name.endsWith(".dat") && !name.equals("mihomo")) continue;
                    File f = new File(targetDir, name);
                    File parent = f.getParentFile();
                    if (parent != null) parent.mkdirs();
                    try (FileOutputStream o = new FileOutputStream(f)) {
                        int n;
                        while ((n = zis.read(buf)) > 0) o.write(buf, 0, n);
                    }
                }
            }
        }

        private void unzipFromAssets(String asset, File targetDir) throws Exception {
            targetDir.mkdirs();
            try (java.util.zip.ZipInputStream zis =
                     new java.util.zip.ZipInputStream(getAssets().open(asset))) {
                java.util.zip.ZipEntry e;
                byte[] buf = new byte[65536];
                while ((e = zis.getNextEntry()) != null) {
                    if (e.isDirectory()) continue;
                    File f = new File(targetDir, e.getName());
                    File parent = f.getParentFile();
                    if (parent != null) parent.mkdirs();
                    try (FileOutputStream o = new FileOutputStream(f)) {
                        int n;
                        while ((n = zis.read(buf)) > 0) o.write(buf, 0, n);
                    }
                }
            }
        }


        /** 把内置模块包导出到 App 外部目录，供 root 管理器安装 */
        @JavascriptInterface
        public String exportModule() {
            try {
                File dir = getExternalFilesDir(null);
                if (dir == null) dir = getFilesDir();
                dir.mkdirs();
                File out = new File(dir, "hotspot-gateway-module.zip");
                try (java.io.InputStream in = getAssets().open("seed.zip");
                     FileOutputStream o = new FileOutputStream(out)) {
                    byte[] buf = new byte[65536];
                    int n;
                    while ((n = in.read(buf)) > 0) o.write(buf, 0, n);
                }
                return "OK|" + out.getAbsolutePath();
            } catch (Exception e) {
                return "ERR|" + e;
            }
        }

        /** 打开 KernelSU / Magisk 管理器 */
        @JavascriptInterface
        public String openRootManager() {
            String[] pkgs = {"me.weishu.kernelsu", "com.topjohnwu.magisk", "me.bmax.apatch", "com.rifsxd.ksunext"};
            for (String p : pkgs) {
                try {
                    android.content.Intent i = getPackageManager().getLaunchIntentForPackage(p);
                    if (i != null) { i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK); startActivity(i); return "OK|" + p; }
                } catch (Exception ignored) {}
            }
            try {
                android.content.Intent i = new android.content.Intent(android.provider.Settings.ACTION_APPLICATION_SETTINGS);
                i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
                return "OK|settings";
            } catch (Exception e) { return "ERR|" + e; }
        }


        private volatile long dlBytes = 0;
        private volatile long dlTotal = 0;
        private volatile String dlState = "idle";

        @JavascriptInterface
        public String downloadProgress() {
            return dlState + "|" + dlBytes + "|" + dlTotal;
        }

        /** 下载模块包到私有目录，url 可为多个用 | 分隔，依次尝试 */
        @JavascriptInterface
        public String downloadModule(String urls) {
            File out = new File(getFilesDir(), "module.zip");
            String[] list = urls.split("\\|");
            for (String u : list) {
                if (u.trim().isEmpty()) continue;
                java.net.HttpURLConnection c = null;
                try {
                    dlState = "downloading"; dlBytes = 0; dlTotal = 0;
                    java.net.URL url = new java.net.URL(u.trim());
                    c = (java.net.HttpURLConnection) url.openConnection();
                    c.setConnectTimeout(15000);
                    c.setReadTimeout(60000);
                    c.setInstanceFollowRedirects(true);
                    c.setRequestProperty("User-Agent", "dsh-gateway");
                    dlTotal = c.getContentLength();
                    try (java.io.InputStream in = c.getInputStream();
                         FileOutputStream o = new FileOutputStream(out)) {
                        byte[] buf = new byte[65536];
                        int n;
                        while ((n = in.read(buf)) > 0) {
                            o.write(buf, 0, n);
                            dlBytes += n;
                        }
                    }
                    if (out.length() < 1024 * 1024) throw new Exception("文件过小 " + out.length());
                    dlState = "done";
                    return "OK|" + out.length() + "|" + u;
                } catch (Exception e) {
                    dlState = "error";
                    // 继续尝试下一个源
                } finally {
                    if (c != null) try { c.disconnect(); } catch (Exception ignored) {}
                }
            }
            dlState = "failed";
            return "ERR|所有下载源都失败";
        }

        /** 异步下载，JS 轮询 downloadProgress() */
        @JavascriptInterface
        public void startDownload(final String urls) {
            new Thread(new Runnable() {
                @Override public void run() { downloadModule(urls); }
            }).start();
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
