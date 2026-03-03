package com.example

import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.coroutines.delay

fun Application.module() {
    routing {
        get("/health") {
            call.respondText("OK")
        }
        get("/slow") {
            delay(10000)
            call.respondText("Done")
        }
    }
}
