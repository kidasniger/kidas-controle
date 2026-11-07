package com.kidas.controle.updater

/**
 * SemVer comparison for release tags, including optional v-prefix and prerelease identifiers.
 * Build metadata is ignored, as required by SemVer 2.0.0.
 */
object SemanticVersion {
    private val pattern = Regex("""^[vV]?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$""")

    fun compare(left: String, right: String): Int {
        val a = parse(left)
        val b = parse(right)
        for (i in 0..2) {
            val c = a.core[i].compareTo(b.core[i])
            if (c != 0) return c
        }
        if (a.pre.isEmpty() && b.pre.isEmpty()) return 0
        if (a.pre.isEmpty()) return 1
        if (b.pre.isEmpty()) return -1
        val count = maxOf(a.pre.size, b.pre.size)
        for (i in 0 until count) {
            if (i >= a.pre.size) return -1
            if (i >= b.pre.size) return 1
            val x = a.pre[i]
            val y = b.pre[i]
            val xn = x.toLongOrNull()
            val yn = y.toLongOrNull()
            val c = when {
                xn != null && yn != null -> xn.compareTo(yn)
                xn != null -> -1
                yn != null -> 1
                else -> x.compareTo(y)
            }
            if (c != 0) return c
        }
        return 0
    }

    fun isNewer(remote: String, installed: String): Boolean = compare(remote, installed) > 0

    private data class Parsed(val core: List<Long>, val pre: List<String>)

    private fun parse(raw: String): Parsed {
        val match = pattern.matchEntire(raw.trim())
            ?: throw IllegalArgumentException("Version sémantique invalide : $raw")
        return Parsed(
            listOf(match.groupValues[1].toLong(), match.groupValues[2].toLong(), match.groupValues[3].toLong()),
            match.groupValues[4].takeIf(String::isNotEmpty)?.split(".") ?: emptyList()
        )
    }
}
