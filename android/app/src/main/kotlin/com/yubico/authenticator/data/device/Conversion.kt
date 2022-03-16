package com.yubico.authenticator.data.device

import com.yubico.yubikit.core.Transport
import com.yubico.yubikit.core.Version
import com.yubico.yubikit.management.DeviceConfig
import com.yubico.yubikit.management.DeviceInfo
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

fun DeviceConfig.toJson() = JsonObject(
    mapOf(
        "device_flags" to JsonPrimitive(deviceFlags),
        "challenge_response_timeout" to JsonPrimitive(challengeResponseTimeout),
        "auto_eject_timeout" to JsonPrimitive(autoEjectTimeout),
        "enabled_capabilities" to JsonObject(
            mapOf(
                "usb" to JsonPrimitive(getEnabledCapabilities(Transport.USB) ?: 0),
                "nfc" to JsonPrimitive(getEnabledCapabilities(Transport.NFC) ?: 0),
            )
        )
    )
)

fun Version.toJson() = JsonArray(
    listOf(
        JsonPrimitive(major),
        JsonPrimitive(minor),
        JsonPrimitive(micro)
    )
)

fun DeviceInfo.toJson(isNfcDevice: Boolean) = JsonObject(
    mapOf(
        "config" to config.toJson(),
        "serial" to JsonPrimitive(serialNumber),
        "version" to version.toJson(),
        "form_factor" to JsonPrimitive(formFactor.value),
        "is_locked" to JsonPrimitive(isLocked),
        "is_sky" to JsonPrimitive(false),  // FIXME return correct value
        "is_fips" to JsonPrimitive(false), // FIXME return correct value
        "name" to JsonPrimitive("FIXME"),  // FIXME return correct value
        "isNFC" to JsonPrimitive(isNfcDevice),
        "supported_capabilities" to JsonObject(
            mapOf(
                "usb" to JsonPrimitive(getSupportedCapabilities(Transport.USB)),
                "nfc" to JsonPrimitive(getSupportedCapabilities(Transport.NFC)),
            )
        )
    )
)
