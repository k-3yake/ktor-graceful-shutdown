package com.example

import io.netty.bootstrap.ServerBootstrap
import io.netty.channel.*
import io.netty.channel.nio.NioEventLoopGroup
import io.netty.channel.socket.SocketChannel
import io.netty.channel.socket.nio.NioServerSocketChannel
import io.netty.handler.codec.http.*
import io.netty.util.concurrent.SingleThreadEventExecutor
import java.net.InetSocketAddress
import java.nio.channels.Selector
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class NettyHttpServer(private val port: Int = 0) : TestableServer {

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
        // 1. 新規接続の受付を停止
        serverChannel?.close()?.sync()
        // 2. アプリケーションロジックの完了を待つ
        callExecutor.shutdown()
        callExecutor.awaitTermination(timeoutSeconds, TimeUnit.SECONDS)
        // 3. worker/bossをシャットダウン
        workerGroup.shutdownGracefully(gracePeriodSeconds, timeoutSeconds, TimeUnit.SECONDS)
        bossGroup.shutdownGracefully(gracePeriodSeconds, timeoutSeconds, TimeUnit.SECONDS)
    }

    override fun printState(label: String) {
        println("=== [$label] NettyHttpServer 内部状態 ===")
        printEventLoopGroupState("bossGroup", bossGroup)
        printEventLoopGroupState("workerGroup", workerGroup)
        println("=== [$label] END ===")
    }
}
