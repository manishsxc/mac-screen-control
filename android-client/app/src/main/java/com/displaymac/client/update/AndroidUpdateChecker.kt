package com.displaymac.client.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

data class AndroidUpdateInfo(
    val latestVersion: String,
    val downloadUrl: String,
    val releaseNotes: String
)

object AndroidUpdateChecker {
    private const val TAG = "UpdateChecker"
    const val CURRENT_VERSION = "1.0.0"
    const val REPO_OWNER = "sumitkumar"
    const val REPO_NAME = "DisplayMac"

    suspend fun checkForUpdates(): AndroidUpdateInfo? = withContext(Dispatchers.IO) {
        try {
            val url = URL("https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest")
            val conn = url.openConnection() as HttpURLConnection
            conn.setRequestProperty("User-Agent", "DisplayMac-Android-Updater")
            conn.connectTimeout = 5000
            conn.readTimeout = 5000

            if (conn.responseCode == 200) {
                val response = conn.inputStream.bufferedReader().use { it.readText() }
                val json = JSONObject(response)
                val tagName = json.getString("tag_name").replace("v", "").trim()

                if (isNewerVersion(tagName, CURRENT_VERSION)) {
                    val htmlUrl = json.optString("html_url", "https://github.com/$REPO_OWNER/$REPO_NAME/releases")
                    val body = json.optString("body", "New version available!")
                    return@withContext AndroidUpdateInfo(tagName, htmlUrl, body)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Update check failed: ${e.message}")
        }
        return@withContext null
    }

    fun openUpdatePage(context: Context, url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(intent)
    }

    private fun isNewerVersion(remote: String, current: String): Boolean {
        val remoteParts = remote.split(".").mapNotNull { it.toIntOrNull() }
        val currentParts = current.split(".").mapNotNull { it.toIntOrNull() }

        val length = maxOf(remoteParts.size, currentParts.size)
        for (i in 0 until length) {
            val r = remoteParts.getOrElse(i) { 0 }
            val c = currentParts.getOrElse(i) { 0 }
            if (r > c) return true
            if (r < c) return false
        }
        return false
    }
}
