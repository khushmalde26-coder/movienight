package com.khush.movienight.core

/** Object-based surround: sound placed around and above you rather than in fixed channels. */
enum class SpatialAudio(val badge: String, val spoken: String) {
    ATMOS("Atmos", "Dolby Atmos"),
    DTS_X("DTS:X", "DTS:X");

    companion object {
        private val atmosName = Regex("""(?i)\batmos\b""")
        private val dtsXName = Regex("""(?i)\bdts[ :-]?x\b""")

        /**
         * Release names often say so ("…DDP5.1.Atmos", "…TrueHD.7.1.Atmos", "…DTS-X…"): the fallback when
         * the soundtrack itself doesn't tell (TrueHD Atmos and Blu-ray DTS:X can't be read on Android).
         */
        fun fromFileName(fileName: String): SpatialAudio? {
            val text = fileName.replace(Regex("[._]"), " ")
            return when {
                atmosName.containsMatchIn(text) -> ATMOS
                dtsXName.containsMatchIn(text) -> DTS_X
                else -> null
            }
        }

        /** Media3's names for the object-based formats it recognises. */
        fun fromMimeType(mimeType: String?): SpatialAudio? = when {
            mimeType == null -> null
            mimeType.startsWith("audio/eac3-joc") -> ATMOS
            mimeType.startsWith("audio/vnd.dts.uhd") && mimeType.contains("profile=p2") -> DTS_X
            else -> null
        }
    }
}
