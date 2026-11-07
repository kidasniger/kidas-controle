package com.kidas.controle.updater

import org.json.JSONObject

data class GitHubReleaseInfo(
    val tagName: String,
    val name: String?,
    val body: String,
    val publishedAt: String?,
    val htmlUrl: String,
    val apkName: String,
    val apkUrl: String,
    val apkSize: Long,
    val sha256: String?,
    val checksumUrl: String?
) {
    companion object {
        fun fromJson(json: JSONObject): GitHubReleaseInfo {
            val assets = json.optJSONArray("assets")
            var apk: JSONObject? = null
            var checksum: JSONObject? = null
            if (assets != null) for (i in 0 until assets.length()) {
                val item = assets.optJSONObject(i) ?: continue
                val name = item.optString("name")
                if (name.endsWith(".apk", true) && apk == null) apk = item
                if ((name.endsWith(".sha256", true) || name.equals("SHA256SUMS.txt", true)) && checksum == null) checksum = item
            }
            val selected = requireNotNull(apk) { "La dernière release ne contient aucun APK installable." }
            return GitHubReleaseInfo(
                tagName = json.optString("tag_name"),
                name = json.optString("name").takeIf(String::isNotBlank),
                body = json.optString("body"),
                publishedAt = json.optString("published_at").takeIf(String::isNotBlank),
                htmlUrl = json.optString("html_url"),
                apkName = selected.optString("name"),
                apkUrl = selected.optString("browser_download_url"),
                apkSize = selected.optLong("size"),
                sha256 = selected.optString("digest").removePrefix("sha256:").takeIf { it.matches(Regex("[a-fA-F0-9]{64}")) },
                checksumUrl = checksum?.optString("browser_download_url")?.takeIf(String::isNotBlank)
            )
        }
    }
}

sealed interface UpdateState {
    data object Idle : UpdateState
    data object Checking : UpdateState
    data class UpdateAvailable(val release: GitHubReleaseInfo, val installedVersion: String) : UpdateState
    data class UpToDate(val installedVersion: String) : UpdateState
    data class Error(val message: String) : UpdateState
    data class Downloading(val percent: Int, val received: Long, val total: Long) : UpdateState
    data class Downloaded(val apkPath: String, val version: String) : UpdateState
    data class Installing(val version: String) : UpdateState
}
