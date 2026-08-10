package net.vipertec.viperchat;

import android.content.ClipData;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@CapacitorPlugin(name = "NativeShare")
public class NativeSharePlugin extends Plugin {
    private static final int MAX_FILES = 10;

    @PluginMethod
    public void getPendingShare(PluginCall call) {
        Intent intent = getActivity().getIntent();
        if (!isShareIntent(intent)) {
            call.resolve(new JSObject().put("available", false));
            return;
        }

        try {
            JSObject result = new JSObject();
            result.put("available", true);
            result.put("text", getTextExtra(intent, Intent.EXTRA_TEXT));
            result.put("subject", getTextExtra(intent, Intent.EXTRA_SUBJECT));
            result.put("files", copySharedFiles(intent));
            intent.setAction(Intent.ACTION_MAIN);
            intent.setClipData(null);
            intent.removeExtra(Intent.EXTRA_STREAM);
            intent.removeExtra(Intent.EXTRA_TEXT);
            intent.removeExtra(Intent.EXTRA_SUBJECT);
            call.resolve(result);
        } catch (Exception error) {
            call.reject("Não foi possível importar o conteúdo compartilhado.", error);
        }
    }

    @Override
    protected void handleOnNewIntent(Intent intent) {
        getActivity().setIntent(intent);
        if (isShareIntent(intent)) {
            notifyListeners("shareReceived", new JSObject().put("available", true), true);
        }
    }

    @PluginMethod
    public void clearFiles(PluginCall call) {
        JSArray paths = call.getArray("paths", new JSArray());
        File shareDirectory = new File(getContext().getCacheDir(), "shared");
        for (int index = 0; index < paths.length(); index += 1) {
            String path = paths.optString(index, "");
            File file = new File(path);
            try {
                if (file.getCanonicalPath().startsWith(shareDirectory.getCanonicalPath() + File.separator)) {
                    file.delete();
                }
            } catch (Exception ignored) {
                // Cache cleanup is best effort; Android also clears this directory.
            }
        }
        call.resolve();
    }

    private JSArray copySharedFiles(Intent intent) throws Exception {
        List<Uri> uris = new ArrayList<>();
        if (Intent.ACTION_SEND_MULTIPLE.equals(intent.getAction())) {
            ArrayList<Uri> streams = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);
            if (streams != null) uris.addAll(streams);
        } else {
            Uri stream = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (stream != null) uris.add(stream);
        }

        ClipData clipData = intent.getClipData();
        if (clipData != null) {
            for (int index = 0; index < clipData.getItemCount(); index += 1) {
                Uri uri = clipData.getItemAt(index).getUri();
                if (uri != null && !uris.contains(uri)) uris.add(uri);
            }
        }

        JSArray files = new JSArray();
        for (int index = 0; index < Math.min(uris.size(), MAX_FILES); index += 1) {
            files.put(copyUri(uris.get(index), intent.getType()));
        }
        return files;
    }

    private JSObject copyUri(Uri uri, String fallbackType) throws Exception {
        String displayName = queryDisplayName(uri);
        String safeName = displayName.replaceAll("[^A-Za-z0-9._-]", "_");
        if (safeName.isBlank()) safeName = "arquivo";

        File directory = new File(getContext().getCacheDir(), "shared");
        if (!directory.exists() && !directory.mkdirs()) {
            throw new IllegalStateException("Could not create share cache directory");
        }
        File destination = new File(directory, UUID.randomUUID() + "-" + safeName);
        try (InputStream input = getContext().getContentResolver().openInputStream(uri);
             FileOutputStream output = new FileOutputStream(destination)) {
            if (input == null) throw new IllegalStateException("Could not read shared URI");
            byte[] buffer = new byte[8192];
            int length;
            while ((length = input.read(buffer)) != -1) output.write(buffer, 0, length);
        }

        String mimeType = getContext().getContentResolver().getType(uri);
        return new JSObject()
            .put("name", displayName)
            .put("type", mimeType == null ? fallbackType : mimeType)
            .put("size", destination.length())
            .put("path", destination.getAbsolutePath())
            .put("uri", Uri.fromFile(destination).toString());
    }

    private String queryDisplayName(Uri uri) {
        try (Cursor cursor = getContext().getContentResolver().query(uri, null, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (column >= 0) {
                    String displayName = cursor.getString(column);
                    if (displayName != null && !displayName.isBlank()) return displayName;
                }
            }
        } catch (Exception ignored) {
            // Fall back to the URI path below.
        }
        String segment = uri.getLastPathSegment();
        return segment == null || segment.isBlank() ? "arquivo" : segment;
    }

    private boolean isShareIntent(Intent intent) {
        if (intent == null) return false;
        String action = intent.getAction();
        return Intent.ACTION_SEND.equals(action) || Intent.ACTION_SEND_MULTIPLE.equals(action);
    }

    private String getTextExtra(Intent intent, String key) {
        CharSequence value = intent.getCharSequenceExtra(key);
        return value == null ? null : value.toString();
    }
}
