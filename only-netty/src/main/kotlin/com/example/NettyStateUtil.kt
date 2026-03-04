package com.example

import io.netty.channel.EventLoopGroup
import io.netty.util.concurrent.SingleThreadEventExecutor
import java.nio.channels.Selector

// Netty 4.2.x の SingleThreadEventExecutor state 定数
private val STATE_NAMES = mapOf(
    1 to "NOT_STARTED",
    2 to "SUSPENDING",
    3 to "SUSPENDED",
    4 to "STARTED",
    5 to "SHUTTING_DOWN",
    6 to "SHUTDOWN",
    7 to "TERMINATED"
)

fun printEventLoopGroupState(name: String, group: EventLoopGroup) {
    println("  [$name] isShuttingDown=${group.isShuttingDown}, isShutdown=${group.isShutdown}, isTerminated=${group.isTerminated}")

    for ((i, eventLoop) in group.toList().withIndex()) {
        // EventLoop の state をリフレクションで取得
        val stateValue = try {
            val stateField = SingleThreadEventExecutor::class.java.getDeclaredField("state")
            stateField.isAccessible = true
            stateField.getInt(eventLoop)
        } catch (e: Exception) {
            println("    EventLoop[$i] state取得失敗: ${e.message}")
            -1
        }
        val stateName = STATE_NAMES[stateValue] ?: "UNKNOWN($stateValue)"

        println("    EventLoop[$i] state=$stateValue($stateName), isShuttingDown=${eventLoop.isShuttingDown}")

        // Netty 4.2.x: selector は NioIoHandler 内にある
        // NioEventLoop → SingleThreadIoEventLoop.ioHandler → NioIoHandler.unwrappedSelector
        try {
            // Step 1: SingleThreadIoEventLoop から ioHandler を取得
            val ioEventLoopClass = Class.forName("io.netty.channel.SingleThreadIoEventLoop")
            val ioHandlerField = ioEventLoopClass.getDeclaredField("ioHandler")
            ioHandlerField.isAccessible = true
            val ioHandler = ioHandlerField.get(eventLoop)

            // Step 2: NioIoHandler から unwrappedSelector を取得
            val nioIoHandlerClass = Class.forName("io.netty.channel.nio.NioIoHandler")
            val selectorField = nioIoHandlerClass.getDeclaredField("unwrappedSelector")
            selectorField.isAccessible = true
            val selector = selectorField.get(ioHandler) as? Selector

            if (selector != null) {
                try {
                    val keys = selector.keys()
                    println("      登録チャネル数: ${keys.size}")
                    for (key in keys) {
                        val attachment = key.attachment()
                        if (attachment is io.netty.channel.Channel) {
                            println("        Channel: ${attachment::class.simpleName} isOpen=${attachment.isOpen}, isActive=${attachment.isActive}")
                        } else {
                            println("        SelectionKey: valid=${key.isValid}, attachment=${attachment?.javaClass?.simpleName}")
                        }
                    }
                } catch (e: java.util.ConcurrentModificationException) {
                    println("      チャネル列挙中にConcurrentModificationException発生（スキップ）")
                } catch (e: java.nio.channels.ClosedSelectorException) {
                    println("      selector已クローズ")
                }
            } else {
                println("      selector=null")
            }
        } catch (e: Exception) {
            println("      selector取得失敗: ${e::class.simpleName}: ${e.message}")
        }
    }
}
