package net.vipertec.viperchat;

import android.content.Intent;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.View;

import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(SecureStoragePlugin.class);
        registerPlugin(NativeSharePlugin.class);
        super.onCreate(savedInstanceState);

        configureStatusBar();
    }

    @SuppressWarnings("deprecation")
    private void configureStatusBar() {
        int brandColor = Color.rgb(111, 57, 53);

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            getWindow().setStatusBarColor(brandColor);
        } else {
            WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
            View webView = getBridge().getWebView();
            webView.setBackgroundColor(brandColor);
            ViewCompat.setOnApplyWindowInsetsListener(webView, (view, windowInsets) -> {
                Insets statusBar = windowInsets.getInsets(
                        WindowInsetsCompat.Type.statusBars()
                                | WindowInsetsCompat.Type.displayCutout()
                );
                view.setPadding(
                        view.getPaddingLeft(),
                        statusBar.top,
                        view.getPaddingRight(),
                        view.getPaddingBottom()
                );
                return windowInsets;
            });
            ViewCompat.requestApplyInsets(webView);
        }

        WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView())
                .setAppearanceLightStatusBars(false);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        setIntent(intent);
        super.onNewIntent(intent);
    }
}
