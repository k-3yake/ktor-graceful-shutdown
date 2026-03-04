package com.example

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

fun assertGracefulShutdown(server: TestableServer) {
    server.start()
    val port = server.actualPort

    val responseFuture = CompletableFuture.supplyAsync {
        val conn = URI("http://localhost:$port/slow").toURL().openConnection() as HttpURLConnection
        conn.connectTimeout = 30_000
        conn.readTimeout = 30_000
        conn.responseCode
    }

    Thread.sleep(2_000)
    server.stop()

    val statusCode = responseFuture.get(30, TimeUnit.SECONDS)
    assertEquals(200, statusCode)
}

class GracefulShutdownTest {

    @Test
    fun `Netty公式パターンでインフライトリクエストが正常完了する`() {
        assertGracefulShutdown(NettyHttpServer())
    }

    @Test
    fun `Ktor3_4_0相当の順序でインフライトリクエストが正常完了する`() {
        assertGracefulShutdown(NettyHttpServerNearKtor3_4_0())
    }
}
