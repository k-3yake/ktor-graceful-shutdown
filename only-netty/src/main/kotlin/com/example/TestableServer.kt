package com.example

interface TestableServer {
    val actualPort: Int
    fun start()
    fun stop(gracePeriodSeconds: Long = 15, timeoutSeconds: Long = 20)
    fun printState(label: String)
}
