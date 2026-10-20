package com.khush.movienight

import com.khush.movienight.core.SpatialAudio
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SpatialAudioTest {
    @Test fun fallsBackToReleaseNames() {
        assertEquals(SpatialAudio.ATMOS, SpatialAudio.fromFileName("Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.mkv"))
        assertEquals(SpatialAudio.ATMOS, SpatialAudio.fromFileName("Top Gun Maverick (2022) TrueHD 7.1 Atmos.mkv"))
        assertEquals(SpatialAudio.DTS_X, SpatialAudio.fromFileName("Oppenheimer.2023.DTS-X.mkv"))
        assertNull(SpatialAudio.fromFileName("Atmosphere.mkv"))
        assertNull(SpatialAudio.fromFileName("Heat (1995).mkv"))
    }

    @Test fun readsMedia3FormatNames() {
        assertEquals(SpatialAudio.ATMOS, SpatialAudio.fromMimeType("audio/eac3-joc"))
        assertEquals(SpatialAudio.DTS_X, SpatialAudio.fromMimeType("audio/vnd.dts.uhd;profile=p2"))
        assertNull(SpatialAudio.fromMimeType("audio/eac3"))
        assertNull(SpatialAudio.fromMimeType(null))
    }
}
