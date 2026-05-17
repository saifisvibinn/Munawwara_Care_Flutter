package com.munawwaracare.andriod

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log

/**
 * Opens manufacturer-specific "autostart" / battery screens when available.
 * Falls back to the app details page in system settings.
 */
object OemSettingsHelper {

    private const val TAG = "OemSettingsHelper"

    fun isBatteryUnrestricted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(context.packageName)) return true
        if (isMiuiFamily()) return isMiuiBatteryUnrestricted(context)
        return false
    }

    private fun isMiuiFamily(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        return manufacturer.contains("xiaomi") ||
            manufacturer.contains("redmi") ||
            manufacturer.contains("poco") ||
            brand.contains("xiaomi") ||
            brand.contains("redmi") ||
            brand.contains("poco")
    }

    /** Best-effort read of MIUI per-app "No restrictions" (not Doze whitelist). */
    private fun isMiuiBatteryUnrestricted(context: Context): Boolean {
        try {
            val clazz = Class.forName("android.miui.AppOpsUtils")
            val method = clazz.getMethod(
                "getApplicationBatteryOptimization",
                Context::class.java,
                String::class.java,
            )
            val code = method.invoke(null, context, context.packageName) as? Int
            if (code != null) {
                Log.d(TAG, "MIUI getApplicationBatteryOptimization=$code")
                // Documented on several MIUI builds: 1 = no restrictions.
                if (code == 1) return true
            }
        } catch (e: Exception) {
            Log.d(TAG, "MIUI battery optimization probe failed", e)
        }
        return false
    }

    fun deviceOemHaystack(): String {
        val brand = Build.BRAND.orEmpty().lowercase()
        val manufacturer = Build.MANUFACTURER.orEmpty().lowercase()
        val model = Build.MODEL.orEmpty().lowercase()
        return "$brand $manufacturer $model"
    }

    fun openAutostartSettings(context: Context): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val candidates = buildList {
            when {
                manufacturer.contains("xiaomi") ||
                    manufacturer.contains("redmi") ||
                    manufacturer.contains("poco") -> {
                    add(
                        componentIntent(
                            "com.miui.securitycenter",
                            "com.miui.permcenter.autostart.AutoStartManagementActivity",
                        ),
                    )
                }
                manufacturer.contains("huawei") ||
                    manufacturer.contains("honor") -> {
                    add(
                        componentIntent(
                            "com.huawei.systemmanager",
                            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                        ),
                    )
                    add(
                        componentIntent(
                            "com.huawei.systemmanager",
                            "com.huawei.systemmanager.optimize.process.ProtectActivity",
                        ),
                    )
                }
                manufacturer.contains("oppo") ||
                    manufacturer.contains("realme") ||
                    manufacturer.contains("oneplus") -> {
                    add(
                        componentIntent(
                            "com.coloros.safecenter",
                            "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                        ),
                    )
                    add(
                        componentIntent(
                            "com.oppo.safe",
                            "com.oppo.safe.permission.startup.StartupAppListActivity",
                        ),
                    )
                }
                manufacturer.contains("vivo") ||
                    manufacturer.contains("iqoo") -> {
                    add(
                        componentIntent(
                            "com.vivo.permissionmanager",
                            "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                        ),
                    )
                    add(
                        componentIntent(
                            "com.iqoo.secure",
                            "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                        ),
                    )
                }
                manufacturer.contains("meizu") -> {
                    add(
                        componentIntent(
                            "com.meizu.safe",
                            "com.meizu.safe.security.SHOW_APPSEC",
                        ),
                    )
                }
            }
        }

        for (intent in candidates) {
            if (tryStart(context, intent)) return true
        }
        return openAppDetails(context)
    }

    fun openBatterySettings(context: Context): Boolean {
        val pkg = context.packageName

        // System dialog stays in-app and dismisses on Allow (best auto-return UX).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$pkg")
            }
            if (tryStart(context, direct)) return true
        }

        // App info → Battery → Unrestricted (One UI / AOSP AdvancedPowerUsageDetail).
        if (openAppBatteryUsageDetail(context, pkg)) return true

        val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        if (tryStart(context, list)) return true

        if (openAppDetails(context)) return true

        Log.w(TAG, "openBatterySettings: all intents failed for $pkg")
        return false
    }

    /**
     * Opens the per-app battery screen (Unrestricted / Optimized / Restricted),
     * same as tapping Battery on the app's Settings page.
     */
    private fun openAppBatteryUsageDetail(context: Context, pkg: String): Boolean {
        val uid = packageUid(context, pkg) ?: return false

        val settingsHosts = listOf(
            "com.android.settings",
            "com.samsung.android.settings",
        )
        val detailActivities = listOf(
            "com.android.settings.fuelgauge.AdvancedPowerUsageDetailActivity",
            "com.android.settings.Settings\$AdvancedPowerUsageDetailActivity",
            "com.samsung.android.settings.fuelgauge.AdvancedPowerUsageDetailActivity",
        )

        for (host in settingsHosts) {
            for (activity in detailActivities) {
                val intent = Intent().apply {
                    component = ComponentName(host, activity)
                    data = Uri.parse("package:$pkg")
                    putExtra("extra_package_name", pkg)
                    putExtra("extra_uid", uid)
                    putExtra("android.intent.extra.PACKAGE_NAME", pkg)
                    putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                    putExtra("request_ignore_background_restriction", true)
                }
                if (tryStart(context, intent)) {
                    Log.i(TAG, "Opened app battery detail: $host/$activity")
                    return true
                }
            }
        }

        if (isSamsung()) {
            if (openSamsungAppInfoBatterySubpage(context, pkg, uid)) return true
            if (openSamsungLegacyBatteryDetail(context, pkg, uid)) return true
        }
        return false
    }

    /**
     * One UI: jump into App info → Battery (not just the top of App info).
     */
    private fun openSamsungAppInfoBatterySubpage(
        context: Context,
        pkg: String,
        uid: Int,
    ): Boolean {
        val batteryFragments = listOf(
            "com.samsung.android.settings.applications.appinfo.AppInfoBatteryCategory",
            "com.samsung.android.settings.applications.appinfo.AppInfoBatteryFragment",
            "com.android.settings.applications.appinfo.AppBatteryPreferenceController",
            "com.android.settings.fuelgauge.AdvancedPowerUsageDetail",
        )
        val hosts = listOf(
            "com.android.settings",
            "com.samsung.android.settings",
        )

        for (host in hosts) {
            for (fragment in batteryFragments) {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", pkg, null)
                    setPackage(host)
                    putExtra(":settings:fragment_args_key", pkg)
                    putExtra(":settings:show_fragment_title", true)
                    putExtra(":settings:fragment", fragment)
                    putExtra("extra_package_name", pkg)
                    putExtra("extra_uid", uid)
                    putExtra("app_uid", uid)
                }
                if (tryStart(context, intent)) {
                    Log.i(TAG, "Opened Samsung app-info battery subpage: $host/$fragment")
                    return true
                }
            }
        }
        return false
    }

    /** Older Samsung builds / Device Care battery UI. */
    private fun openSamsungLegacyBatteryDetail(
        context: Context,
        pkg: String,
        uid: Int,
    ): Boolean {
        val hosts = listOf(
            "com.samsung.android.lool",
            "com.samsung.android.sm",
        )
        val activities = listOf(
            "com.samsung.android.sm.ui.battery.BatteryDetailActivity",
            "com.samsung.android.sm.ui.battery.AppDetailsSettingsActivity",
            "com.samsung.android.sm.ui.battery.BatteryActivity",
            "com.samsung.android.sm.battery.ui.BatteryDetailActivity",
        )

        for (host in hosts) {
            for (activity in activities) {
                val intent = componentIntent(host, activity).apply {
                    data = Uri.parse("package:$pkg")
                    putExtra("package_name", pkg)
                    putExtra("packageName", pkg)
                    putExtra("package", pkg)
                    putExtra("app_package", pkg)
                    putExtra("app_uid", uid)
                    putExtra("uid", uid)
                    putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                }
                if (tryStart(context, intent)) {
                    Log.i(TAG, "Opened Samsung legacy battery: $host/$activity")
                    return true
                }
            }
        }
        return false
    }

    private fun isSamsung(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        return manufacturer.contains("samsung") || brand.contains("samsung")
    }

    private fun packageUid(context: Context, pkg: String): Int? {
        return try {
            context.packageManager.getPackageUid(pkg, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    /**
     * Opens the per-app permission screen (MIUI/HyperOS editor, etc.), not only
     * the top-level App info page.
     */
    fun openLocationPermissionSettings(context: Context): Boolean {
        val pkg = context.packageName
        val manufacturer = Build.MANUFACTURER.lowercase()

        val candidates = buildList {
            add(
                Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                    setClassName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.permissions.PermissionsEditorActivity",
                    )
                    putExtra("extra_pkgname", pkg)
                },
            )
            add(
                componentIntent(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity",
                ).apply {
                    putExtra("extra_pkgname", pkg)
                },
            )
            add(
                componentIntent(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.AppPermissionsEditorActivity",
                ).apply {
                    putExtra("extra_pkgname", pkg)
                },
            )
            if (manufacturer.contains("oppo") ||
                manufacturer.contains("realme") ||
                manufacturer.contains("oneplus")
            ) {
                add(
                    componentIntent(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.permission.PermissionAppAllPermissionActivity",
                    ).apply {
                        putExtra("packageName", pkg)
                    },
                )
            }
            if (manufacturer.contains("vivo") || manufacturer.contains("iqoo")) {
                add(
                    componentIntent(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.SoftPermissionDetailActivity",
                    ).apply {
                        putExtra("packagename", pkg)
                        putExtra("tabId", "1")
                    },
                )
            }
        }

        for (intent in candidates) {
            if (tryStart(context, intent)) {
                Log.i(TAG, "Opened location permission settings for $pkg")
                return true
            }
        }
        return openAppDetails(context)
    }

    /**
     * Full-screen incoming calls on lock screen: Android 14+ intent plus OEM
     * permission editors (MIUI "Show on lock screen", etc.).
     */
    fun openLockScreenCallSettings(context: Context): Boolean {
        val pkg = context.packageName

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val fullScreen = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:$pkg")
            }
            if (tryStart(context, fullScreen)) {
                Log.i(TAG, "Opened full-screen intent settings for $pkg")
                return true
            }
        }

        if (isMiuiFamily()) {
            val miuiCandidates = listOf(
                Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                    setClassName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.permissions.PermissionsEditorActivity",
                    )
                    putExtra("extra_pkgname", pkg)
                },
                componentIntent(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.AppPermissionsEditorActivity",
                ).apply {
                    putExtra("extra_pkgname", pkg)
                },
            )
            for (intent in miuiCandidates) {
                if (tryStart(context, intent)) {
                    Log.i(TAG, "Opened MIUI lock-screen permission editor for $pkg")
                    return true
                }
            }
        }

        if (openNotificationSettings(context)) return true
        return openAppDetails(context)
    }

    fun openNotificationSettings(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            }
            if (tryStart(context, intent)) return true
        }
        return openAppDetails(context)
    }

    fun openAppDetails(context: Context): Boolean {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
        }
        return tryStart(context, intent)
    }

    private fun componentIntent(pkg: String, cls: String): Intent {
        return Intent().setComponent(ComponentName(pkg, cls))
    }

    private fun tryStart(context: Context, intent: Intent): Boolean {
        val launch = Intent(intent)
        if (context !is Activity) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            if (launch.resolveActivity(context.packageManager) == null) {
                false
            } else {
                context.startActivity(launch)
                true
            }
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "ActivityNotFound: ${launch.component ?: launch.action}", e)
            false
        } catch (e: Exception) {
            Log.w(TAG, "startActivity failed: ${launch.component ?: launch.action}", e)
            false
        }
    }
}
