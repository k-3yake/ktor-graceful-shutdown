package com.example

import io.netty.bootstrap.ServerBootstrap
import io.netty.channel.*
import io.netty.channel.nio.NioEventLoopGroup
import io.netty.channel.socket.SocketChannel
import io.netty.channel.socket.nio.NioServerSocketChannel
import io.netty.handler.codec.http.*
import java.net.InetSocketAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Ktor 3.4.0 の NettyApplicationEngine.stop() に近い順序でシャットダウンする。
 *
 * Ktor 3.4.0 の stop():
 *   1. サーバーチャネルを同期クローズ
 *   2. connectionEventGroup.shutdownGracefully(0, timeout) ← awaitせず
 *   3. workerEventGroup.shutdownGracefully(gracePeriod, timeout) ← 同時に開始
 *   4. 両方の完了を待機
 *   5. callEventGroup.shutdownGracefully(0, timeout)
 *
 * Netty単独での対応:
 *   connectionEventGroup → bossGroup
 *   workerEventGroup → workerGroup
 *   callEventGroup → callExecutor
 */
class NettyHttpServerNearKtor3_4_0(private val port: Int = 0) : TestableServer {

    private val bossGroup = NioEventLoopGroup(1)
    private val workerGroup = NioEventLoopGroup(1)
    private val callExecutor: ExecutorService = Executors.newFixedThreadPool(4)
    private var serverChannel: Channel? = null

    override val actualPort: Int
        get() = (serverChannel?.localAddress() as? InetSocketAddress)?.port
            ?: throw IllegalStateException("Server not started")

    override fun start() {
        val bootstrap = ServerBootstrap()
            .group(bossGroup, workerGroup)
            .channel(NioServerSocketChannel::class.java)
            .childHandler(object : ChannelInitializer<SocketChannel>() {
                override fun initChannel(ch: SocketChannel) {
                    ch.pipeline().addLast(
                        HttpServerCodec(),
                        HttpObjectAggregator(65536),
                        RequestHandler(callExecutor)
                    )
                }
            })

        serverChannel = bootstrap.bind(port).sync().channel()
    }

    override fun stop(gracePeriodSeconds: Long, timeoutSeconds: Long) {
        // ステップ1: サーバーチャネルを同期クローズ
        serverChannel?.close()?.sync()

        // ステップ2-3: bossとworkerを同時にシャットダウン開始（awaitしない）
        val shutdownBoss = bossGroup.shutdownGracefully(0, timeoutSeconds, TimeUnit.SECONDS)
        val shutdownWorker = workerGroup.shutdownGracefully(gracePeriodSeconds, timeoutSeconds, TimeUnit.SECONDS)

        // ステップ4: 両方の完了を待機
        shutdownBoss.sync()
        shutdownWorker.sync()

        // ステップ5: callExecutorを最後にシャットダウン
        callExecutor.shutdown()
        callExecutor.awaitTermination(timeoutSeconds, TimeUnit.SECONDS)
    }

    override fun printState(label: String) {
        println("=== [$label] NettyHttpServerNearKtor3_4_0 内部状態 ===")
        printEventLoopGroupState("bossGroup", bossGroup)
        printEventLoopGroupState("workerGroup", workerGroup)
        println("=== [$label] END ===")
    }
}
