package com.example

import io.netty.bootstrap.ServerBootstrap
import io.netty.channel.*
import io.netty.channel.nio.NioEventLoopGroup
import io.netty.channel.socket.SocketChannel
import io.netty.channel.socket.nio.NioServerSocketChannel
import io.netty.handler.codec.http.*
import java.net.InetSocketAddress
import java.util.concurrent.TimeUnit

class NettyHttpServer(private val port: Int = 0) : TestableServer {

    private val bossGroup = NioEventLoopGroup(1)
    private val workerGroup = NioEventLoopGroup()
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
                        RequestHandler()
                    )
                }
            })

        serverChannel = bootstrap.bind(port).sync().channel()
    }

    override fun stop(gracePeriodSeconds: Long, timeoutSeconds: Long) {
        serverChannel?.close()?.sync()
        workerGroup.shutdownGracefully(gracePeriodSeconds, timeoutSeconds, TimeUnit.SECONDS)
        bossGroup.shutdownGracefully(gracePeriodSeconds, timeoutSeconds, TimeUnit.SECONDS)
    }
}
