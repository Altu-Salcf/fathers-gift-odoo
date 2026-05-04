package com.example.fathers_gift_app

import android.nfc.NfcAdapter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val NFC_CHANNEL = "nfc_check"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NFC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNfcState" -> {
                        // Get a FRESH adapter reference every time
                        val adapter = NfcAdapter.getDefaultAdapter(this)
                        if (adapter == null) {
                            // No NFC hardware on this device
                            result.success("notSupported")
                        } else if (!adapter.isEnabled) {
                            // NFC hardware exists but is turned OFF
                            result.success("disabled")
                        } else {
                            // NFC is ON and ready
                            result.success("enabled")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
