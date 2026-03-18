package it.pviotti.readeck

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

private const val TAG = "ReadeckShare"

class ShareHandlerActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val sharedText = extractSharedText() ?: run {
            finish()
            return
        }

        val url = extractFirstUrl(sharedText)
        if (url == null) {
            Toast.makeText(this, "No valid URL found in shared content.", Toast.LENGTH_SHORT)
                .show()
            finish()
            return
        }

        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()

        Log.d(TAG, "Share intent received: url=$url, subject=$subject")

        val credentials = readShareCredentials(this)
        if (credentials == null) {
            Log.d(TAG, "No credentials found")
            Toast.makeText(this, "Sign in to Readeck first.", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        val (baseUrl, accessToken) = credentials
        Log.d(TAG, "Credentials found: baseUrl=$baseUrl")

        Thread {
            val success =
                try {
                    Log.d(TAG, "Posting bookmark to $baseUrl/api/bookmarks")
                    postBookmark(baseUrl, accessToken, url, subject)
                    true
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to post bookmark", e)
                    false
                }

            runOnUiThread {
                val message =
                    if (success) "Bookmark sent to Readeck."
                    else "Failed to save the bookmark."
                Log.d(TAG, message)
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
                finish()
            }
        }.start()
    }

    private fun extractSharedText(): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent?.type?.startsWith("text/") != true) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun postBookmark(
        baseUrl: String,
        accessToken: String,
        url: String,
        title: String?,
    ) {
        val connection = URL("$baseUrl/api/bookmarks").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.setRequestProperty("Authorization", "Bearer $accessToken")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.doOutput = true
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000

            val body =
                JSONObject().apply {
                    put("url", url)
                    if (!title.isNullOrBlank()) put("title", title)
                }

            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(body.toString())
            }

            val statusCode = connection.responseCode
            Log.d(TAG, "POST /bookmarks response: $statusCode")
            if (statusCode != 202) throw RuntimeException("Unexpected status: $statusCode")
        } finally {
            connection.disconnect()
        }
    }

    private fun extractFirstUrl(text: String): String? {
        val regex = Regex("https?://\\S+", RegexOption.IGNORE_CASE)
        for (match in regex.findAll(text)) {
            val candidate = sanitizeUrl(match.value)
            val uri = runCatching { URI(candidate) }.getOrNull() ?: continue
            if (uri.scheme == "http" || uri.scheme == "https") return candidate
        }
        return null
    }

    private fun sanitizeUrl(candidate: String): String {
        val trailingChars = ".,!?;:)]}'\""
        var result = candidate.trim()
        while (result.isNotEmpty() && result.last() in trailingChars)
            result = result.dropLast(1)
        return result
    }
}
