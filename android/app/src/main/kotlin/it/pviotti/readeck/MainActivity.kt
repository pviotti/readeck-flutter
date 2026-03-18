package it.pviotti.readeck

import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import org.json.JSONObject

internal const val CREDENTIALS_FILE = "readeck_share_creds"
private const val PREFS_CHANNEL = "it.pviotti.readeck/prefs"
private const val TAG = "ReadeckCredentials"

internal fun readShareCredentials(context: Context): Pair<String, String>? {
    return try {
        val credsFile = File(context.filesDir, CREDENTIALS_FILE)
        if (!credsFile.exists()) {
            Log.d(TAG, "No credentials file found")
            return null
        }
        val json = JSONObject(credsFile.readText())
        val baseUrl = json.optString("baseUrl").takeIf { it.isNotEmpty() } ?: return null
        val accessToken = json.optString("accessToken").takeIf { it.isNotEmpty() } ?: return null
        Log.d(TAG, "Credentials read from private file")
        Pair(baseUrl, accessToken)
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read credentials", e)
        null
    }
}

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PREFS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveCredentials" -> {
                    val baseUrl = call.argument<String>("baseUrl") ?: ""
                    val accessToken = call.argument<String>("accessToken") ?: ""
                    saveCredentials(baseUrl, accessToken)
                    result.success(null)
                }

                "clearCredentials" -> {
                    clearCredentials()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun saveCredentials(baseUrl: String, accessToken: String) {
        try {
            val credsFile = File(filesDir, CREDENTIALS_FILE)
            val json = JSONObject().apply {
                put("baseUrl", baseUrl)
                put("accessToken", accessToken)
            }
            credsFile.writeText(json.toString())
            credsFile.setReadable(false, false)
            credsFile.setWritable(false, false)
            credsFile.setReadable(true, true)
            credsFile.setWritable(true, true)
            Log.d(TAG, "Credentials saved to private file")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save credentials", e)
        }
    }

    private fun clearCredentials() {
        try {
            val credsFile = File(filesDir, CREDENTIALS_FILE)
            if (credsFile.exists()) {
                credsFile.delete()
                Log.d(TAG, "Credentials cleared")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear credentials", e)
        }
    }
}
