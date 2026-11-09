package info.typikon.cs

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "info.typikon.cs/scripture")
            .setMethodCallHandler { call, result ->
                if (call.method != "openScripture") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val raw = call.argument<String>("url")
                val uri = raw?.let { Uri.parse(it) }
                if (uri == null || uri.scheme != "https" || uri.host != "www.typikon.info" ||
                    !uri.userInfo.isNullOrEmpty() ||
                    !Regex("^/bible/[a-z0-9-]+/[1-9][0-9]*$").matches(uri.path ?: "")) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri)
                        .addCategory(Intent.CATEGORY_BROWSABLE)
                        .setPackage("su.typikon.typikon"))
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                } catch (_: SecurityException) {
                    result.success(false)
                }
            }
    }
}
