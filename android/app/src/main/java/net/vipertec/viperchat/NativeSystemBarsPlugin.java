package net.vipertec.viperchat;

import android.graphics.Color;
import android.os.Build;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "NativeSystemBars")
public class NativeSystemBarsPlugin extends Plugin {
    @SuppressWarnings("deprecation")
    @PluginMethod
    public void setThemeColor(PluginCall call) {
        String value = call.getString("color", "#6F3935");
        final int color;
        try {
            color = Color.parseColor(value);
        } catch (IllegalArgumentException exception) {
            call.reject("Invalid system bar color");
            return;
        }

        getActivity().runOnUiThread(() -> {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                getActivity().getWindow().setStatusBarColor(color);
            }
            getBridge().getWebView().setBackgroundColor(color);
            call.resolve(new JSObject());
        });
    }
}
