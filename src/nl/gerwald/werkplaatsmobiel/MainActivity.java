package nl.gerwald.werkplaatsmobiel;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.view.ViewGroup;
import android.view.Window;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import java.util.ArrayList;

public class MainActivity extends Activity {

    private static final String LIVE_URL = "https://grwald.github.io/werkplaats-mobiel/";
    private static final String LOCAL_ASSET_URL = "file:///android_asset/index.html";
    private static final int REQ_RECORD_AUDIO = 1001;

    private WebView webView;
    private SpeechRecognizer speechRecognizer;
    private boolean isListening = false;
    private String pendingToken = null;
    private String pendingRepo = null;
    private String pendingClaudeKey = null;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Window w = getWindow();
        if (w != null) {
            w.setStatusBarColor(Color.parseColor("#120D0A"));
            w.setNavigationBarColor(Color.parseColor("#120D0A"));
        }

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.parseColor("#120D0A"));

        webView = new WebView(this);
        webView.setBackgroundColor(Color.parseColor("#120D0A"));
        root.addView(webView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        setContentView(root);

        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setDatabaseEnabled(true);
        ws.setAllowFileAccess(true);
        ws.setAllowFileAccessFromFileURLs(true);
        ws.setAllowUniversalAccessFromFileURLs(true);
        ws.setMediaPlaybackRequiresUserGesture(false);
        ws.setCacheMode(WebSettings.LOAD_DEFAULT);

        webView.addJavascriptInterface(new WerkplaatsBridge(), "AndroidWerkplaats");

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        request.grant(request.getResources());
                    }
                });
            }
        });

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (uri == null) return false;
                String url = uri.toString();
                if (url.startsWith("https://grwald.github.io/werkplaats-mobiel") || url.startsWith("file:///android_asset/")) {
                    return false;
                }
                openExternal(url);
                return true;
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                pushPendingAdbConfigToWeb();
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request != null && request.isForMainFrame()) {
                    view.loadUrl(LOCAL_ASSET_URL);
                }
            }
        });

        captureIntentExtras(getIntent());
        loadBestSource(false);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        boolean forceRefresh = captureIntentExtras(intent);
        if (forceRefresh) {
            loadBestSource(true);
        } else {
            pushPendingAdbConfigToWeb();
        }
    }

    private boolean captureIntentExtras(Intent intent) {
        if (intent == null) return false;
        Uri data = intent.getData();
        if (data != null && "werkplaats".equals(data.getScheme())) {
            String t = data.getQueryParameter("token");
            String r = data.getQueryParameter("repo");
            String c = data.getQueryParameter("claude");
            if (t != null && !t.isEmpty()) pendingToken = t;
            if (r != null && !r.isEmpty()) pendingRepo = r;
            if (c != null && !c.isEmpty()) pendingClaudeKey = c;
        }
        if (intent.hasExtra("token")) pendingToken = intent.getStringExtra("token");
        if (intent.hasExtra("repo")) pendingRepo = intent.getStringExtra("repo");
        if (intent.hasExtra("claude")) pendingClaudeKey = intent.getStringExtra("claude");
        return intent.getBooleanExtra("refresh", false);
    }

    private void pushPendingAdbConfigToWeb() {
        if (webView == null) return;
        if (pendingToken != null || pendingRepo != null || pendingClaudeKey != null) {
            final String js = String.format(
                    "if(window.receiveAdbConfig){window.receiveAdbConfig(%s,%s,%s);}",
                    toJsStr(pendingToken),
                    toJsStr(pendingRepo != null ? pendingRepo : "GRwald/ai-werkplaats"),
                    toJsStr(pendingClaudeKey)
            );
            pendingToken = null;
            pendingRepo = null;
            pendingClaudeKey = null;
            webView.post(new Runnable() {
                @Override
                public void run() {
                    webView.evaluateJavascript(js, null);
                }
            });
        }
    }

    private String toJsStr(String s) {
        if (s == null) return "null";
        return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'";
    }

    private boolean isOnline() {
        try {
            ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) return false;
            NetworkInfo ni = cm.getActiveNetworkInfo();
            return ni != null && ni.isConnected();
        } catch (Exception e) {
            return false;
        }
    }

    private void loadBestSource(boolean bustCache) {
        if (bustCache && isOnline()) {
            webView.clearCache(true);
            webView.loadUrl(LIVE_URL + "?v=" + System.currentTimeMillis());
        } else {
            webView.loadUrl(LOCAL_ASSET_URL);
        }
    }

    private void openExternal(String url) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Exception ignored) {
        }
    }

    private void postNativeMorningNotification(String title, String body) {
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                if (checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 1002);
                }
            }
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            String chanId = "ochtendbode_kanaal";
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel ch = new NotificationChannel(
                        chanId,
                        "Ochtendbode (Werkplaats)",
                        NotificationManager.IMPORTANCE_DEFAULT
                );
                ch.setDescription("Rustig ochtend-seintje na de ochtendloop als jij ergens aan zet bent");
                nm.createNotificationChannel(ch);
            }
            Intent tapIntent = new Intent(this, MainActivity.class);
            tapIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(
                    this, 0, tapIntent,
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT : PendingIntent.FLAG_UPDATE_CURRENT
            );
            Notification.Builder b = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ? new Notification.Builder(this, chanId)
                    : new Notification.Builder(this);
            b.setSmallIcon(R.drawable.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setStyle(new Notification.BigTextStyle().bigText(body))
                    .setContentIntent(pi)
                    .setAutoCancel(true);
            nm.notify(701, b.build());
        } catch (Exception ignored) {
        }
    }

    public class WerkplaatsBridge {

        @JavascriptInterface
        public String getDefaultToken() {
            return LocalConfig.GH_TOKEN;
        }

        @JavascriptInterface
        public void showMorningNotification(final String title, final String body) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    postNativeMorningNotification(title, body);
                }
            });
        }

        @JavascriptInterface
        public void reloadFromCloud() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    loadBestSource(true);
                }
            });
        }

        @JavascriptInterface
        public void openExternalUrl(final String url) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    openExternal(url);
                }
            });
        }

        @JavascriptInterface
        public void startSpeech() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    startNativeSpeech();
                }
            });
        }

        @JavascriptInterface
        public void stopSpeech() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    stopNativeSpeech();
                }
            });
        }
    }

    private void startNativeSpeech() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, REQ_RECORD_AUDIO);
                return;
            }
        }
        try {
            if (speechRecognizer == null) {
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this);
                speechRecognizer.setRecognitionListener(new RecognitionListener() {
                    @Override public void onReadyForSpeech(Bundle params) {}
                    @Override public void onBeginningOfSpeech() {}
                    @Override public void onRmsChanged(float rmsdB) {}
                    @Override public void onBufferReceived(byte[] buffer) {}
                    @Override public void onEndOfSpeech() {}

                    @Override
                    public void onError(int error) {
                        isListening = false;
                        sendSpeechToWeb("", true);
                    }

                    @Override
                    public void onResults(Bundle results) {
                        ArrayList<String> matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                        if (matches != null && !matches.isEmpty()) {
                            sendSpeechToWeb(matches.get(0), true);
                        }
                        if (isListening) {
                            launchRecognizerIntent();
                        }
                    }

                    @Override
                    public void onPartialResults(Bundle partialResults) {
                        ArrayList<String> matches = partialResults.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                        if (matches != null && !matches.isEmpty()) {
                            sendSpeechToWeb(matches.get(0), false);
                        }
                    }

                    @Override public void onEvent(int eventType, Bundle params) {}
                });
            }
            isListening = true;
            launchRecognizerIntent();
        } catch (Exception e) {
            isListening = false;
        }
    }

    private void launchRecognizerIntent() {
        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "nl-NL");
        intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
        speechRecognizer.startListening(intent);
    }

    private void stopNativeSpeech() {
        isListening = false;
        if (speechRecognizer != null) {
            try {
                speechRecognizer.stopListening();
            } catch (Exception ignored) {}
        }
    }

    private void sendSpeechToWeb(final String text, final boolean isFinal) {
        if (webView == null) return;
        final String js = String.format(
                "if(window.onAndroidSpeechResult){window.onAndroidSpeechResult(%s,%s);}",
                toJsStr(text),
                isFinal ? "true" : "false"
        );
        webView.post(new Runnable() {
            @Override
            public void run() {
                webView.evaluateJavascript(js, null);
            }
        });
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (speechRecognizer != null) {
            try {
                speechRecognizer.destroy();
            } catch (Exception ignored) {}
        }
        super.onDestroy();
    }
}
