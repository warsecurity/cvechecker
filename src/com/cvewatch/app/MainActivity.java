package com.cvewatch.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import org.json.JSONArray;
import org.json.JSONObject;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

public class MainActivity extends Activity {
    private static final int BG = Color.WHITE;
    private static final int PANEL = Color.WHITE;
    private static final int SOFT = Color.rgb(246, 248, 251);
    private static final int LINE = Color.rgb(226, 232, 240);
    private static final int TEXT = Color.rgb(15, 23, 42);
    private static final int MUTED = Color.rgb(100, 116, 139);
    private static final int ACCENT = Color.rgb(21, 101, 192);
    private static final int ACCENT_SOFT = Color.rgb(232, 240, 254);
    private static final int GREEN = Color.rgb(46, 125, 50);
    private static final int GREEN_SOFT = Color.rgb(232, 245, 233);
    private static final int RED = Color.rgb(198, 40, 40);
    private static final int RED_SOFT = Color.rgb(253, 236, 234);
    private static final int AMBER = Color.rgb(216, 118, 0);
    private static final long FRESH_WINDOW = 2L * 24 * 60 * 60 * 1000;

    static volatile boolean moduleFlag;

    static boolean isModuleActive() { return moduleFlag; }

    private final Handler handler = new Handler(Looper.getMainLooper());
    private LinearLayout root, page, bottom, resultsBox;
    private ScrollView scroller;
    private TextView progressTitle, progressLine;
    private ProgressBar progressBar;
    private Button progressAction;
    private EditText searchInput;
    private ImageView resyncButton;

    private String tab = "Home";
    private String sort = "new";
    private String query = "";
    private int severityIndex = 0;
    private boolean savedView;
    private boolean searchOpen;
    private boolean alive;
    private int lastRevision = -1;
    private int lastNewsCount = -1;
    private boolean lastNewsBusy;
    private JSONArray online = new JSONArray();
    private boolean onlineBusy;
    private int searchToken;
    private static long lastKick;

    private static final class AgeLabel {
        final TextView view;
        final String prefix;
        final String suffix;
        final long published;
        final TextView star;
        AgeLabel(TextView view, String prefix, String suffix, long published, TextView star) {
            this.view = view;
            this.prefix = prefix;
            this.suffix = suffix;
            this.published = published;
            this.star = star;
        }
    }

    private final List<AgeLabel> ageLabels = new ArrayList<>();
    private long lastAgeRefresh;

    private final Runnable poller = new Runnable() {
        @Override public void run() {
            if (!alive) return;
            if (tab.equals("Home")) {
                JSONObject st = json(Sync.status(MainActivity.this));
                updateProgress(st);
                if (st.optInt("revision", 0) != lastRevision) {
                    lastRevision = st.optInt("revision", 0);
                    fillResults();
                } else if (System.currentTimeMillis() - lastAgeRefresh >= 30_000L) {
                    refreshAges();
                }
            } else if (tab.equals("News")) {
                JSONObject meta = json(News.meta(MainActivity.this));
                if (meta.optInt("count", 0) != lastNewsCount || meta.optBoolean("busy") != lastNewsBusy) renderNews();
            }
            handler.postDelayed(this, 3000);
        }
    };

    private final Runnable debounce = new Runnable() {
        @Override public void run() {
            query = searchInput == null ? query : searchInput.getText().toString().trim();
            online = new JSONArray();
            fillResults();
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        int flags = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
        if (Build.VERSION.SDK_INT >= 26) flags |= View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
        getWindow().getDecorView().setSystemUiVisibility(flags);
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != 0)
            requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 1);
        SyncJob.schedule(this);
        buildShell();
        moduleFlag = moduleFlag || Prefs.systemScannerAlive(this);
        boolean showLatest = getIntent() != null && getIntent().getBooleanExtra("showLatest", false);
        if (showLatest) latestView();
        render();
        if (showLatest) refreshFromNotification();
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (intent != null && intent.getBooleanExtra("showLatest", false)) {
            latestView();
            render();
            refreshFromNotification();
        }
    }

    private void latestView() {
        tab = "Home";
        savedView = false;
        sort = "new";
        severityIndex = 0;
        query = "";
        searchOpen = false;
        online = new JSONArray();
        onlineBusy = false;
        searchToken++;
        lastRevision = -1;
    }

    private void refreshFromNotification() {
        if (!Prefs.hasKey(this) || !Prefs.scopeChosen(this) || Prefs.paused(this) || Sync.running()) return;
        startSync(false, true);
    }

    @Override protected void onStart() {
        super.onStart();
        alive = true;
        handler.removeCallbacks(poller);
        handler.post(poller);
        maybeStartSync();
    }

    @Override protected void onStop() {
        alive = false;
        handler.removeCallbacks(poller);
        new Thread(() -> Db.get(this).markSeen(), "cve-mark-seen").start();
        super.onStop();
    }

    private void buildShell() {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        root.setLayoutParams(new ViewGroup.LayoutParams(-1, -1));

        scroller = new ScrollView(this);
        scroller.setFillViewport(true);
        scroller.setClipToPadding(false);
        scroller.setBackgroundColor(BG);
        page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(16), dp(4), dp(16), dp(28));
        scroller.addView(page, new ScrollView.LayoutParams(-1, -2));
        root.addView(scroller, new LinearLayout.LayoutParams(-1, 0, 1));

        View divider = new View(this);
        divider.setBackgroundColor(LINE);
        root.addView(divider, new LinearLayout.LayoutParams(-1, 1));

        bottom = new LinearLayout(this);
        bottom.setOrientation(LinearLayout.HORIZONTAL);
        bottom.setGravity(Gravity.CENTER);
        bottom.setBackgroundColor(BG);
        bottom.setPadding(dp(6), dp(7), dp(6), dp(9));
        root.addView(bottom, new LinearLayout.LayoutParams(-1, -2));
        setContentView(root);
        drawTabs();
    }

    private void drawTabs() {
        bottom.removeAllViews();
        for (String name : new String[]{"Home", "News", "Settings"}) {
            boolean selected = tab.equals(name);
            TextView b = text(name, 13, selected ? ACCENT : MUTED, selected);
            b.setGravity(Gravity.CENTER);
            b.setPadding(dp(7), dp(11), dp(7), dp(11));
            b.setBackground(selected ? round(ACCENT_SOFT, 22) : null);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1);
            lp.setMargins(dp(4), 0, dp(4), 0);
            bottom.addView(b, lp);
            b.setOnClickListener(v -> {
                if (!tab.equals(name)) savedView = false;
                tab = name;
                render();
            });
        }
    }

    private void render() {
        drawTabs();
        page.removeAllViews();
        progressTitle = progressLine = null;
        progressBar = null;
        progressAction = null;
        searchInput = null;
        resyncButton = null;
        resultsBox = null;
        ageLabels.clear();
        handler.removeCallbacks(debounce);
        scroller.scrollTo(0, 0);
        if (tab.equals("Home")) renderHome();
        else if (tab.equals("News")) renderNews();
        else renderSettings();
    }

    private void topBar(String title) {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(0, dp(8), 0, dp(4));
        page.addView(bar, new LinearLayout.LayoutParams(-1, -2));

        if (savedView) {
            TextView back = text("\u2190", 21, ACCENT, true);
            back.setGravity(Gravity.CENTER);
            back.setPadding(dp(2), dp(6), dp(12), dp(6));
            back.setOnClickListener(v -> { savedView = false; render(); });
            bar.addView(back, new LinearLayout.LayoutParams(-2, -2));
        }

        TextView heading = text(title, 22, TEXT, true);
        bar.addView(heading, new LinearLayout.LayoutParams(0, -2, 1));

        if (tab.equals("Home") && !savedView) {
            resyncButton = new ImageView(this);
            resyncButton.setImageResource(android.R.drawable.ic_popup_sync);
            resyncButton.setColorFilter(TEXT);
            resyncButton.setScaleType(ImageView.ScaleType.CENTER);
            resyncButton.setPadding(dp(11), dp(11), dp(11), dp(11));
            resyncButton.setBackground(round(SOFT, 22));
            resyncButton.setContentDescription("Resync latest CVEs");
            resyncButton.setOnClickListener(v -> manualResync());
            LinearLayout.LayoutParams syncLp = new LinearLayout.LayoutParams(dp(44), dp(44));
            syncLp.setMargins(0, 0, dp(8), 0);
            bar.addView(resyncButton, syncLp);

            ImageView lens = new ImageView(this);
            lens.setImageResource(android.R.drawable.ic_menu_search);
            lens.setColorFilter(TEXT);
            lens.setScaleType(ImageView.ScaleType.CENTER);
            lens.setPadding(dp(11), dp(11), dp(11), dp(11));
            lens.setBackground(round(searchOpen || !query.isEmpty() ? ACCENT_SOFT : SOFT, 22));
            lens.setContentDescription("Search CVEs");
            lens.setOnClickListener(v -> toggleSearch());
            LinearLayout.LayoutParams lensLp = new LinearLayout.LayoutParams(dp(44), dp(44));
            lensLp.setMargins(0, 0, dp(8), 0);
            bar.addView(lens, lensLp);
        }

        TextView more = text("\u22ee", 25, TEXT, false);
        more.setGravity(Gravity.CENTER);
        more.setBackground(round(SOFT, 22));
        more.setOnClickListener(v -> showMenu());
        bar.addView(more, new LinearLayout.LayoutParams(dp(44), dp(44)));
    }

    private void showMenu() {
        final List<String> items = new ArrayList<>();
        if (tab.equals("News")) {
            items.add("Refresh news");
            items.add("Activity logs");
            items.add("Clear all news and refresh");
        } else if (tab.equals("Home")) {
            if (savedView) {
                items.add("Latest CVEs");
            } else {
                items.add("Sort: " + sortLabel());
                items.add("Severity: " + severityLabel());
                items.add("Saved CVEs (" + Prefs.savedCount(this) + ")");
            }
            items.add("Watch CVEs (" + Prefs.watchlist(this).size() + ")");
            items.add("Download options");
            items.add(Sync.running() ? "Pause download" : "Refresh CVE database");
            items.add("Activity logs");
        } else {
            items.add("Activity logs");
            items.add("Watch CVEs (" + Prefs.watchlist(this).size() + ")");
            items.add("Download options");
            items.add(Sync.running() ? "Pause download" : "Refresh CVE database");
        }
        new AlertDialog.Builder(this).setTitle("Options")
                .setItems(items.toArray(new String[0]), (d, which) -> onMenu(items.get(which)))
                .setNegativeButton("Close", null).show();
    }

    private void onMenu(String choice) {
        if (choice.startsWith("Severity:")) { chooseSeverity(); return; }
        if (choice.startsWith("Sort:")) { chooseSort(); return; }
        if (choice.startsWith("Saved CVEs")) { savedView = true; render(); return; }
        if (choice.equals("Latest CVEs")) { savedView = false; render(); return; }
        if (choice.startsWith("Watch CVEs")) { showWatch(); return; }
        if (choice.equals("Download options")) { showDownloadChoice(); return; }
        if (choice.equals("Pause download")) {
            Sync.stop();
            toast("Pausing the download\u2026");
            return;
        }
        if (choice.equals("Refresh CVE database")) { confirmRefresh(); return; }
        if (choice.equals("Refresh news")) { refreshNews(); return; }
        if (choice.equals("Clear all news and refresh")) {
            News.clear(this);
            toast("All news cleared. Fetching fresh stories\u2026");
            renderNews();
            return;
        }
        if (choice.equals("Activity logs")) { renderLogs(); return; }
    }

    private void renderHome() {
        topBar(savedView ? "Saved CVEs" : "CVE Checker");
        if (savedView) {
            resultsBox = new LinearLayout(this);
            resultsBox.setOrientation(LinearLayout.VERTICAL);
            page.addView(resultsBox, new LinearLayout.LayoutParams(-1, -2));
            fillResults();
            return;
        }

        if (searchOpen || !query.isEmpty()) searchBar();
        boolean hasKey = Prefs.hasKey(this);
        JSONObject st = json(Sync.status(this));
        if (hasKey) progressCard(st);

        if (!hasKey) {
            addCard("NVD API key required", "Add and verify your free NVD API key in Settings before downloading CVEs.", RED);
            Button open = primaryButton("Open Settings");
            open.setOnClickListener(v -> { tab = "Settings"; render(); });
            page.addView(open, fullLp(0, 8));
        } else if (!Prefs.scopeChosen(this) && !Sync.running()) {
            addCard("Choose what to download", "Download latest CVE records only or download full 500K CVE records.", null);
            Button choose = primaryButton("Choose what to download");
            choose.setOnClickListener(v -> showDownloadChoice());
            page.addView(choose, fullLp(0, 8));
        }

        resultsBox = new LinearLayout(this);
        resultsBox.setOrientation(LinearLayout.VERTICAL);
        page.addView(resultsBox, new LinearLayout.LayoutParams(-1, -2));
        fillResults();
    }

    private void searchBar() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);

        searchInput = new EditText(this);
        searchInput.setSingleLine(true);
        searchInput.setText(query);
        searchInput.setHint("Search CVEs, vendors or keywords");
        searchInput.setHintTextColor(MUTED);
        searchInput.setTextColor(TEXT);
        searchInput.setTextSize(16);
        searchInput.setInputType(InputType.TYPE_CLASS_TEXT);
        searchInput.setImeOptions(EditorInfo.IME_ACTION_SEARCH);
        searchInput.setBackground(round(SOFT, 16, LINE));
        searchInput.setPadding(dp(16), dp(12), dp(16), dp(12));
        searchInput.setMinHeight(dp(52));
        searchInput.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int a, int b, int c) { }
            @Override public void onTextChanged(CharSequence s, int a, int b, int c) { }
            @Override public void afterTextChanged(Editable s) {
                handler.removeCallbacks(debounce);
                handler.postDelayed(debounce, 400);
            }
        });
        searchInput.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                showSearchChoice();
                return true;
            }
            return false;
        });
        row.addView(searchInput, new LinearLayout.LayoutParams(0, -2, 1));

        Button search = primaryButton("Search");
        LinearLayout.LayoutParams searchLp = new LinearLayout.LayoutParams(-2, -2);
        searchLp.setMargins(dp(8), 0, 0, 0);
        search.setOnClickListener(v -> showSearchChoice());
        row.addView(search, searchLp);
        page.addView(row, fullLp(2, 6));

        if (!query.isEmpty()) {
            Button exit = button("Exit search and load all CVEs");
            exit.setOnClickListener(v -> exitSearch());
            page.addView(exit, fullLp(0, 8));
        }
    }

    private void showSearchChoice() {
        final String value = searchInput == null ? query : searchInput.getText().toString().trim();
        if (value.isEmpty()) { toast("Type a CVE ID, vendor or keyword first."); return; }
        query = value;

        LinearLayout wrap = new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setPadding(dp(24), dp(4), dp(24), 0);
        wrap.addView(text("Search both NVD online and your local database, or search the local database only.", 14, MUTED, false), fullLp(0, 10));

        final RadioGroup group = new RadioGroup(this);
        final RadioButton both = new RadioButton(this);
        both.setId(1101);
        both.setText("Online + local (recommended)");
        both.setTextColor(TEXT);
        both.setTextSize(15);
        both.setPadding(0, dp(8), 0, dp(8));
        final RadioButton localOnly = new RadioButton(this);
        localOnly.setId(1102);
        localOnly.setText("Local only");
        localOnly.setTextColor(TEXT);
        localOnly.setTextSize(15);
        localOnly.setPadding(0, dp(8), 0, dp(8));
        group.addView(both);
        group.addView(localOnly);
        group.check(1101);
        wrap.addView(group);

        new AlertDialog.Builder(this)
                .setTitle("Search CVEs")
                .setView(wrap)
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Search", (d, w) -> {
                    searchToken++;
                    online = new JSONArray();
                    onlineBusy = false;
                    boolean onlineMode = group.getCheckedRadioButtonId() == 1101;
                    render();
                    if (!onlineMode) {
                        toast("Showing local results only.");
                    } else if (!Prefs.hasKey(this)) {
                        toast("No NVD API key. Showing local results only.");
                    } else {
                        searchOnline();
                    }
                }).show();
    }

    private void exitSearch() {
        searchToken++;
        searchOpen = false;
        query = "";
        online = new JSONArray();
        onlineBusy = false;
        handler.removeCallbacks(debounce);
        render();
    }

    private void toggleSearch() {
        if (searchOpen || !query.isEmpty()) {
            exitSearch();
            return;
        }
        searchOpen = true;
        render();
        if (searchInput != null) {
            searchInput.requestFocus();
            searchInput.post(() -> {
                InputMethodManager imm = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
                if (imm != null) imm.showSoftInput(searchInput, InputMethodManager.SHOW_IMPLICIT);
            });
        }
    }

    private void progressCard(JSONObject st) {
        LinearLayout box = cardBox();
        progressTitle = text("", 16, TEXT, true);
        progressLine = text("", 13, MUTED, false);
        progressLine.setPadding(0, dp(5), 0, dp(8));
        progressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progressBar.setMax(100);
        progressBar.setProgressTintList(ColorStateList.valueOf(ACCENT));
        progressBar.setIndeterminateTintList(ColorStateList.valueOf(ACCENT));
        box.addView(progressTitle);
        box.addView(progressLine);
        box.addView(progressBar, new LinearLayout.LayoutParams(-1, dp(6)));

        progressAction = primaryButton("Pause fetching");
        progressAction.setOnClickListener(v -> {
            if (Sync.running()) {
                Sync.stop();
                progressAction.setText("Pausing\u2026");
                progressAction.setEnabled(false);
                toast("Pausing the download\u2026");
            } else {
                startSync(false);
                toast("Resuming the download\u2026");
            }
        });
        box.addView(progressAction, fullLp(10, 0));
        page.addView(box, fullLp(0, 8));
        updateProgress(st);
    }

    private void updateProgress(JSONObject st) {
        if (progressTitle == null || progressBar == null) return;
        String state = st.optString("state", "idle");
        int done = st.optInt("done", 0), total = st.optInt("total", 0);
        int pending = st.optInt("pending", Math.max(0, total - done));
        int percent = st.optInt("percent", 0);
        boolean scope = Prefs.scopeChosen(this);
        boolean running = Sync.running() || state.equals("running");
        if (resyncButton != null) resyncButton.setAlpha(running ? .45f : 1f);

        if (running) {
            progressTitle.setText("Downloading CVEs");
            progressLine.setText(format(done) + " / " + format(total) + (pending > 0 ? "  \u00b7  " + format(pending) + " remaining" : "")
                    + (st.optString("note").isEmpty() ? "" : "  \u00b7  " + st.optString("note")));
            progressBar.setIndeterminate(total <= 0);
            progressBar.setProgress(Math.max(1, Math.min(100, percent)));
            showAction("Pause fetching", true);
        } else if (state.equals("error")) {
            progressTitle.setText("Download failed");
            progressLine.setText(st.optString("note"));
            progressBar.setIndeterminate(false);
            progressBar.setProgress(0);
            showAction("Retry download", scope);
        } else if (state.equals("paused")) {
            progressTitle.setText("Download paused");
            progressLine.setText(format(done) + " / " + format(total) + " downloaded. Tap Resume fetching to continue.");
            progressBar.setIndeterminate(total <= 0);
            progressBar.setProgress(Math.max(1, Math.min(100, percent)));
            showAction("Resume fetching", true);
        } else if (st.optBoolean("complete")) {
            progressTitle.setText(format(st.optInt("count", done)) + " CVEs ready");
            String mode = "all".equals(st.optString("loadedMode")) ? "Full 500K CVEs" : "Latest CVEs";
            progressLine.setText(mode + "  \u00b7  " + (st.optLong("last") > 0 ? "updated " + age(st.optLong("last")) : "ready"));
            progressBar.setIndeterminate(false);
            progressBar.setProgress(100);
            showAction("", false);
        } else {
            progressTitle.setText("CVE database empty");
            progressLine.setText(scope ? "Tap Start download to fetch CVEs with your NVD key." : "Choose what to download to get started.");
            progressBar.setIndeterminate(false);
            progressBar.setProgress(0);
            showAction("Start download", scope);
        }
    }

    private void showAction(String label, boolean visible) {
        if (progressAction == null) return;
        progressAction.setText(label);
        progressAction.setEnabled(true);
        progressAction.setVisibility(visible ? View.VISIBLE : View.GONE);
    }

    private void fillResults() {
        if (resultsBox == null) return;
        resultsBox.removeAllViews();
        ageLabels.clear();
        lastAgeRefresh = System.currentTimeMillis();
        if (savedView) { fillSaved(); return; }

        JSONArray rows;
        try { rows = new JSONArray(Db.get(this).rows(query, severityLabel(), sort, 80)); }
        catch (Exception e) { rows = new JSONArray(); }

        List<String> localIds = new ArrayList<>();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject c = rows.optJSONObject(i);
            if (c != null) localIds.add(c.optString("id"));
        }
        int onlineShown = 0;
        for (int i = 0; i < online.length(); i++) {
            JSONObject c = online.optJSONObject(i);
            if (c != null && !localIds.contains(c.optString("id"))) onlineShown++;
        }
        if (!query.isEmpty()) {
            String summary = format(rows.length()) + (rows.length() >= 80 ? "+" : "") + " local matches";
            if (onlineShown > 0) summary += " \u00b7 " + format(onlineShown) + " online";
            resultsBox.addView(text(summary + " for \u201c" + query + "\u201d", 12, MUTED, false), fullLp(4, 6));
        }
        if (rows.length() == 0) {
            if (!query.isEmpty()) {
                if (onlineBusy) {
                    resultsBox.addView(text("No local matches. Searching NVD online\u2026", 12, ACCENT, false), fullLp(4, 6));
                } else if (online.length() > 0) {
                    resultsBox.addView(text("No local matches. Showing NVD online results below.", 12, MUTED, false), fullLp(4, 6));
                } else {
                    addCardTo(resultsBox, "No matches found",
                            Prefs.hasKey(this) ? "Nothing matched locally or online. Try the Search button to search NVD online again."
                                    : "Nothing matched locally. Add an NVD API key in Settings to search NVD online too.",
                            null);
                }
            } else if (!Prefs.hasKey(this)) {
                addCardTo(resultsBox, "No CVEs stored yet", "Add and verify your NVD API key in Settings to start downloading CVEs.", null);
            } else if (!Prefs.scopeChosen(this)) {
                addCardTo(resultsBox, "No CVEs yet", "Download latest CVE records only or download full 500K CVE records.", null);
            } else {
                addCardTo(resultsBox, "No CVEs stored yet", "Tap Start download above, or use Refresh CVE database in the menu.", null);
            }
        }
        for (int i = 0; i < rows.length(); i++) {
            JSONObject c = rows.optJSONObject(i);
            if (c != null) resultsBox.addView(cveRow(c, false), fullLp(0, 7));
        }
        if (!query.isEmpty() && onlineBusy && rows.length() > 0) {
            resultsBox.addView(text("Searching NVD online\u2026", 12, ACCENT, false), fullLp(4, 6));
        }
        if (onlineShown > 0) {
            resultsBox.addView(text(format(onlineShown) + " online results", 12, ACCENT, true), fullLp(6, 4));
            for (int i = 0; i < online.length(); i++) {
                JSONObject c = online.optJSONObject(i);
                if (c != null && !localIds.contains(c.optString("id"))) resultsBox.addView(cveRow(c, true), fullLp(0, 7));
            }
        }
    }

    private void fillSaved() {
        JSONArray saved = Prefs.savedJson(this);
        if (saved.length() == 0) {
            addCardTo(resultsBox, "No saved CVEs", "Open a CVE on the home screen and choose Save CVE to keep it here.", null);
            return;
        }
        Button clear = button("Delete all saved CVEs");
        clear.setTextColor(RED);
        clear.setOnClickListener(v -> new AlertDialog.Builder(this).setTitle("Delete all saved CVEs?")
                .setNegativeButton("Cancel", null).setPositiveButton("Delete", (d, w) -> {
                    Prefs.clearSavedCves(this);
                    fillResults();
                }).show());
        resultsBox.addView(clear, fullLp(0, 8));
        for (int i = 0; i < saved.length(); i++) {
            JSONObject c = saved.optJSONObject(i);
            if (c != null) resultsBox.addView(cveRow(c, false), fullLp(0, 7));
        }
    }

    private LinearLayout cveRow(JSONObject c, boolean remote) {
        LinearLayout box = cardBox();
        String id = c.optString("id");
        long published = publishedMs(c.optString("pub"));
        boolean fresh = isFresh(published);
        LinearLayout headRow = new LinearLayout(this);
        headRow.setOrientation(LinearLayout.HORIZONTAL);
        headRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView star = null;
        if (fresh) {
            star = text("\u2605", 15, GREEN, false);
            star.setPadding(0, 0, dp(6), 0);
            headRow.addView(star);
        }
        headRow.addView(text(id + (Prefs.isSaved(this, id) ? "   \u2605" : ""), 16, TEXT, true));
        box.addView(headRow);
        String vendor = c.optString("vendor");
        if (!vendor.isEmpty()) box.addView(text(vendor, 13, MUTED, false));
        String d = c.optString("desc");
        if (!d.isEmpty()) {
            TextView desc = text(d, 13, MUTED, false);
            desc.setPadding(0, dp(5), 0, dp(5));
            box.addView(desc);
        }
        String severity = c.optString("sev", "Unrated");
        int color = severity.equals("Critical") ? RED : severity.equals("High") ? AMBER : severity.equals("Medium") ? 0xFF9A6700 : GREEN;
        double score = c.optDouble("score", -1);
        String before = (score >= 0 ? String.format(Locale.US, "%.1f", score) + " \u00b7 " : "") + severity
                + (c.optBoolean("kev") ? " \u00b7 Actively exploited" : "");
        String source = c.optString("src", remote ? "NVD online" : "");
        String suffix = source.isEmpty() ? "" : " \u00b7 " + source;
        String prefix = before + (published > 0 ? " \u00b7 " : "");
        TextView metaView = text(prefix + (published > 0 ? age(published) : "") + suffix, 12, color, false);
        box.addView(metaView);
        ageLabels.add(new AgeLabel(metaView, prefix, suffix, published, star));
        box.setOnClickListener(v -> cveActions(c, remote));
        return box;
    }

    private void cveActions(JSONObject c, boolean remote) {
        final String id = c.optString("id");
        final String vendor = c.optString("vendor");
        final List<String> labels = new ArrayList<>();
        labels.add(Prefs.isSaved(this, id) ? "Remove from saved CVEs" : "Save CVE");
        if (!vendor.isEmpty()) labels.add("Watch \u201c" + vendor + "\u201d");
        labels.add("Open on nvd.nist.gov");
        if (remote) labels.add("Save to local database");
        new AlertDialog.Builder(this).setTitle(id)
                .setItems(labels.toArray(new String[0]), (d, which) -> {
                    String pick = labels.get(which);
                    if (pick.equals("Save CVE")) {
                        Prefs.saveCve(this, c);
                        toast("Saved " + id);
                        fillResults();
                    } else if (pick.startsWith("Remove from saved")) {
                        Prefs.removeSavedCve(this, id);
                        toast("Removed " + id);
                        fillResults();
                    } else if (pick.startsWith("Watch")) {
                        List<String> watch = Prefs.watchlist(this);
                        if (!watch.contains(vendor)) watch.add(vendor);
                        Prefs.saveWatchlist(this, watch);
                        toast("Watching " + vendor);
                    } else if (pick.equals("Save to local database")) {
                        Db.get(this).saveOne(c);
                        Prefs.saveCve(this, c);
                        toast("Saved to database");
                        fillResults();
                    } else {
                        openExternal("https://nvd.nist.gov/vuln/detail/" + id);
                    }
                }).show();
    }

    private JSONObject remoteJson(Nvd.Cve cve, String source) throws Exception {
        return new JSONObject().put("id", cve.id).put("pub", cve.published)
                .put("score", cve.score).put("sev", cve.severity())
                .put("vendor", cve.vendor).put("desc", cve.description).put("src", source);
    }

    private void searchOnline() {
        final String q = query;
        if (q.isEmpty() || onlineBusy || !Prefs.hasKey(this)) return;
        final int token = ++searchToken;
        onlineBusy = true;
        fillResults();
        new Thread(() -> {
            JSONArray found = new JSONArray();
            String error = null;
            try {
                JSONObject response = Nvd.search(q, Prefs.apiKey(this));
                JSONArray items = response.optJSONArray("vulnerabilities");
                if (items != null) {
                    for (int i = 0; i < items.length() && i < 40; i++) {
                        found.put(remoteJson(Nvd.parse(items.getJSONObject(i)), "NVD online"));
                    }
                }
            } catch (Exception e) {
                error = String.valueOf(e.getMessage());
            }
            if (found.length() == 0) {
                String id = Nvd.parseCveId(q);
                if (id != null) {
                    try {
                        Nvd.Cve cve = Nvd.byCveOrg(id);
                        if (cve != null) {
                            found.put(remoteJson(cve, "CVE.org"));
                            error = null;
                        }
                    } catch (Exception e) {
                        if (error == null) error = String.valueOf(e.getMessage());
                    }
                }
            }
            final JSONArray result = found;
            final String failure = error;
            runOnUiThread(() -> {
                if (token != searchToken) return;
                onlineBusy = false;
                online = result;
                if (failure != null) toast("Online search unavailable. Showing local results only.");
                else if (result.length() == 0) toast("No online matches found. Local results are shown.");
                fillResults();
            });
        }, "online-search").start();
    }

    private void renderNews() {
        topBar("Security news");
        JSONObject meta = json(News.meta(this));
        lastNewsCount = meta.optInt("count", 0);
        lastNewsBusy = meta.optBoolean("busy");

        LinearLayout head = cardBox();
        head.addView(text("Latest security and cyber headlines", 17, TEXT, true));
        String stamp = meta.optLong("at") == 0 ? "not refreshed yet" : "updated " + age(meta.optLong("at"));
        head.addView(text(meta.optInt("count") + " / " + Prefs.newsLimit(this) + " headlines \u00b7 " + stamp, 12, MUTED, false));
        if (meta.optBoolean("busy"))
            head.addView(text("Refreshing " + meta.optInt("done") + " / " + meta.optInt("total") + " feeds", 12, ACCENT, false));
        page.addView(head, fullLp(2, 10));

        Button refresh = primaryButton(meta.optBoolean("busy") ? "Refreshing news\u2026" : "Refresh news");
        refresh.setEnabled(!meta.optBoolean("busy"));
        if (meta.optBoolean("busy")) refresh.setAlpha(.6f);
        refresh.setOnClickListener(v -> refreshNews());
        page.addView(refresh, fullLp(0, 10));

        JSONArray all;
        try { all = new JSONArray(News.json(this)); } catch (Exception e) { all = new JSONArray(); }
        if (all.length() == 0) addCard("Fetching live feeds", "Headlines come from more than 300 public RSS and Atom sources. Tap Refresh news, or wait for the configured interval.", null);
        for (int i = 0; i < all.length(); i++) {
            JSONArray item = all.optJSONArray(i);
            if (item != null) page.addView(newsRow(item), fullLp(0, 6));
        }
    }

    private LinearLayout newsRow(JSONArray item) {
        LinearLayout box = cardBox();
        String cat = item.optString(4, "n");
        String label = cat.equals("v") ? "CVE / ADVISORY" : cat.equals("c") ? "CRYPTO" : cat.equals("r") ? "RESEARCH" : "CYBER NEWS";
        long time = item.optLong(2);
        box.addView(text(label + "  \u00b7  " + item.optString(0) + (time > 0 ? "  \u00b7  " + age(time) : ""), 11, ACCENT, true));
        TextView headline = text(item.optString(1), 15, TEXT, true);
        headline.setPadding(0, dp(5), 0, 0);
        box.addView(headline);
        final String url = item.optString(3);
        box.setOnClickListener(v -> openExternal(url));
        return box;
    }

    private void refreshNews() {
        News.refresh(this);
        toast("Refreshing news feeds\u2026");
        renderNews();
    }

    private void renderLogs() {
        page.removeAllViews();
        progressTitle = progressLine = null;
        progressBar = null;
        progressAction = null;
        searchInput = null;
        resyncButton = null;
        resultsBox = null;

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        TextView back = text("\u2190  Activity logs", 17, TEXT, true);
        back.setPadding(0, dp(12), 0, dp(10));
        back.setOnClickListener(v -> render());
        bar.addView(back, new LinearLayout.LayoutParams(0, -2, 1));
        page.addView(bar, new LinearLayout.LayoutParams(-1, -2));

        JSONArray logs = Prefs.logs(this);
        Button clear = button("Clear all logs");
        clear.setTextColor(RED);
        clear.setOnClickListener(v -> new AlertDialog.Builder(this).setTitle("Clear all logs?")
                .setMessage("This removes every stored activity entry.")
                .setNegativeButton("Cancel", null).setPositiveButton("Clear", (d, w) -> {
                    Prefs.clearLogs(this);
                    renderLogs();
                    toast("Logs cleared");
                }).show());
        page.addView(clear, fullLp(0, 10));

        if (logs.length() == 0) {
            addCard("No activity yet", "CVE syncs, news refreshes and scanner events will appear here.", null);
            return;
        }
        for (int i = 0; i < logs.length(); i++) {
            JSONArray row = logs.optJSONArray(i);
            if (row == null) continue;
            LinearLayout box = cardBox();
            box.addView(text(row.optString(0), 11, ACCENT, true));
            box.addView(text(row.optString(1), 13, TEXT, false));
            page.addView(box, fullLp(0, 6));
        }
    }

    private void renderSettings() {
        topBar("Settings");
        addSection("Module status");

        boolean active = Prefs.systemScannerAlive(this) || isModuleActive();
        LinearLayout lsp = statusBox("LSPosed system scanner",
                active ? "Active. Last scanner beat " + age(Prefs.beat(this)) + "."
                        : "Not active. Enable CVE Checker inside LSPosed and scope it to System Framework, then reboot.",
                active);
        page.addView(lsp, fullLp(0, 6));

        boolean verified = Prefs.verified(this);
        LinearLayout keyBox = statusBox("NVD API key",
                verified ? "Verified" + (Prefs.verifiedAt(this) > 0 ? " " + age(Prefs.verifiedAt(this)) : "")
                        : Prefs.hasKey(this) ? "Saved but not verified. Verify it to start downloads."
                        : "No key stored. A verified key is required before any CVE download.",
                verified);
        page.addView(keyBox, fullLp(0, 6));

        Button editKey = primaryButton(Prefs.hasKey(this) ? "Replace API key" : "Add and verify API key");
        editKey.setOnClickListener(v -> showKeyDialog());
        page.addView(editKey, fullLp(0, 8));
        TextView getKey = text("Request a free key from nvd.nist.gov", 13, ACCENT, false);
        getKey.setPadding(dp(4), dp(2), dp(4), dp(10));
        getKey.setOnClickListener(v -> openExternal("https://nvd.nist.gov/developers/request-an-api-key"));
        page.addView(getKey);

        addSection("CVE database");
        addCard("Download scope",
                "latest".equals(Prefs.mode(this))
                        ? "Download latest CVE records only."
                        : "Download full 500K CVE records.",
                null);
        Button scope = button("Choose what to download");
        scope.setOnClickListener(v -> showDownloadChoice());
        page.addView(scope, fullLp(0, 7));

        Button refresh = button("Refresh CVE database now");
        refresh.setOnClickListener(v -> confirmRefresh());
        page.addView(refresh, fullLp(0, 7));

        addSection("Background");
        Button interval = button("CVE sync interval \u00b7 " + intervalName());
        interval.setOnClickListener(v -> chooseInterval());
        page.addView(interval, fullLp(0, 7));
        Button news = button("News refresh \u00b7 " + Prefs.newsIntervalName(this));
        news.setOnClickListener(v -> chooseNewsInterval());
        page.addView(news, fullLp(0, 7));
        Button newsLimit = button("News history limit \u00b7 " + Prefs.newsLimit(this));
        newsLimit.setOnClickListener(v -> chooseNewsLimit());
        page.addView(newsLimit, fullLp(0, 7));
        addCard("News cleanup", "Oldest headlines are removed automatically when the limit is reached. News feeds refresh every 2 hours by default, then the oldest stories are replaced with fresh ones.", null);
        Button battery = button("Battery optimization settings");
        battery.setOnClickListener(v -> openBatterySettings());
        page.addView(battery, fullLp(0, 7));

        addSection("Watch list");
        addCard("Watch CVEs", Prefs.watchlist(this).isEmpty()
                        ? "No vendors watched. Add ftp, mtk or any vendor to get notified when a matching CVE is detected."
                        : String.join(", ", Prefs.watchlist(this)),
                null);
        Button watch = button("Manage watch list");
        watch.setOnClickListener(v -> showWatch());
        page.addView(watch, fullLp(0, 7));

        addSection("Activity");
        Button logs = button("Activity logs");
        logs.setOnClickListener(v -> renderLogs());
        page.addView(logs, fullLp(0, 7));

        addSection("About");
        addCard("CVE Checker 0.8", "CVE Checker is open source. Source code: https://github.com/warsecurity/cvechecker\n\nCVE data: NVD. Exploited list: CISA KEV. News: 360+ public RSS and Atom feeds.", null);
        Button github = primaryButton("Open source code on GitHub");
        github.setOnClickListener(v -> showGitHubDialog());
        page.addView(github, fullLp(0, 7));
    }

    private void showGitHubDialog() {
        new AlertDialog.Builder(this)
                .setTitle("Open GitHub?")
                .setMessage("You will be redirected to https://github.com/warsecurity/cvechecker")
                .setPositiveButton("Yes", (d, w) -> openExternal("https://github.com/warsecurity/cvechecker"))
                .setNegativeButton("Quit", null)
                .show();
    }

    private void chooseNewsLimit() {
        final EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setInputType(InputType.TYPE_CLASS_NUMBER);
        input.setText(String.valueOf(Prefs.newsLimit(this)));
        input.setSelectAllOnFocus(true);
        input.setTextColor(TEXT);
        input.setBackground(round(SOFT, 12, LINE));
        input.setPadding(dp(12), dp(10), dp(12), dp(10));
        LinearLayout wrap = new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setPadding(dp(22), dp(4), dp(22), 0);
        wrap.addView(text("Enter the maximum number of news stories to keep. Maximum: " + Prefs.NEWS_LIMIT_MAX + ". Oldest stories are removed first.", 13, MUTED, false), fullLp(0, 8));
        wrap.addView(input, new LinearLayout.LayoutParams(-1, -2));
        new AlertDialog.Builder(this)
                .setTitle("News history limit")
                .setView(wrap)
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Save", (d, w) -> {
                    int value;
                    try { value = Integer.parseInt(input.getText().toString().trim()); }
                    catch (Exception e) { value = Prefs.newsLimit(this); }
                    value = Math.max(1, Math.min(Prefs.NEWS_LIMIT_MAX, value));
                    Prefs.setNewsLimit(this, value);
                    News.trimToLimit(this);
                    toast("News limit set to " + value);
                    render();
                })
                .show();
    }

    private LinearLayout statusBox(String title, String body, boolean good) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(14), dp(12), dp(14), dp(12));
        box.setBackground(round(good ? GREEN_SOFT : RED_SOFT, 14));
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        TextView dot = text("\u25cf", 12, good ? GREEN : RED, false);
        dot.setPadding(0, 0, dp(7), 0);
        header.addView(dot);
        header.addView(text(title, 15, TEXT, true));
        box.addView(header);
        TextView b = text(body, 13, good ? GREEN : RED, false);
        b.setPadding(0, dp(5), 0, 0);
        box.addView(b);
        return box;
    }

    private void showKeyDialog() {
        final EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setText(Prefs.apiKey(this));
        input.setHint("Paste NVD API key");
        input.setHintTextColor(MUTED);
        input.setTextColor(TEXT);
        input.setBackground(round(SOFT, 12, LINE));
        input.setPadding(dp(12), dp(10), dp(12), dp(10));
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        LinearLayout wrap = new LinearLayout(this);
        wrap.setPadding(dp(22), dp(4), dp(22), 0);
        wrap.addView(input, new LinearLayout.LayoutParams(-1, -2));
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Verify NVD API key")
                .setMessage("The key is tested against NVD before it is stored. After verification you can choose what to download.")
                .setView(wrap).setNegativeButton("Cancel", null).setPositiveButton("Verify and save", null).create();
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            final String candidate = input.getText().toString().trim();
            if (candidate.isEmpty()) { input.setError("An API key is required"); return; }
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);
            dialog.setTitle("Checking key with NVD\u2026");
            new Thread(() -> {
                String result = Sync.testKey(candidate);
                runOnUiThread(() -> {
                    if (result.startsWith("Key accepted")) {
                        Prefs.get(this).edit().putString("apiKey", candidate).putBoolean("verified", true)
                                .putLong("verifiedAt", System.currentTimeMillis())
                                .putBoolean("complete", false).putBoolean("scopeChosen", false)
                                .putBoolean("paused", false).putInt("offset", 0).putInt("total", 0)
                                .putInt("done", 0).apply();
                        dialog.dismiss();
                        toast("Key verified. Choose what to download.");
                        render();
                        showDownloadChoice();
                    } else {
                        Prefs.setVerified(this, false);
                        dialog.setTitle("Key not accepted");
                        dialog.setMessage(result);
                        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(true);
                        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setText("Try again");
                    }
                });
            }, "nvd-key-check").start();
        }));
        dialog.show();
    }

    private void showDownloadChoice() {
        if (!Prefs.hasKey(this)) {
            new AlertDialog.Builder(this).setTitle("API key required")
                    .setMessage("Add and verify an NVD API key in Settings first.")
                    .setPositiveButton("Open Settings", (d, w) -> { tab = "Settings"; render(); })
                    .setNegativeButton("Cancel", null).show();
            return;
        }

        LinearLayout wrap = new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setPadding(dp(24), dp(4), dp(24), 0);
        TextView info = text("Download latest CVE records only or download full 500K CVE records.\n\n"
                + "You can pause the download at any time on the Home screen.", 14, MUTED, false);
        wrap.addView(info, fullLp(0, 12));

        final RadioGroup group = new RadioGroup(this);
        final RadioButton newest = new RadioButton(this);
        newest.setId(1001);
        newest.setText("Download latest CVE records only");
        newest.setTextColor(TEXT);
        newest.setTextSize(15);
        newest.setPadding(0, dp(8), 0, dp(8));
        final RadioButton all = new RadioButton(this);
        all.setId(1002);
        all.setText("Download full 500K CVE records");
        all.setTextColor(TEXT);
        all.setTextSize(15);
        all.setPadding(0, dp(8), 0, dp(8));
        group.addView(newest);
        group.addView(all);
        group.check("all".equals(Prefs.mode(this)) ? 1002 : 1001);
        wrap.addView(group);

        new AlertDialog.Builder(this)
                .setTitle("Choose what to download")
                .setView(wrap)
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Start download", (d, w) -> {
                    int picked = group.getCheckedRadioButtonId();
                    String mode = picked == 1002 ? "all" : "latest";
                    Prefs.setMode(this, mode);
                    Prefs.setScopeChosen(this, true);
                    Prefs.setPaused(this, false);
                    Prefs.get(this).edit().putBoolean("complete", false).putInt("offset", 0)
                            .putInt("total", 0).putInt("done", 0).putLong("lastChange", 0).apply();
                    startSync(true);
                    tab = "Home";
                    savedView = false;
                    render();
                    toast(mode.equals("all")
                            ? "Downloading full 500K CVE records. You can pause on Home."
                            : "Downloading latest CVE records only. You can pause on Home.");
                })
                .show();
    }

    private void confirmRefresh() {
        if (!Prefs.hasKey(this)) {
            new AlertDialog.Builder(this).setTitle("API key required")
                    .setMessage("Add and verify an NVD API key in Settings first.")
                    .setPositiveButton("Open Settings", (d, w) -> { tab = "Settings"; render(); })
                    .setNegativeButton("Cancel", null).show();
            return;
        }
        new AlertDialog.Builder(this).setTitle("Refresh CVE database?")
                .setMessage("The local cache is cleared and downloaded again using the current scope ("
                        + ("all".equals(Prefs.mode(this)) ? "full 500K CVE records" : "latest CVE records only") + "). Saved CVEs are kept.")
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Refresh", (d, w) -> startSync(true)).show();
    }

    private void manualResync() {
        if (Sync.running()) { toast("A sync is already running."); return; }
        if (!Prefs.hasKey(this)) { toast("Add and verify an NVD API key in Settings first."); return; }
        startSync(false, true);
        toast("Resyncing latest CVEs\u2026");
    }

    private void startSync(boolean forceFull) { startSync(forceFull, false); }

    private void startSync(boolean forceFull, boolean resync) {
        if (!Prefs.hasKey(this)) { toast("A verified NVD API key is required."); return; }
        if (Sync.running()) { toast("A download is already running."); return; }
        lastKick = System.currentTimeMillis();
        Prefs.setPaused(this, false);
        Intent i = new Intent(this, SyncService.class).putExtra("forceFull", forceFull).putExtra("resync", resync);
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(i); else startService(i);
        } catch (Exception e) {
            toast("Could not start CVE sync: " + e.getMessage());
        }
    }

    private void maybeStartSync() {
        if (!Prefs.hasKey(this) || !Prefs.scopeChosen(this) || Prefs.paused(this) || Sync.running()) return;
        if (System.currentTimeMillis() - lastKick < 120_000L) return;
        SharedPreferences p = Prefs.get(this);
        if (!p.getBoolean("complete", false) || Sync.due(this)) {
            lastKick = System.currentTimeMillis();
            startSync(false);
        }
    }

    private void chooseSeverity() {
        final String[] choices = {"All", "Critical", "High", "Medium", "Low"};
        new AlertDialog.Builder(this).setTitle("Severity filter").setSingleChoiceItems(choices, severityIndex, (d, which) -> {
            severityIndex = which;
            d.dismiss();
            if (resultsBox != null) fillResults(); else render();
        }).setNegativeButton("Cancel", null).show();
    }

    private String severityLabel() {
        return new String[]{"All", "Critical", "High", "Medium", "Low"}[Math.max(0, Math.min(4, severityIndex))];
    }

    private void chooseSort() {
        final String[] labels = {"Newest first", "Oldest first", "Highest score"};
        final String[] values = {"new", "old", "score"};
        int current = 0;
        for (int i = 0; i < values.length; i++) if (values[i].equals(sort)) current = i;
        new AlertDialog.Builder(this).setTitle("Sort results").setSingleChoiceItems(labels, current, (d, which) -> {
            sort = values[which];
            d.dismiss();
            if (resultsBox != null) fillResults(); else render();
        }).setNegativeButton("Cancel", null).show();
    }

    private String sortLabel() {
        return sort.equals("old") ? "Oldest first" : sort.equals("score") ? "Highest score" : "Newest first";
    }

    private void showWatch() {
        LinearLayout wrap = new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setPadding(dp(20), dp(4), dp(20), 0);

        wrap.addView(text("LSPosed checks your watchlist in the background. You will get a notification with the watched name, such as ftp or mtk, when a matching CVE is detected.", 13, MUTED, false), fullLp(0, 10));

        final EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setHint("Vendor or keyword, e.g. ftp, mtk, samsung");
        input.setHintTextColor(MUTED);
        input.setTextColor(TEXT);
        input.setBackground(round(SOFT, 10, LINE));
        input.setPadding(dp(10), dp(8), dp(10), dp(8));
        wrap.addView(input, new LinearLayout.LayoutParams(-1, -2));
        Button add = button("Add to watch list");
        wrap.addView(add, fullLp(0, 8));
        final List<String> current = Prefs.watchlist(this);
        for (final String entry : current) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);
            TextView label = text(entry, 14, TEXT, false);
            row.addView(label, new LinearLayout.LayoutParams(0, -2, 1));
            TextView remove = text("\u2715", 15, RED, true);
            remove.setPadding(dp(12), dp(8), dp(4), dp(8));
            remove.setOnClickListener(v -> {
                List<String> next = Prefs.watchlist(this);
                next.remove(entry);
                Prefs.saveWatchlist(this, next);
                toast("Removed " + entry);
            });
            row.addView(remove);
            wrap.addView(row, fullLp(0, 4));
        }
        add.setOnClickListener(v -> {
            String value = input.getText().toString().trim();
            if (value.isEmpty()) { input.setError("Enter a vendor or keyword"); return; }
            List<String> next = Prefs.watchlist(this);
            if (!next.contains(value)) next.add(value);
            Prefs.saveWatchlist(this, next);
            input.setText("");
            toast("Watching " + value + ". You will be notified when a matching CVE is exploited.");
        });
        new AlertDialog.Builder(this).setTitle("Watch CVEs").setView(wrap)
                .setNegativeButton("Close", null).show();
    }

    private void chooseNewsInterval() {
        String[] names = Prefs.newsIntervalNames();
        new AlertDialog.Builder(this).setTitle("News refresh interval")
                .setSingleChoiceItems(names, Prefs.newsIntervalIndex(this), (d, which) -> {
                    Prefs.setNewsInterval(this, which);
                    SyncJob.schedule(this);
                    d.dismiss();
                    render();
                }).setNegativeButton("Cancel", null).show();
    }

    private void chooseInterval() {
        String[] names = {"Every 15 minutes", "Every hour", "Every 6 hours", "Every 24 hours"};
        new AlertDialog.Builder(this).setTitle("Background CVE sync interval").setSingleChoiceItems(names, Prefs.get(this).getInt("interval", 0), (d, which) -> {
            Prefs.get(this).edit().putInt("interval", which).apply();
            SyncJob.schedule(this);
            d.dismiss();
            render();
        }).setNegativeButton("Cancel", null).show();
    }

    private String intervalName() {
        String[] a = {"15 minutes", "1 hour", "6 hours", "24 hours"};
        int i = Math.max(0, Math.min(a.length - 1, Prefs.get(this).getInt("interval", 0)));
        return a[i];
    }

    private void openBatterySettings() {
        String pkg = getPackageName();
        new Thread(() -> {
            try { Runtime.getRuntime().exec(new String[]{"su", "-c", "dumpsys deviceidle whitelist +" + pkg}).waitFor(); }
            catch (Exception ignored) { }
        }, "battery-whitelist").start();
        try { startActivity(new Intent("android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", Uri.parse("package:" + pkg))); }
        catch (Exception e) {
            try { startActivity(new Intent("android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS")); } catch (Exception ignored) { }
        }
    }

    private void openExternal(String url) {
        if (url == null || !(url.startsWith("https://") || url.startsWith("http://"))) return;
        try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); }
        catch (ActivityNotFoundException e) { toast("No browser is available to open this link."); }
    }

    private void addSection(String title) {
        TextView t = text(title.toUpperCase(Locale.US), 11, MUTED, true);
        t.setLetterSpacing(.1f);
        t.setPadding(0, dp(14), 0, dp(6));
        page.addView(t);
    }

    private void addCard(String title, String body, Integer bodyColor) {
        addCardTo(page, title, body, bodyColor);
    }

    private void addCardTo(LinearLayout parent, String title, String body, Integer bodyColor) {
        LinearLayout box = cardBox();
        box.addView(text(title, 15, TEXT, true));
        TextView b = text(body, 13, bodyColor == null ? MUTED : bodyColor, false);
        b.setPadding(0, dp(5), 0, 0);
        box.addView(b);
        parent.addView(box, fullLp(0, 6));
    }

    private LinearLayout cardBox() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(14), dp(12), dp(14), dp(12));
        box.setBackground(round(PANEL, 16, LINE));
        return box;
    }

    private TextView text(String s, int sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s == null ? "" : s);
        t.setTextSize(sp);
        t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        t.setIncludeFontPadding(true);
        return t;
    }

    private Button button(String label) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(14);
        b.setTextColor(TEXT);
        b.setPadding(dp(12), dp(2), dp(12), dp(2));
        b.setMinHeight(dp(44));
        b.setBackground(round(SOFT, 12, LINE));
        return b;
    }

    private Button primaryButton(String label) {
        Button b = button(label);
        b.setTextColor(Color.WHITE);
        b.setBackground(round(ACCENT, 12));
        return b;
    }

    private GradientDrawable round(int color, int radius) {
        return round(color, radius, 0);
    }

    private GradientDrawable round(int color, int radius, int strokeColor) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(radius));
        if (strokeColor != 0) d.setStroke(1, strokeColor);
        return d;
    }

    private LinearLayout.LayoutParams fullLp(int top, int bottom) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(top), 0, dp(bottom));
        return p;
    }

    private int dp(float v) { return (int) (v * getResources().getDisplayMetrics().density + .5f); }

    private String format(int n) { return String.format(Locale.US, "%,d", n); }

    private JSONObject json(String s) { try { return new JSONObject(s); } catch (Exception e) { return new JSONObject(); } }

    private void toast(String message) { Toast.makeText(this, message, Toast.LENGTH_SHORT).show(); }

    private void refreshAges() {
        lastAgeRefresh = System.currentTimeMillis();
        if (ageLabels.isEmpty()) return;
        for (AgeLabel label : ageLabels) {
            label.view.setText(label.prefix + (label.published > 0 ? age(label.published) : "") + label.suffix);
            if (label.star != null) label.star.setVisibility(isFresh(label.published) ? View.VISIBLE : View.GONE);
        }
    }

    private boolean isFresh(long published) {
        return published > 0 && System.currentTimeMillis() - published <= FRESH_WINDOW;
    }

    private long publishedMs(String value) {
        if (value == null) return 0;
        String s = value.trim();
        if (s.length() < 19) return 0;
        try {
            SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US);
            f.setTimeZone(TimeZone.getTimeZone("UTC"));
            f.setLenient(true);
            return f.parse(s.substring(0, 19)).getTime();
        } catch (Exception e) { return 0; }
    }

    private String age(long ms) {
        if (ms <= 0) return "not yet";
        long m = Math.max(0, (System.currentTimeMillis() - ms) / 60_000L);
        if (m < 1) return "just now";
        if (m == 1) return "1 minute ago";
        if (m < 60) return m + " minutes ago";
        long h = m / 60;
        if (h == 1) return "1 hour ago";
        if (h < 24) return h + " hours ago";
        long d = h / 24;
        if (d == 1) return "1 day ago";
        return d + " days ago";
    }
}
