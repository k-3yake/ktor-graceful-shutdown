package com.example

import io.ktor.server.application.*
import io.ktor.server.netty.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.coroutines.delay
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("com.example.Application")

fun main(args: Array<String>): Unit {
    Runtime.getRuntime().addShutdownHook(Thread {
        log.info("[EVENT] SIGTERM received - JVM shutdown hook triggered")
    })
    EngineMain.main(args)
}

fun Application.module() {
    environment.monitor.subscribe(ApplicationStarted) {
        log.info("[EVENT] Application started")
    }
    environment.monitor.subscribe(ApplicationStopping) {
        log.info("[EVENT] ApplicationStopping - Ktor shutdown initiated")
    }
    environment.monitor.subscribe(ApplicationStopped) {
        log.info("[EVENT] ApplicationStopped - Ktor shutdown completed")
    }

    routing {
        get("/health") {
            call.respondText("OK")
        }
        get("/slow") {
            log.info("[EVENT] /slow request received - starting 30s processing")
            delay(30000)
            log.info("[EVENT] /slow response sending - processing complete")
            call.respondText("Done")
        }
    }
}
