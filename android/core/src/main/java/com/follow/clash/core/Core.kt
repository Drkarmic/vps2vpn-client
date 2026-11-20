package com.follow.clash.core

import com.follow.clash.core.mobile.Mobile
import com.follow.clash.core.mobile.ResultHandler
import com.follow.clash.core.mobile.TunHandler
import java.net.InetAddress
import java.net.InetSocketAddress

object Core {
    /** Loads the Go library and runs its package init, which the first call otherwise pays for. */
    fun load() = Mobile.touch()

    fun forceGC() = Mobile.forceGC()

    fun setMitmPressure(level: Int) = Mobile.setMitmPressure(level)

    fun updateDNS(
        dns: String,
    ) = Mobile.updateDns(dns)

    fun resetNetwork() = Mobile.resetNetwork()

    private fun parseInetSocketAddress(address: String): InetSocketAddress {
        val rawHost: String
        val portText: String
        if (address.startsWith("[")) {
            val closeBracket = address.indexOf(']')
            require(
                closeBracket > 1 &&
                    closeBracket + 1 < address.length &&
                    address[closeBracket + 1] == ':',
            ) { "Invalid IPv6 socket address: $address" }
            rawHost = address.substring(1, closeBracket)
            portText = address.substring(closeBracket + 2)
        } else {
            val colon = address.lastIndexOf(':')
            require(colon > 0 && address.indexOf(':') == colon) {
                "Invalid socket address: $address"
            }
            rawHost = address.substring(0, colon)
            portText = address.substring(colon + 1)
        }
        val host = rawHost.substringBefore('%')
        require(host.isNotEmpty()) { "Missing host in address: $address" }
        val port = portText.toIntOrNull()
        require(port != null && port in 0..65535) { "Invalid port in address: $address" }
        return InetSocketAddress(InetAddress.getByName(host), port)
    }

    fun startTun(
        fd: Int,
        protect: (Int) -> Boolean,
        resolveUid: (protocol: Int, source: InetSocketAddress, target: InetSocketAddress) -> Int,
        resolvePackage: (uid: Int) -> String,
        stack: String,
        address: String,
        dns: String,
        options: String,
    ): Boolean {
        return Mobile.startTun(
            fd,
            object : TunHandler {
                override fun protect(fd: Int): Boolean = protect(fd)

                override fun resolveUid(
                    protocol: Int,
                    source: String,
                    target: String,
                ): Int {
                    return resolveUid(
                        protocol,
                        parseInetSocketAddress(source),
                        parseInetSocketAddress(target),
                    )
                }

                override fun resolvePackage(uid: Int): String = resolvePackage(uid)
            },
            stack,
            address,
            dns,
            options,
        )
    }

    fun invokeMethod(
        data: String,
        cb: (result: ByteArray?) -> Unit,
    ) {
        Mobile.invokeMethod(data, ResultHandler { result -> cb(result) })
    }

    fun updateEventListener(
        callback: ((result: ByteArray) -> Unit)?,
    ) {
        Mobile.setEventListener(
            callback?.let { ResultHandler { result -> it(result ?: ByteArray(0)) } },
        )
    }

    fun quickSetup(
        initParamsString: String,
        setupParamsString: String,
        callback: (result: String?) -> Unit,
    ) {
        Mobile.quickSetup(
            initParamsString,
            setupParamsString,
            ResultHandler { result -> callback(result?.decodeToString()) },
        )
    }

    fun stopTun() = Mobile.stopTun()

    fun startListener() = Mobile.startListener()

    fun stopListener() = Mobile.stopListener()

    fun getTraffic(onlyStatisticsProxy: Boolean): String = Mobile.getTraffic(onlyStatisticsProxy)

    fun getTotalTraffic(onlyStatisticsProxy: Boolean): String = Mobile.getTotalTraffic(onlyStatisticsProxy)
}
