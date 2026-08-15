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
        registerPlugin(NativeSystemBarsPlugin.class);
        super.onCreate(savedInstanceState);

        configureStatusBar();
    }

    @SuppressWarnings("deprecation")
    private void configureStatusBar() {
        int brandColor = Color.rgb(111, 57, 53);
        View decorView = getWindow().getDecorView();
        View webView = getBridge().getWebView();
        int initialPaddingLeft = webView.getPaddingLeft();
        int initialPaddingRight = webView.getPaddingRight();
        int initialPaddingBottom = webView.getPaddingBottom();

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            getWindow().setStatusBarColor(brandColor);
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
            webView.setBackgroundColor(brandColor);
            ViewCompat.setOnApplyWindowInsetsListener(decorView, (view, windowInsets) -> {
                Insets statusBar = windowInsets.getInsets(
                        WindowInsetsCompat.Type.statusBars()
                                | WindowInsetsCompat.Type.displayCutout()
                );
                webView.setPadding(
                        initialPaddingLeft,
                        statusBar.top,
                        initialPaddingRight,
                        initialPaddingBottom
                );
                return windowInsets;
            });
            ViewCompat.requestApplyInsets(decorView);
        }

        WindowCompat.getInsetsController(getWindow(), decorView)
                .setAppearanceLightStatusBars(false);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        setIntent(intent);
        super.onNewIntent(intent);
    }
}
