package com.example

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.fail
import org.junit.jupiter.api.Test
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit

fun sendSlowRequest(port: Int): CompletableFuture<Int> {
    return CompletableFuture.supplyAsync {
        val conn = URI("http://localhost:$port/slow").toURL().openConnection() as HttpURLConnection
        conn.connectTimeout = 30_000
        conn.readTimeout = 30_000
        conn.responseCode
    }
}

class GracefulShutdownTest {

    @Test
    fun `Netty公式パターンでインフライトリクエストが正常完了する`() {
        val server = NettyHttpServer()
        server.start()
        val port = server.actualPort

        val responseFuture = sendSlowRequest(port)
        Thread.sleep(2_000)
        server.stop()

        val statusCode = responseFuture.get(30, TimeUnit.SECONDS)
        assertEquals(200, statusCode)
    }

    @Test
    fun `Ktor3_4_0相当の順序ではインフライトリクエストが中断される`() {
        val server = NettyHttpServerNearKtor3_4_0()
        server.start()
        val port = server.actualPort

        val responseFuture = sendSlowRequest(port)
        Thread.sleep(2_000)
        server.stop()

        try {
            val statusCode = responseFuture.get(30, TimeUnit.SECONDS)
            fail("グレースフルシャットダウンが成功してしまった (HTTP $statusCode)。" +
                "Ktor 3.4.0相当の順序ではworkerGroupのシャットダウンにより" +
                "チャネルが即座にクローズされ、リクエストが中断されるはず")
        } catch (e: ExecutionException) {
            // 期待通り: workerGroup.shutdownGracefully() がチャネルを即座にクローズし、
            // callExecutor上のハンドラがレスポンスを返す前にコネクションが切断される
            println("期待通りリクエストが中断された: ${e.cause?.message}")
        }
    }
}
