package it.pviotti.readeck

import android.content.Context
import android.util.Log
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import org.json.JSONObject

internal const val CREDENTIALS_FILE = "readeck_share_creds"
private const val PREFS_CHANNEL = "it.pviotti.readeck/prefs"
private const val TAG = "ReadeckCredentials"

private fun buildMasterKey(context: Context): MasterKey =
    MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

private fun buildEncryptedFile(context: Context, file: File): EncryptedFile =
    EncryptedFile.Builder(
        context,
        file,
        buildMasterKey(context),
        EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB,
    ).build()

internal fun readShareCredentials(context: Context): Pair<String, String>? {
    return try {
        val credsFile = File(context.filesDir, CREDENTIALS_FILE)
        if (!credsFile.exists()) {
            Log.d(TAG, "No credentials file found")
            return null
        }
        val content = buildEncryptedFile(context, credsFile)
            .openFileInput()
            .use { it.readBytes().toString(Charsets.UTF_8) }
        val json = JSONObject(content)
        val baseUrl = json.optString("baseUrl").takeIf { it.isNotEmpty() } ?: return null
        val accessToken = json.optString("accessToken").takeIf { it.isNotEmpty() } ?: return null
        Log.d(TAG, "Credentials read from encrypted file")
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
                    val baseUrl = call.argument<String>("baseUrl").orEmpty().trim()
                    val accessToken = call.argument<String>("accessToken").orEmpty().trim()
                    if (baseUrl.isEmpty() || accessToken.isEmpty()) {
                        result.error(
                            "INVALID_ARGUMENTS",
                            "baseUrl and accessToken must be non-empty",
                            null,
                        )
                    } else {
                        try {
                            saveCredentials(baseUrl, accessToken)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", "Failed to save credentials", e.message)
                        }
                    }
                }

                "clearCredentials" -> {
                    try {
                        clearCredentials()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CLEAR_FAILED", "Failed to clear credentials", e.message)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun saveCredentials(baseUrl: String, accessToken: String) {
        val credsFile = File(filesDir, CREDENTIALS_FILE)
        // EncryptedFile cannot overwrite an existing file; delete first.
        if (credsFile.exists()) credsFile.delete()
        val json = JSONObject().apply {
            put("baseUrl", baseUrl)
            put("accessToken", accessToken)
        }
        buildEncryptedFile(this, credsFile)
            .openFileOutput()
            .use { it.write(json.toString().toByteArray(Charsets.UTF_8)) }
        Log.d(TAG, "Credentials saved to encrypted file")
    }

    private fun clearCredentials() {
        val credsFile = File(filesDir, CREDENTIALS_FILE)
        if (credsFile.exists()) {
            credsFile.delete()
            Log.d(TAG, "Credentials cleared")
        }
    }
}
