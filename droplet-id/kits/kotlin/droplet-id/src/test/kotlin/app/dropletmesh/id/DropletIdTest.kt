package app.dropletmesh.id

import org.junit.Assert.assertEquals
import org.junit.Test

class DropletIdTest {
    @Test
    fun `openid est toujours demandé`() {
        assertEquals(listOf("openid", "profile"), DropletId.avecOpenid(listOf("profile")))
        assertEquals(listOf("openid"), DropletId.avecOpenid(listOf("openid")))
    }
}
