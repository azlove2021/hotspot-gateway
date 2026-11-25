package com.dsh.gateway;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import java.io.File;
import java.io.FileOutputStream;

/**
 * 前台服务：锁屏/后台时继续写心跳文件，防止守护进程误判 App 已关闭而清空规则。
 * 用户主动划掉 App 时服务一并结束，心跳停止 → 90 秒后自动恢复默认网络。
 */
public class HeartbeatService extends Service {

    private static final String CH = "gw_heartbeat";
    private static final int NOTI_ID = 1001;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private File hb;
    private volatile boolean running = false;

    @Override
    public void onCreate() {
        super.onCreate();
        hb = new File(getFilesDir(), "heartbeat");

        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm != null) {
            NotificationChannel ch = new NotificationChannel(CH, "网关运行状态", NotificationManager.IMPORTANCE_MIN);
            ch.setShowBadge(false);
            nm.createNotificationChannel(ch);
        }
        Notification n = new Notification.Builder(this, CH)
                .setContentTitle("热点网关运行中")
                .setContentText("关闭 App 后 90 秒自动恢复默认网络")
                .setSmallIcon(android.R.drawable.stat_sys_upload_done)
                .setOngoing(true)
                .build();
        startForeground(NOTI_ID, n);

        running = true;
        ui.post(beat);
    }

    private final Runnable beat = new Runnable() {
        @Override
        public void run() {
            if (!running) return;
            try (FileOutputStream o = new FileOutputStream(hb)) {
                o.write(String.valueOf(System.currentTimeMillis()).getBytes());
            } catch (Exception ignored) {
            }
            ui.postDelayed(this, 3000);
        }
    };

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        running = false;
        ui.removeCallbacks(beat);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
