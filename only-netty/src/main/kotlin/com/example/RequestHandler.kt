package com.example

import io.netty.buffer.Unpooled
import io.netty.channel.ChannelFutureListener
import io.netty.channel.ChannelHandlerContext
import io.netty.channel.SimpleChannelInboundHandler
import io.netty.handler.codec.http.*
import java.nio.charset.StandardCharsets

class RequestHandler : SimpleChannelInboundHandler<FullHttpRequest>() {

    override fun channelRead0(ctx: ChannelHandlerContext, request: FullHttpRequest) {
        val uri = request.uri()
        val (status, body) = when {
            uri == "/health" -> HttpResponseStatus.OK to "OK"
            uri == "/slow" -> {
                Thread.sleep(10_000)
                HttpResponseStatus.OK to "Done"
            }
            else -> HttpResponseStatus.NOT_FOUND to "Not Found"
        }

        val content = Unpooled.copiedBuffer(body, StandardCharsets.UTF_8)
        val response = DefaultFullHttpResponse(HttpVersion.HTTP_1_1, status, content)
        response.headers().set(HttpHeaderNames.CONTENT_TYPE, "text/plain")
        response.headers().set(HttpHeaderNames.CONTENT_LENGTH, content.readableBytes())
        ctx.writeAndFlush(response).addListener(ChannelFutureListener.CLOSE)
    }
}
