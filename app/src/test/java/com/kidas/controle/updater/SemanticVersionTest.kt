package com.kidas.controle.updater

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SemanticVersionTest {
    @Test fun comparesNumericSegmentsNotAlphabetically() {
        assertTrue(SemanticVersion.isNewer("1.0.10", "1.0.9"))
        assertFalse(SemanticVersion.isNewer("1.0.9", "1.0.10"))
    }
    @Test fun equalAndOlderVersionsAreNotUpdates() {
        assertEquals(0, SemanticVersion.compare("v1.2.3", "1.2.3"))
        assertFalse(SemanticVersion.isNewer("1.2.3", "1.2.3"))
        assertFalse(SemanticVersion.isNewer("1.2.2", "1.2.3"))
    }
    @Test fun semverPrereleaseHasLowerPrecedence() {
        assertTrue(SemanticVersion.isNewer("1.2.3", "1.2.3-rc.1"))
        assertTrue(SemanticVersion.isNewer("1.2.3-rc.2", "1.2.3-rc.1"))
        assertFalse(SemanticVersion.isNewer("1.2.3-rc.1", "1.2.3"))
    }
}
