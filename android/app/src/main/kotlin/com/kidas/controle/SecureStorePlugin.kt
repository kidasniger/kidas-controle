package com.kidas.controle

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Plugin Flutter dédié au coffre. Canal séparé du pont général kidas/native.
 * L'enregistrement se fait explicitement depuis MainActivity sur chaque moteur.
 */
class SecureStorePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(
            binding.binaryMessenger,
            "com.kidas.controle/secure_store_v1"
        ).also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("secure_unavailable", "Le coffre sécurisé n'est pas initialisé.", null)
            return
        }
        val store = SecureStore(context)
        try {
            when (call.method) {
                "get" -> result.success(store.get(call.argument<String>("key") ?: ""))
                "set" -> {
                    store.set(
                        call.argument<String>("key") ?: "",
                        call.argument<String>("value") ?: ""
                    )
                    result.success(true)
                }
                "delete" -> {
                    store.delete(call.argument<String>("key") ?: "")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error(
                "secure_store_error",
                error.message ?: "Opération du coffre sécurisé impossible.",
                null
            )
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }
}
