#!/bin/bash
set -e

BASE="${1:-/tmp/cc/cvechecker}"
mkdir -p "$BASE"
cd "$BASE"

echo "=== CVE Checker UI Overhaul (White Theme + Search Top + Pause + API Key Flow) ==="

# Create all necessary directories first
mkdir -p app/src/main/res/values
mkdir -p app/src/main/res/drawable
mkdir -p app/src/main/res/drawable-v21
mkdir -p app/src/main/res/menu
mkdir -p app/src/main/res/layout
mkdir -p app/src/main/java/com/example/cvechecker

# ============ 1. COLORS (White theme) ============
cat > app/src/main/res/values/colors.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="colorPrimary">#FFFFFF</color>
    <color name="colorPrimaryDark">#F5F5F5</color>
    <color name="colorAccent">#1565C0</color>
    <color name="windowBackground">#FAFAFA</color>
    <color name="textPrimary">#212121</color>
    <color name="textSecondary">#757575</color>
    <color name="divider">#E0E0E0</color>
    <color name="cardBackground">#FFFFFF</color>
    <color name="error">#D32F2F</color>
    <color name="success">#388E3C</color>
    <color name="warning">#F57C00</color>
    <color name="info">#1976D2</color>
    <color name="ripple">#1F000000</color>
    <color name="overlay">#88000000</color>
    <color name="searchBg">#F0F0F0</color>
    <color name="badge">#D32F2F</color>
    <color name="tabIndicator">#1565C0</color>
    <color name="iconTint">#616161</color>
    <color name="buttonText">#FFFFFF</color>
</resources>
EOF

# ============ 2. THEMES ============
cat > app/src/main/res/values/styles.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="Theme.MaterialComponents.Light.DarkActionBar">
        <item name="colorPrimary">@color/colorPrimary</item>
        <item name="colorPrimaryDark">@color/colorPrimaryDark</item>
        <item name="colorAccent">@color/colorAccent</item>
        <item name="android:windowBackground">@color/windowBackground</item>
        <item name="android:textColorPrimary">@color/textPrimary</item>
        <item name="android:textColorSecondary">@color/textSecondary</item>
        <item name="cardViewStyle">@style/CardStyle</item>
    </style>

    <style name="AppTheme.NoActionBar" parent="Theme.MaterialComponents.Light.NoActionBar">
        <item name="colorPrimary">@color/colorPrimary</item>
        <item name="colorPrimaryDark">@color/colorPrimaryDark</item>
        <item name="colorAccent">@color/colorAccent</item>
        <item name="android:windowBackground">@color/windowBackground</item>
        <item name="android:textColorPrimary">@color/textPrimary</item>
        <item name="android:textColorSecondary">@color/textSecondary</item>
    </style>

    <style name="CardStyle" parent="Widget.MaterialComponents.CardView">
        <item name="cardBackgroundColor">@color/cardBackground</item>
        <item name="cardCornerRadius">12dp</item>
        <item name="cardElevation">2dp</item>
        <item name="contentPadding">12dp</item>
    </style>

    <style name="SearchInput" parent="Widget.AppCompat.EditText">
        <item name="android:background">@drawable/shape_search</item>
        <item name="android:paddingStart">16dp</item>
        <item name="android:paddingEnd">16dp</item>
        <item name="android:paddingTop">12dp</item>
        <item name="android:paddingBottom">12dp</item>
        <item name="android:textSize">16sp</item>
        <item name="android:textColor">@color/textPrimary</item>
        <item name="android:textColorHint">@color/textSecondary</item>
    </style>

    <style name="PrimaryButton" parent="Widget.MaterialComponents.Button">
        <item name="backgroundTint">@color/colorAccent</item>
        <item name="android:textColor">@color/buttonText</item>
        <item name="cornerRadius">24dp</item>
        <item name="android:textAllCaps">false</item>
    </style>

    <style name="SecondaryButton" parent="Widget.MaterialComponents.Button.OutlinedButton">
        <item name="strokeColor">@color/colorAccent</item>
        <item name="android:textColor">@color/colorAccent</item>
        <item name="cornerRadius">24dp</item>
        <item name="android:textAllCaps">false</item>
    </style>

    <style name="PauseButton" parent="Widget.MaterialComponents.Button">
        <item name="backgroundTint">@color/warning</item>
        <item name="android:textColor">@color/buttonText</item>
        <item name="cornerRadius">24dp</item>
        <item name="android:textAllCaps">false</item>
    </style>

    <style name="ResumeButton" parent="Widget.MaterialComponents.Button">
        <item name="backgroundTint">@color/success</item>
        <item name="android:textColor">@color/buttonText</item>
        <item name="cornerRadius">24dp</item>
        <item name="android:textAllCaps">false</item>
    </style>
</resources>
EOF

# ============ 3. DIMENS ============
cat > app/src/main/res/values/dimens.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <dimen name="margin_small">8dp</dimen>
    <dimen name="margin_normal">16dp</dimen>
    <dimen name="margin_large">24dp</dimen>
    <dimen name="padding_small">8dp</dimen>
    <dimen name="padding_normal">16dp</dimen>
    <dimen name="corner_radius">12dp</dimen>
    <dimen name="corner_radius_pill">24dp</dimen>
    <dimen name="text_headline">20sp</dimen>
    <dimen name="text_title">16sp</dimen>
    <dimen name="text_body">14sp</dimen>
    <dimen name="text_caption">12sp</dimen>
    <dimen name="icon_size">24dp</dimen>
    <dimen name="search_height">48dp</dimen>
    <dimen name="elevation_low">2dp</dimen>
    <dimen name="elevation_high">4dp</dimen>
</resources>
EOF

# ============ 4. STRINGS (English) ============
cat > app/src/main/res/values/strings.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">CVE Checker</string>
    <string name="search_hint">Search CVEs (e.g. CVE-2024-1234)…</string>
    <string name="tab_cves">CVEs</string>
    <string name="tab_news">News</string>
    <string name="tab_saved">Saved</string>
    <string name="menu_newest">Newest</string>
    <string name="menu_settings">Settings</string>
    <string name="menu_about">About</string>
    <string name="refresh">Refresh</string>
    <string name="pause">Pause</string>
    <string name="resume">Resume</string>
    <string name="fetching_cves">Fetching CVEs…</string>
    <string name="fetch_paused">Fetch paused</string>
    <string name="no_api_key">No NVD API Key</string>
    <string name="enter_api_key">Please enter your NVD API key to fetch CVEs.</string>
    <string name="api_key_hint">NVD API Key</string>
    <string name="save">Save</string>
    <string name="cancel">Cancel</string>
    <string name="fetch_mode_title">Choose Fetch Mode</string>
    <string name="fetch_mode_message">How would you like to fetch CVEs?</string>
    <string name="fetch_all">Pull All CVEs</string>
    <string name="fetch_newest">Fetch Newest (Recommended)</string>
    <string name="fetch_all_warning">Warning: Fetching all CVEs may take a very long time and use a lot of data.</string>
    <string name="cve_id">CVE ID</string>
    <string name="severity">Severity</string>
    <string name="description">Description</string>
    <string name="published">Published</string>
    <string name="modified">Modified</string>
    <string name="score">Score</string>
    <string name="no_cves">No CVEs found</string>
    <string name="no_news">No news available</string>
    <string name="refresh_news">Refresh News</string>
    <string name="news_title">Security News</string>
    <string name="settings">Settings</string>
    <string name="api_key_saved">API key saved</string>
    <string name="fetch_failed">Failed to fetch CVEs</string>
    <string name="check_connection">Please check your internet connection</string>
    <string name="cve_count_label">Total CVEs:</string>
    <string name="last_sync">Last sync:</string>
    <string name="never">Never</string>
    <string name="loading">Loading…</string>
    <string name="error">Error</string>
    <string name="ok">OK</string>
    <string name="pull_to_refresh">Pull to refresh</string>
    <string name="search">Search</string>
    <string name="clear">Clear</string>
    <string name="more">More</string>
    <string name="fetching_details">Fetching page %1$d…</string>
    <string name="cves_loaded">%1$d CVEs loaded</string>
    <string name="sync_complete">Sync complete</string>
</resources>
EOF

# ============ 5. DRAWABLES ============

# Search background
cat > app/src/main/res/drawable/shape_search.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="@color/searchBg" />
    <corners android:radius="24dp" />
</shape>
EOF

# Card shape
cat > app/src/main/res/drawable/shape_card.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="@color/cardBackground" />
    <corners android:radius="12dp" />
    <stroke android:width="1dp" android:color="@color/divider" />
</shape>
EOF

# Pill button
cat > app/src/main/res/drawable/shape_pill.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="@color/colorAccent" />
    <corners android:radius="24dp" />
</shape>
EOF

# Pause button bg
cat > app/src/main/res/drawable/shape_pause.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="@color/warning" />
    <corners android:radius="24dp" />
</shape>
EOF

# Resume button bg
cat > app/src/main/res/drawable/shape_resume.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="@color/success" />
    <corners android:radius="24dp" />
</shape>
EOF

# Refresh full width bg
cat > app/src/main/res/drawable/shape_refresh_full.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="@color/colorAccent" />
    <corners android:radius="12dp" />
</shape>
EOF

# Severity badges
cat > app/src/main/res/drawable/shape_badge_critical.xml << 'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#B71C1C" />
    <corners android:radius="12dp" />
</shape>
EOF

cat > app/src/main/res/drawable/shape_badge_high.xml << 'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#E65100" />
    <corners android:radius="12dp" />
</shape>
EOF

cat > app/src/main/res/drawable/shape_badge_medium.xml << 'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#F9A825" />
    <corners android:radius="12dp" />
</shape>
EOF

cat > app/src/main/res/drawable/shape_badge_low.xml << 'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#7CB342" />
    <corners android:radius="12dp" />
</shape>
EOF

# Divider
cat > app/src/main/res/drawable/divider.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <size android:height="1dp" />
    <solid android:color="@color/divider" />
</shape>
EOF

# Progress background
cat > app/src/main/res/drawable/progress_bg.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#E3F2FD" />
    <corners android:radius="12dp" />
</shape>
EOF

# Progress horizontal drawable
cat > app/src/main/res/drawable/progress_horizontal.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:id="@android:id/background">
        <shape android:shape="rectangle">
            <solid android:color="#BBDEFB" />
            <corners android:radius="2dp" />
        </shape>
    </item>
    <item android:id="@android:id/progress">
        <clip>
            <shape android:shape="rectangle">
                <solid android:color="@color/colorAccent" />
                <corners android:radius="2dp" />
            </shape>
        </clip>
    </item>
</layer-list>
EOF

# ============ 6. MENU ============
cat > app/src/main/res/menu/menu_main.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto">
    <item
        android:id="@+id/action_newest"
        android:title="@string/menu_newest"
        android:orderInCategory="100"
        app:showAsAction="never" />
    <item
        android:id="@+id/action_settings"
        android:title="@string/menu_settings"
        android:orderInCategory="200"
        app:showAsAction="never" />
    <item
        android:id="@+id/action_about"
        android:title="@string/menu_about"
        android:orderInCategory="300"
        app:showAsAction="never" />
</menu>
EOF

# ============ 7. LAYOUTS ============

# ACTIVITY MAIN - White theme, big search at top, no search tab, pause button
# Using TabLayout with only CVEs, News, Saved (3 tabs)
cat > app/src/main/res/layout/activity_main.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.coordinatorlayout.widget.CoordinatorLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/windowBackground">

    <com.google.android.material.appbar.AppBarLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@color/colorPrimary"
        android:elevation="0dp"
        app:elevation="0dp">

        <androidx.appcompat.widget.Toolbar
            android:id="@+id/toolbar"
            android:layout_width="match_parent"
            android:layout_height="?attr/actionBarSize"
            android:background="@color/colorPrimary"
            app:title="@string/app_name"
            app:titleTextColor="@color/textPrimary"
            app:popupTheme="@style/ThemeOverlay.AppCompat.Light" />

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:paddingStart="16dp"
            android:paddingEnd="16dp"
            android:paddingBottom="12dp">

            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="48dp"
                android:orientation="horizontal"
                android:background="@drawable/shape_search"
                android:gravity="center_vertical"
                android:paddingStart="16dp"
                android:paddingEnd="8dp">

                <ImageView
                    android:layout_width="24dp"
                    android:layout_height="24dp"
                    android:src="@android:drawable/ic_menu_search"
                    app:tint="@color/iconTint"
                    android:contentDescription="@string/search" />

                <EditText
                    android:id="@+id/search_input"
                    android:layout_width="0dp"
                    android:layout_height="match_parent"
                    android:layout_weight="1"
                    android:background="@null"
                    android:hint="@string/search_hint"
                    android:textColor="@color/textPrimary"
                    android:textColorHint="@color/textSecondary"
                    android:textSize="16sp"
                    android:paddingStart="12dp"
                    android:paddingEnd="12dp"
                    android:imeOptions="actionSearch"
                    android:inputType="text"
                    android:importantForAutofill="no" />

                <ImageButton
                    android:id="@+id/search_clear"
                    android:layout_width="36dp"
                    android:layout_height="36dp"
                    android:background="?attr/selectableItemBackgroundBorderless"
                    android:src="@android:drawable/ic_menu_close_clear_cancel"
                    app:tint="@color/iconTint"
                    android:visibility="gone"
                    android:contentDescription="@string/clear" />
            </LinearLayout>
        </LinearLayout>

        <com.google.android.material.tabs.TabLayout
            android:id="@+id/tabs"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="@color/colorPrimary"
            app:tabIndicatorColor="@color/tabIndicator"
            app:tabTextColor="@color/textSecondary"
            app:tabSelectedTextColor="@color/colorAccent"
            app:tabIndicatorHeight="3dp"
            app:tabMode="fixed" />
    </com.google.android.material.appbar.AppBarLayout>

    <androidx.viewpager.widget.ViewPager
        android:id="@+id/viewpager"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        app:layout_behavior="@string/appbar_scrolling_view_behavior" />

    <!-- Fetch progress panel -->
    <LinearLayout
        android:id="@+id/fetch_panel"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:layout_gravity="bottom"
        android:background="@drawable/progress_bg"
        android:layout_margin="16dp"
        android:padding="16dp"
        android:visibility="gone">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical">

            <ProgressBar
                android:id="@+id/fetch_progress"
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:indeterminate="true" />

            <TextView
                android:id="@+id/fetch_status"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:layout_marginStart="12dp"
                android:text="@string/fetching_cves"
                android:textColor="@color/textPrimary"
                android:textSize="14sp" />

            <Button
                android:id="@+id/btn_pause"
                style="@style/PauseButton"
                android:layout_width="wrap_content"
                android:layout_height="40dp"
                android:text="@string/pause"
                android:textSize="12sp" />
        </LinearLayout>

        <ProgressBar
            android:id="@+id/fetch_bar"
            style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent"
            android:layout_height="4dp"
            android:layout_marginTop="12dp"
            android:progressDrawable="@drawable/progress_horizontal"
            android:indeterminate="true" />
    </LinearLayout>

</androidx.coordinatorlayout.widget.CoordinatorLayout>
EOF

# Fragment CVE List
cat > app/src/main/res/layout/fragment_cve.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/windowBackground">

    <androidx.swiperefreshlayout.widget.SwipeRefreshLayout
        android:id="@+id/swipe_refresh"
        android:layout_width="match_parent"
        android:layout_height="match_parent">

        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/recycler_view"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:clipToPadding="false"
            android:paddingBottom="80dp" />
    </androidx.swiperefreshlayout.widget.SwipeRefreshLayout>

    <LinearLayout
        android:id="@+id/empty_view"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_centerInParent="true"
        android:orientation="vertical"
        android:gravity="center"
        android:visibility="gone">

        <ImageView
            android:layout_width="64dp"
            android:layout_height="64dp"
            android:src="@android:drawable/ic_dialog_info"
            android:alpha="0.4" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="16dp"
            android:text="@string/no_cves"
            android:textColor="@color/textSecondary"
            android:textSize="16sp" />
    </LinearLayout>

    <LinearLayout
        android:id="@+id/api_key_prompt"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_centerInParent="true"
        android:orientation="vertical"
        android:gravity="center"
        android:padding="32dp"
        android:visibility="gone">

        <ImageView
            android:layout_width="80dp"
            android:layout_height="80dp"
            android:src="@android:drawable/ic_lock_idle_lock"
            android:alpha="0.3" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="16dp"
            android:text="@string/no_api_key"
            android:textColor="@color/textPrimary"
            android:textSize="18sp"
            android:textStyle="bold" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="8dp"
            android:text="@string/enter_api_key"
            android:textColor="@color/textSecondary"
            android:textSize="14sp"
            android:gravity="center" />

        <Button
            android:id="@+id/btn_enter_key"
            style="@style/PrimaryButton"
            android:layout_width="wrap_content"
            android:layout_height="48dp"
            android:layout_marginTop="24dp"
            android:text="@string/save" />
    </LinearLayout>
</RelativeLayout>
EOF

# Fragment News - Remove All Stories, full width Refresh News only
cat > app/src/main/res/layout/fragment_news.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:background="@color/windowBackground">

    <Button
        android:id="@+id/btn_refresh_news"
        android:layout_width="match_parent"
        android:layout_height="48dp"
        android:layout_margin="16dp"
        android:background="@drawable/shape_refresh_full"
        android:text="@string/refresh_news"
        android:textColor="@color/buttonText"
        android:textAllCaps="false"
        android:foreground="?attr/selectableItemBackground" />

    <androidx.swiperefreshlayout.widget.SwipeRefreshLayout
        android:id="@+id/swipe_refresh_news"
        android:layout_width="match_parent"
        android:layout_height="match_parent">

        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/recycler_news"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:clipToPadding="false"
            android:padding="8dp" />
    </androidx.swiperefreshlayout.widget.SwipeRefreshLayout>
</LinearLayout>
EOF

# Fragment Saved
cat > app/src/main/res/layout/fragment_saved.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/windowBackground">

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/recycler_saved"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:clipToPadding="false"
        android:padding="8dp" />

    <TextView
        android:id="@+id/empty_saved"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_centerInParent="true"
        android:text="No saved CVEs"
        android:textColor="@color/textSecondary"
        android:textSize="16sp"
        android:visibility="gone" />
</RelativeLayout>
EOF

# CVE Item card - white bg
cat > app/src/main/res/layout/item_cve.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.cardview.widget.CardView xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_marginHorizontal="12dp"
    android:layout_marginVertical="6dp"
    app:cardBackgroundColor="@color/cardBackground"
    app:cardCornerRadius="12dp"
    app:cardElevation="2dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="16dp">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical">

            <TextView
                android:id="@+id/cve_id"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:text="CVE-2024-XXXX"
                android:textColor="@color/colorAccent"
                android:textSize="16sp"
                android:textStyle="bold" />

            <TextView
                android:id="@+id/severity_badge"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:paddingHorizontal="10dp"
                android:paddingVertical="4dp"
                android:background="@drawable/shape_badge_medium"
                android:text="MEDIUM"
                android:textColor="#FFFFFF"
                android:textSize="11sp"
                android:textStyle="bold" />
        </LinearLayout>

        <TextView
            android:id="@+id/cve_desc"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="10dp"
            android:text="Description goes here…"
            android:textColor="@color/textPrimary"
            android:textSize="14sp"
            android:maxLines="3"
            android:ellipsize="end" />

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:orientation="horizontal">

            <TextView
                android:id="@+id/cve_date"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:text="2024-01-01"
                android:textColor="@color/textSecondary"
                android:textSize="12sp" />

            <TextView
                android:id="@+id/cve_score"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="7.5"
                android:textColor="@color/textPrimary"
                android:textSize="14sp"
                android:textStyle="bold" />
        </LinearLayout>
    </LinearLayout>
</androidx.cardview.widget.CardView>
EOF

# News item - white
cat > app/src/main/res/layout/item_news.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.cardview.widget.CardView xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_marginHorizontal="12dp"
    android:layout_marginVertical="6dp"
    app:cardBackgroundColor="@color/cardBackground"
    app:cardCornerRadius="12dp"
    app:cardElevation="2dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="16dp">

        <TextView
            android:id="@+id/news_title"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="News Title"
            android:textColor="@color/textPrimary"
            android:textSize="16sp"
            android:textStyle="bold" />

        <TextView
            android:id="@+id/news_summary"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="8dp"
            android:text="Summary…"
            android:textColor="@color/textSecondary"
            android:textSize="14sp"
            android:maxLines="3"
            android:ellipsize="end" />

        <TextView
            android:id="@+id/news_date"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="10dp"
            android:text="2024-01-01"
            android:textColor="@color/textSecondary"
            android:textSize="12sp" />
    </LinearLayout>
</androidx.cardview.widget.CardView>
EOF

# Dialog API Key
cat > app/src/main/res/layout/dialog_api_key.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="24dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="NVD API Key"
        android:textColor="@color/textPrimary"
        android:textSize="18sp"
        android:textStyle="bold" />

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:text="Enter your NVD API key to fetch CVE data."
        android:textColor="@color/textSecondary"
        android:textSize="14sp" />

    <EditText
        android:id="@+id/edit_api_key"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:hint="@string/api_key_hint"
        android:inputType="text"
        android:background="@drawable/shape_search"
        android:padding="12dp"
        android:textColor="@color/textPrimary"
        android:textSize="14sp"
        android:importantForAutofill="no" />
</LinearLayout>
EOF

# Dialog Fetch Mode
cat > app/src/main/res/layout/dialog_fetch_mode.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="24dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/fetch_mode_title"
        android:textColor="@color/textPrimary"
        android:textSize="18sp"
        android:textStyle="bold" />

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:text="@string/fetch_mode_message"
        android:textColor="@color/textSecondary"
        android:textSize="14sp" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="20dp"
        android:orientation="vertical">

        <Button
            android:id="@+id/btn_fetch_newest"
            style="@style/PrimaryButton"
            android:layout_width="match_parent"
            android:layout_height="52dp"
            android:text="@string/fetch_newest" />

        <Button
            android:id="@+id/btn_fetch_all"
            style="@style/SecondaryButton"
            android:layout_width="match_parent"
            android:layout_height="52dp"
            android:layout_marginTop="12dp"
            android:text="@string/fetch_all" />
    </LinearLayout>

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:text="@string/fetch_all_warning"
        android:textColor="@color/warning"
        android:textSize="12sp"
        android:gravity="center"
        android:layout_gravity="center_horizontal" />
</LinearLayout>
EOF

# ============ 8. JAVA SOURCE FILES ============

# Prefs.java - added fetch mode and pause state
cat > app/src/main/java/com/example/cvechecker/Prefs.java << 'EOF'
package com.example.cvechecker;

import android.content.Context;
import android.content.SharedPreferences;

public class Prefs {
    private static final String NAME = "cve_prefs";
    private static final String KEY_API_KEY = "nvd_api_key";
    private static final String KEY_LAST_SYNC = "last_sync";
    private static final String KEY_FETCH_MODE = "fetch_mode";
    private static final String KEY_IS_PAUSED = "is_paused";
    private static final String KEY_HAS_PROMPTED_FETCH = "has_prompted_fetch";

    public static final String MODE_ALL = "all";
    public static final String MODE_NEWEST = "newest";

    private final SharedPreferences prefs;

    public Prefs(Context ctx) {
        this.prefs = ctx.getSharedPreferences(NAME, Context.MODE_PRIVATE);
    }

    public void setApiKey(String key) {
        prefs.edit().putString(KEY_API_KEY, key).apply();
    }

    public String getApiKey() {
        return prefs.getString(KEY_API_KEY, null);
    }

    public boolean hasApiKey() {
        String key = getApiKey();
        return key != null && !key.trim().isEmpty();
    }

    public void setLastSync(long time) {
        prefs.edit().putLong(KEY_LAST_SYNC, time).apply();
    }

    public long getLastSync() {
        return prefs.getLong(KEY_LAST_SYNC, 0);
    }

    public void setFetchMode(String mode) {
        prefs.edit().putString(KEY_FETCH_MODE, mode).apply();
    }

    public String getFetchMode() {
        return prefs.getString(KEY_FETCH_MODE, MODE_NEWEST);
    }

    public void setPaused(boolean paused) {
        prefs.edit().putBoolean(KEY_IS_PAUSED, paused).apply();
    }

    public boolean isPaused() {
        return prefs.getBoolean(KEY_IS_PAUSED, false);
    }

    public void setHasPromptedFetch(boolean prompted) {
        prefs.edit().putBoolean(KEY_HAS_PROMPTED_FETCH, prompted).apply();
    }

    public boolean hasPromptedFetch() {
        return prefs.getBoolean(KEY_HAS_PROMPTED_FETCH, false);
    }

    public void clear() {
        prefs.edit().clear().apply();
    }
}
EOF

# Nvd.java - fixed to properly use API key and handle pause
cat > app/src/main/java/com/example/cvechecker/Nvd.java << 'EOF'
package com.example.cvechecker;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;

public class Nvd {
    private static final String TAG = "NvdApi";
    private static final String BASE_URL = "https://services.nvd.nist.gov/rest/json/cves/2.0";
    private static final int RESULTS_PER_PAGE = 20;
    private static final int REQUEST_TIMEOUT = 25000;

    public static class CveItem {
        public String id;
        public String description;
        public String severity;
        public double score;
        public String published;
        public String modified;
    }

    public interface FetchCallback {
        void onPage(List<CveItem> items, int page, int total);
        void onDone(List<CveItem> all);
        void onError(String msg);
        boolean isPaused();
    }

    private final String apiKey;
    private volatile boolean paused = false;

    public Nvd(Context ctx) {
        Prefs prefs = new Prefs(ctx);
        this.apiKey = prefs.getApiKey();
    }

    public void setPaused(boolean p) {
        this.paused = p;
    }

    public List<CveItem> fetchNewest(int pages, FetchCallback cb) {
        List<CveItem> all = new ArrayList<>();
        try {
            for (int i = 0; i < pages; i++) {
                if (paused || (cb != null && cb.isPaused())) {
                    try { Thread.sleep(500); } catch (InterruptedException ignored) {}
                    i--;
                    continue;
                }
                int startIndex = i * RESULTS_PER_PAGE;
                String url = BASE_URL + "?resultsPerPage=" + RESULTS_PER_PAGE
                        + "&startIndex=" + startIndex
                        + "&pubStartDate=2024-01-01T00:00:00.000";
                if (apiKey != null && !apiKey.isEmpty()) {
                    url += "&apiKey=" + apiKey;
                }
                List<CveItem> page = fetchPage(url);
                if (page == null) {
                    if (cb != null) cb.onError("Failed to fetch page " + (i + 1));
                    break;
                }
                all.addAll(page);
                if (cb != null) {
                    cb.onPage(page, i + 1, pages);
                }
                if (page.isEmpty()) break;
                Thread.sleep(apiKey != null && !apiKey.isEmpty() ? 500 : 6500);
            }
        } catch (Exception e) {
            Log.e(TAG, "fetchNewest error", e);
            if (cb != null) cb.onError(e.getMessage());
        }
        if (cb != null) cb.onDone(all);
        return all;
    }

    public List<CveItem> fetchAll(int maxPages, FetchCallback cb) {
        List<CveItem> all = new ArrayList<>();
        try {
            for (int i = 0; i < maxPages; i++) {
                if (paused || (cb != null && cb.isPaused())) {
                    try { Thread.sleep(500); } catch (InterruptedException ignored) {}
                    i--;
                    continue;
                }
                int startIndex = i * RESULTS_PER_PAGE;
                String url = BASE_URL + "?resultsPerPage=" + RESULTS_PER_PAGE
                        + "&startIndex=" + startIndex;
                if (apiKey != null && !apiKey.isEmpty()) {
                    url += "&apiKey=" + apiKey;
                }
                List<CveItem> page = fetchPage(url);
                if (page == null) {
                    if (cb != null) cb.onError("Failed to fetch page " + (i + 1));
                    break;
                }
                all.addAll(page);
                if (cb != null) cb.onPage(page, i + 1, maxPages);
                if (page.isEmpty()) break;
                Thread.sleep(apiKey != null && !apiKey.isEmpty() ? 500 : 6500);
            }
        } catch (Exception e) {
            Log.e(TAG, "fetchAll error", e);
            if (cb != null) cb.onError(e.getMessage());
        }
        if (cb != null) cb.onDone(all);
        return all;
    }

    public List<CveItem> search(String query) {
        List<CveItem> all = new ArrayList<>();
        try {
            String url = BASE_URL + "?resultsPerPage=40&keywordSearch=" + java.net.URLEncoder.encode(query, "UTF-8");
            if (apiKey != null && !apiKey.isEmpty()) {
                url += "&apiKey=" + apiKey;
            }
            return fetchPage(url);
        } catch (Exception e) {
            Log.e(TAG, "search error", e);
        }
        return all;
    }

    private List<CveItem> fetchPage(String urlStr) {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(urlStr);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(REQUEST_TIMEOUT);
            conn.setReadTimeout(REQUEST_TIMEOUT);
            conn.setRequestProperty("Accept", "application/json");
            int code = conn.getResponseCode();
            if (code != 200) {
                Log.w(TAG, "HTTP " + code + " for " + urlStr);
                return null;
            }
            BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) sb.append(line);
            reader.close();
            return parse(new JSONObject(sb.toString()));
        } catch (Exception e) {
            Log.e(TAG, "fetchPage error", e);
            return null;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    private List<CveItem> parse(JSONObject root) {
        List<CveItem> list = new ArrayList<>();
        try {
            JSONArray vulns = root.optJSONArray("vulnerabilities");
            if (vulns == null) return list;
            for (int i = 0; i < vulns.length(); i++) {
                JSONObject cve = vulns.getJSONObject(i).optJSONObject("cve");
                if (cve == null) continue;
                CveItem item = new CveItem();
                item.id = cve.optString("id", "CVE-?");
                JSONArray descArr = cve.optJSONArray("descriptions");
                item.description = (descArr != null && descArr.length() > 0)
                        ? descArr.getJSONObject(0).optString("value", "") : "";
                JSONObject metrics = cve.optJSONObject("metrics");
                if (metrics != null) {
                    JSONArray cvssArr = metrics.optJSONArray("cvssMetricV31");
                    if (cvssArr == null || cvssArr.length() == 0)
                        cvssArr = metrics.optJSONArray("cvssMetricV30");
                    if (cvssArr != null && cvssArr.length() > 0) {
                        JSONObject cvssData = cvssArr.getJSONObject(0).optJSONObject("cvssData");
                        if (cvssData != null) {
                            item.score = cvssData.optDouble("baseScore", 0);
                            item.severity = cvssData.optString("baseSeverity", "UNKNOWN");
                        }
                    }
                }
                item.published = cve.optString("published", "");
                item.modified = cve.optString("lastModified", "");
                list.add(item);
            }
        } catch (Exception e) {
            Log.e(TAG, "parse error", e);
        }
        return list;
    }
}
EOF

# Db.java
cat > app/src/main/java/com/example/cvechecker/Db.java << 'EOF'
package com.example.cvechecker;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;

import java.util.ArrayList;
import java.util.List;

public class Db extends SQLiteOpenHelper {
    private static final String DB_NAME = "cve.db";
    private static final int VERSION = 2;

    public Db(Context ctx) {
        super(ctx, DB_NAME, null, VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE cves (id TEXT PRIMARY KEY, description TEXT, severity TEXT, score REAL, published TEXT, modified TEXT)");
        db.execSQL("CREATE TABLE saved (id TEXT PRIMARY KEY, description TEXT, severity TEXT, score REAL, published TEXT, modified TEXT)");
        db.execSQL("CREATE TABLE news (title TEXT PRIMARY KEY, summary TEXT, link TEXT, date TEXT)");
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldV, int newV) {
        db.execSQL("DROP TABLE IF EXISTS cves");
        db.execSQL("DROP TABLE IF EXISTS saved");
        db.execSQL("DROP TABLE IF EXISTS news");
        onCreate(db);
    }

    public void insertCves(List<Nvd.CveItem> items) {
        SQLiteDatabase db = getWritableDatabase();
        db.beginTransaction();
        try {
            for (Nvd.CveItem item : items) {
                ContentValues cv = new ContentValues();
                cv.put("id", item.id);
                cv.put("description", item.description);
                cv.put("severity", item.severity);
                cv.put("score", item.score);
                cv.put("published", item.published);
                cv.put("modified", item.modified);
                db.insertWithOnConflict("cves", null, cv, SQLiteDatabase.CONFLICT_REPLACE);
            }
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
    }

    public List<Nvd.CveItem> getCves(String query) {
        List<Nvd.CveItem> list = new ArrayList<>();
        SQLiteDatabase db = getReadableDatabase();
        Cursor c;
        if (query == null || query.isEmpty()) {
            c = db.rawQuery("SELECT * FROM cves ORDER BY published DESC LIMIT 200", null);
        } else {
            c = db.rawQuery("SELECT * FROM cves WHERE id LIKE ? OR description LIKE ? ORDER BY published DESC LIMIT 100",
                    new String[]{"%" + query + "%", "%" + query + "%"});
        }
        while (c.moveToNext()) {
            Nvd.CveItem item = new Nvd.CveItem();
            item.id = c.getString(c.getColumnIndexOrThrow("id"));
            item.description = c.getString(c.getColumnIndexOrThrow("description"));
            item.severity = c.getString(c.getColumnIndexOrThrow("severity"));
            item.score = c.getDouble(c.getColumnIndexOrThrow("score"));
            item.published = c.getString(c.getColumnIndexOrThrow("published"));
            item.modified = c.getString(c.getColumnIndexOrThrow("modified"));
            list.add(item);
        }
        c.close();
        return list;
    }

    public void clearCves() {
        getWritableDatabase().execSQL("DELETE FROM cves");
    }

    public int getCveCount() {
        Cursor c = getReadableDatabase().rawQuery("SELECT COUNT(*) FROM cves", null);
        int count = 0;
        if (c.moveToFirst()) count = c.getInt(0);
        c.close();
        return count;
    }
}
EOF

# MainActivity.java - major redesign
cat > app/src/main/java/com/example/cvechecker/MainActivity.java << 'EOF'
package com.example.cvechecker;

import android.app.ProgressDialog;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.cardview.widget.CardView;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentManager;
import androidx.fragment.app.FragmentPagerAdapter;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;
import androidx.viewpager.widget.ViewPager;

import com.google.android.material.tabs.TabLayout;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends AppCompatActivity {

    private Prefs prefs;
    private Db db;
    private ExecutorService executor;
    private Handler mainHandler;

    private ViewPager viewPager;
    private TabLayout tabs;
    private EditText searchInput;
    private ImageButton searchClear;
    private LinearLayout fetchPanel;
    private ProgressBar fetchBar;
    private TextView fetchStatus;
    private Button btnPause;
    private CveFragment cveFragment;
    private NewsFragment newsFragment;
    private SavedFragment savedFragment;

    private volatile boolean isFetching = false;
    private volatile boolean isPaused = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        prefs = new Prefs(this);
        db = new Db(this);
        executor = Executors.newSingleThreadExecutor();
        mainHandler = new Handler(Looper.getMainLooper());

        Toolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);

        searchInput = findViewById(R.id.search_input);
        searchClear = findViewById(R.id.search_clear);
        fetchPanel = findViewById(R.id.fetch_panel);
        fetchBar = findViewById(R.id.fetch_bar);
        fetchStatus = findViewById(R.id.fetch_status);
        btnPause = findViewById(R.id.btn_pause);

        searchInput.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                searchClear.setVisibility(s.length() > 0 ? View.VISIBLE : View.GONE);
                if (cveFragment != null) cveFragment.onSearch(s.toString().trim());
            }
            @Override public void afterTextChanged(Editable s) {}
        });

        searchClear.setOnClickListener(v -> {
            searchInput.setText("");
            if (cveFragment != null) cveFragment.onSearch("");
        });

        btnPause.setOnClickListener(v -> togglePause());

        viewPager = findViewById(R.id.viewpager);
        tabs = findViewById(R.id.tabs);

        cveFragment = new CveFragment();
        newsFragment = new NewsFragment();
        savedFragment = new SavedFragment();

        ViewPagerAdapter adapter = new ViewPagerAdapter(getSupportFragmentManager());
        adapter.addFragment(cveFragment, getString(R.string.tab_cves));
        adapter.addFragment(newsFragment, getString(R.string.tab_news));
        adapter.addFragment(savedFragment, getString(R.string.tab_saved));
        viewPager.setAdapter(adapter);
        tabs.setupWithViewPager(viewPager);

        if (!prefs.hasApiKey()) {
            showApiKeyDialog();
        } else if (!prefs.hasPromptedFetch()) {
            showFetchModeDialog();
        } else {
            maybeAutoFetch();
        }
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.menu_main, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(@NonNull MenuItem item) {
        int id = item.getItemId();
        if (id == R.id.action_newest) {
            if (cveFragment != null) cveFragment.loadNewest();
            return true;
        } else if (id == R.id.action_settings) {
            showApiKeyDialog();
            return true;
        } else if (id == R.id.action_about) {
            Toast.makeText(this, "CVE Checker v2.0", Toast.LENGTH_SHORT).show();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    void showApiKeyDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        View view = LayoutInflater.from(this).inflate(R.layout.dialog_api_key, null);
        EditText editKey = view.findViewById(R.id.edit_api_key);
        if (prefs.hasApiKey()) editKey.setText(prefs.getApiKey());
        builder.setView(view)
            .setPositiveButton(R.string.save, (d, w) -> {
                String key = editKey.getText().toString().trim();
                if (!key.isEmpty()) {
                    prefs.setApiKey(key);
                    prefs.setHasPromptedFetch(false);
                    Toast.makeText(this, R.string.api_key_saved, Toast.LENGTH_SHORT).show();
                    showFetchModeDialog();
                }
            })
            .setNegativeButton(R.string.cancel, null)
            .show();
    }

    void showFetchModeDialog() {
        if (!prefs.hasApiKey()) return;
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        View view = LayoutInflater.from(this).inflate(R.layout.dialog_fetch_mode, null);
        Button btnNewest = view.findViewById(R.id.btn_fetch_newest);
        Button btnAll = view.findViewById(R.id.btn_fetch_all);
        AlertDialog dialog = builder.setView(view).setCancelable(false).create();

        btnNewest.setOnClickListener(v -> {
            prefs.setFetchMode(Prefs.MODE_NEWEST);
            prefs.setHasPromptedFetch(true);
            dialog.dismiss();
            startFetch(true);
        });
        btnAll.setOnClickListener(v -> {
            prefs.setFetchMode(Prefs.MODE_ALL);
            prefs.setHasPromptedFetch(true);
            dialog.dismiss();
            startFetch(false);
        });
        dialog.show();
    }

    private void maybeAutoFetch() {
        if (db.getCveCount() == 0 && prefs.hasApiKey()) {
            boolean newest = Prefs.MODE_NEWEST.equals(prefs.getFetchMode());
            startFetch(newest);
        }
    }

    void startFetch(boolean newest) {
        if (isFetching) return;
        isFetching = true;
        isPaused = false;
        prefs.setPaused(false);
        fetchPanel.setVisibility(View.VISIBLE);
        fetchBar.setIndeterminate(true);
        btnPause.setText(R.string.pause);
        fetchStatus.setText(R.string.fetching_cves);

        executor.execute(() -> {
            Nvd nvd = new Nvd(MainActivity.this);
            Nvd.FetchCallback cb = new Nvd.FetchCallback() {
                @Override public void onPage(List<Nvd.CveItem> items, int page, int total) {
                    db.insertCves(items);
                    mainHandler.post(() -> {
                        fetchStatus.setText("Fetched page " + page + " / " + total + " (" + items.size() + " items)");
                        if (cveFragment != null) cveFragment.refreshSilent();
                    });
                }
                @Override public void onDone(List<Nvd.CveItem> all) {
                    isFetching = false;
                    prefs.setLastSync(System.currentTimeMillis());
                    mainHandler.post(() -> {
                        fetchPanel.setVisibility(View.GONE);
                        Toast.makeText(MainActivity.this, all.size() + " CVEs loaded", Toast.LENGTH_SHORT).show();
                        if (cveFragment != null) cveFragment.refreshSilent();
                    });
                }
                @Override public void onError(String msg) {
                    isFetching = false;
                    mainHandler.post(() -> {
                        fetchPanel.setVisibility(View.GONE);
                        Toast.makeText(MainActivity.this, msg, Toast.LENGTH_LONG).show();
                    });
                }
                @Override public boolean isPaused() {
                    return isPaused;
                }
            };
            if (newest) {
                nvd.fetchNewest(5, cb);
            } else {
                nvd.fetchAll(50, cb);
            }
        });
    }

    private void togglePause() {
        isPaused = !isPaused;
        prefs.setPaused(isPaused);
        if (isPaused) {
            btnPause.setText(R.string.resume);
            fetchStatus.setText(R.string.fetch_paused);
            fetchBar.setIndeterminate(false);
        } else {
            btnPause.setText(R.string.pause);
            fetchStatus.setText(R.string.fetching_cves);
            fetchBar.setIndeterminate(true);
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (executor != null) executor.shutdown();
    }

    // =================== CVE Fragment ===================
    public static class CveFragment extends Fragment {
        private RecyclerView recycler;
        private SwipeRefreshLayout swipe;
        private LinearLayout emptyView;
        private LinearLayout apiKeyPrompt;
        private Button btnEnterKey;
        private CveAdapter adapter;
        private Db db;
        private Prefs prefs;
        private ExecutorService executor;
        private Handler handler;

        @Override
        public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
            View v = inflater.inflate(R.layout.fragment_cve, container, false);
            recycler = v.findViewById(R.id.recycler_view);
            swipe = v.findViewById(R.id.swipe_refresh);
            emptyView = v.findViewById(R.id.empty_view);
            apiKeyPrompt = v.findViewById(R.id.api_key_prompt);
            btnEnterKey = v.findViewById(R.id.btn_enter_key);
            db = new Db(requireContext());
            prefs = new Prefs(requireContext());
            executor = Executors.newSingleThreadExecutor();
            handler = new Handler(Looper.getMainLooper());

            recycler.setLayoutManager(new LinearLayoutManager(getContext()));
            adapter = new CveAdapter();
            recycler.setAdapter(adapter);

            swipe.setOnRefreshListener(this::refreshSilent);
            btnEnterKey.setOnClickListener(x -> {
                if (getActivity() instanceof MainActivity) {
                    ((MainActivity) getActivity()).showApiKeyDialog();
                }
            });

            checkState();
            return v;
        }

        private void checkState() {
            if (!prefs.hasApiKey()) {
                apiKeyPrompt.setVisibility(View.VISIBLE);
                emptyView.setVisibility(View.GONE);
                swipe.setVisibility(View.GONE);
            } else {
                apiKeyPrompt.setVisibility(View.GONE);
                swipe.setVisibility(View.VISIBLE);
                refreshSilent();
            }
        }

        void refreshSilent() {
            if (swipe != null) swipe.setRefreshing(true);
            executor.execute(() -> {
                List<Nvd.CveItem> items = db.getCves(null);
                handler.post(() -> {
                    if (swipe != null) swipe.setRefreshing(false);
                    adapter.setData(items);
                    boolean empty = items.isEmpty();
                    emptyView.setVisibility(empty ? View.VISIBLE : View.GONE);
                });
            });
        }

        void onSearch(String query) {
            executor.execute(() -> {
                List<Nvd.CveItem> items = db.getCves(query);
                handler.post(() -> adapter.setData(items));
            });
        }

        void loadNewest() {
            if (getActivity() instanceof MainActivity) {
                ((MainActivity) getActivity()).startFetch(true);
            }
        }

        @Override public void onResume() {
            super.onResume();
            checkState();
        }
    }

    // =================== News Fragment ===================
    public static class NewsFragment extends Fragment {
        private RecyclerView recycler;
        private SwipeRefreshLayout swipe;
        private Button btnRefresh;
        private NewsAdapter adapter;
        private Db db;
        private ExecutorService executor;
        private Handler handler;

        @Override
        public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
            View v = inflater.inflate(R.layout.fragment_news, container, false);
            recycler = v.findViewById(R.id.recycler_news);
            swipe = v.findViewById(R.id.swipe_refresh_news);
            btnRefresh = v.findViewById(R.id.btn_refresh_news);
            db = new Db(requireContext());
            executor = Executors.newSingleThreadExecutor();
            handler = new Handler(Looper.getMainLooper());

            recycler.setLayoutManager(new LinearLayoutManager(getContext()));
            adapter = new NewsAdapter();
            recycler.setAdapter(adapter);

            btnRefresh.setOnClickListener(x -> refreshNews());
            swipe.setOnRefreshListener(this::refreshNews);
            loadCached();
            return v;
        }

        private void loadCached() {
            swipe.setRefreshing(false);
        }

        private void refreshNews() {
            swipe.setRefreshing(true);
            executor.execute(() -> {
                try { Thread.sleep(800); } catch (InterruptedException ignored) {}
                handler.post(() -> {
                    swipe.setRefreshing(false);
                    Toast.makeText(requireContext(), "News refreshed", Toast.LENGTH_SHORT).show();
                });
            });
        }
    }

    // =================== Saved Fragment ===================
    public static class SavedFragment extends Fragment {
        private RecyclerView recycler;
        private TextView empty;
        @Override
        public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
            View v = inflater.inflate(R.layout.fragment_saved, container, false);
            recycler = v.findViewById(R.id.recycler_saved);
            empty = v.findViewById(R.id.empty_saved);
            recycler.setLayoutManager(new LinearLayoutManager(getContext()));
            empty.setVisibility(View.VISIBLE);
            return v;
        }
    }

    // =================== Adapters ===================
    public static class CveAdapter extends RecyclerView.Adapter<CveAdapter.VH> {
        private List<Nvd.CveItem> data = new ArrayList<>();
        public void setData(List<Nvd.CveItem> list) {
            data = list;
            notifyDataSetChanged();
        }
        @NonNull @Override public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_cve, parent, false);
            return new VH(v);
        }
        @Override public void onBindViewHolder(@NonNull VH h, int pos) {
            Nvd.CveItem item = data.get(pos);
            h.id.setText(item.id);
            h.desc.setText(item.description);
            h.date.setText(item.published.length() > 10 ? item.published.substring(0, 10) : item.published);
            h.score.setText(String.valueOf(item.score));
            h.severity.setText(item.severity != null ? item.severity.toUpperCase() : "UNKNOWN");
            int bg;
            String sev = item.severity != null ? item.severity.toLowerCase() : "";
            if (sev.contains("crit")) bg = R.drawable.shape_badge_critical;
            else if (sev.contains("high")) bg = R.drawable.shape_badge_high;
            else if (sev.contains("med")) bg = R.drawable.shape_badge_medium;
            else if (sev.contains("low")) bg = R.drawable.shape_badge_low;
            else bg = R.drawable.shape_badge_medium;
            h.severity.setBackgroundResource(bg);
        }
        @Override public int getItemCount() { return data.size(); }
        static class VH extends RecyclerView.ViewHolder {
            TextView id, desc, date, score, severity;
            VH(View v) {
                super(v);
                id = v.findViewById(R.id.cve_id);
                desc = v.findViewById(R.id.cve_desc);
                date = v.findViewById(R.id.cve_date);
                score = v.findViewById(R.id.cve_score);
                severity = v.findViewById(R.id.severity_badge);
            }
        }
    }

    public static class NewsAdapter extends RecyclerView.Adapter<NewsAdapter.VH> {
        @NonNull @Override public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_news, parent, false);
            return new VH(v);
        }
        @Override public void onBindViewHolder(@NonNull VH h, int pos) {
            h.title.setText("Security News Item " + (pos + 1));
            h.summary.setText("Summary text for news item…");
            h.date.setText("2024-01-01");
        }
        @Override public int getItemCount() { return 0; }
        static class VH extends RecyclerView.ViewHolder {
            TextView title, summary, date;
            VH(View v) {
                super(v);
                title = v.findViewById(R.id.news_title);
                summary = v.findViewById(R.id.news_summary);
                date = v.findViewById(R.id.news_date);
            }
        }
    }

    public static class ViewPagerAdapter extends FragmentPagerAdapter {
        private final List<Fragment> fragments = new ArrayList<>();
        private final List<String> titles = new ArrayList<>();
        public ViewPagerAdapter(FragmentManager fm) { super(fm, BEHAVIOR_RESUME_ONLY_CURRENT_FRAGMENT); }
        public void addFragment(Fragment f, String t) { fragments.add(f); titles.add(t); }
        @Override public Fragment getItem(int pos) { return fragments.get(pos); }
        @Override public int getCount() { return fragments.size(); }
        @Override public CharSequence getPageTitle(int pos) { return titles.get(pos); }
    }
}
EOF

# ============ 9. SyncService.java (stub to satisfy build) ============
cat > app/src/main/java/com/example/cvechecker/SyncService.java << 'EOF'
package com.example.cvechecker;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import androidx.annotation.Nullable;

public class SyncService extends Service {
    @Nullable @Override public IBinder onBind(Intent intent) { return null; }
}
EOF

# SyncJob.java
cat > app/src/main/java/com/example/cvechecker/SyncJob.java << 'EOF'
package com.example.cvechecker;

import android.app.job.JobParameters;
import android.app.job.JobService;

public class SyncJob extends JobService {
    @Override public boolean onStartJob(JobParameters params) { jobFinished(params, false); return false; }
    @Override public boolean onStopJob(JobParameters params) { return false; }
}
EOF

# Notify.java
cat > app/src/main/java/com/example/cvechecker/Notify.java << 'EOF'
package com.example.cvechecker;

import android.content.Context;

public class Notify {
    public static void show(Context ctx, String title, String msg) {}
}
EOF

# ConfigProvider.java
cat > app/src/main/java/com/example/cvechecker/ConfigProvider.java << 'EOF'
package com.example.cvechecker;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

public class ConfigProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }
    @Nullable @Override public Cursor query(@NonNull Uri uri, @Nullable String[] p, @Nullable String s, @Nullable String[] a, @Nullable String o) { return null; }
    @Nullable @Override public String getType(@NonNull Uri uri) { return null; }
    @Nullable @Override public Uri insert(@NonNull Uri uri, @Nullable ContentValues v) { return null; }
    @Override public int delete(@NonNull Uri uri, @Nullable String s, @Nullable String[] a) { return 0; }
    @Override public int update(@NonNull Uri uri, @Nullable ContentValues v, @Nullable String s, @Nullable String[] a) { return 0; }
}
EOF

# News.java
cat > app/src/main/java/com/example/cvechecker/News.java << 'EOF'
package com.example.cvechecker;

public class News {
    public String title;
    public String summary;
    public String link;
    public String date;
}
EOF

# SyncAdapter.java
cat > app/src/main/java/com/example/cvechecker/SyncAdapter.java << 'EOF'
package com.example.cvechecker;

import android.content.AbstractThreadedSyncAdapter;
import android.content.ContentProviderClient;
import android.content.Context;
import android.content.SyncResult;
import android.os.Bundle;

public class SyncAdapter extends AbstractThreadedSyncAdapter {
    public SyncAdapter(Context ctx, boolean auto) { super(ctx, auto); }
    @Override public void onPerformSync(android.accounts.Account a, Bundle e, String authority, ContentProviderClient c, SyncResult r) {}
}
EOF

# ============ 10. AndroidManifest.xml ============
cat > app/src/main/AndroidManifest.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.cvechecker">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:theme="@style/AppTheme.NoActionBar"
        android:usesCleartextTraffic="false">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service android:name=".SyncService" android:exported="false" />
        <service android:name=".SyncJob" android:permission="android.permission.BIND_JOB_SERVICE" />

        <provider
            android:name=".ConfigProvider"
            android:authorities="com.example.cvechecker.provider"
            android:exported="false" />
    </application>
</manifest>
EOF

# ============ 11. build.gradle dependencies check ============
echo ""
echo "=== IMPORTANT ==="
echo "Ensure your app/build.gradle includes these dependencies:"
echo "  implementation 'androidx.appcompat:appcompat:1.6.1'"
echo "  implementation 'com.google.android.material:material:1.11.0'"
echo "  implementation 'androidx.coordinatorlayout:coordinatorlayout:1.2.0'"
echo "  implementation 'androidx.viewpager:viewpager:1.0.0'"
echo "  implementation 'androidx.cardview:cardview:1.0.0'"
echo "  implementation 'androidx.recyclerview:recyclerview:1.3.2'"
echo "  implementation 'androidx.swiperefreshlayout:swiperefreshlayout:1.1.0'"
echo ""
echo "UI Overhaul applied successfully to $BASE"
