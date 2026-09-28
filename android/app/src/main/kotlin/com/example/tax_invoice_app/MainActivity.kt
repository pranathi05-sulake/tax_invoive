package com.example.tax_invoice_app

import android.content.pm.ApplicationInfo
import android.view.WindowManager.LayoutParams
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // FLAG_SECURE is applied ONLY in RELEASE builds.
        // In DEBUG builds, it is temporarily bypassed to allow UI screenshot inspection.
        val isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isDebuggable) {
            window.addFlags(LayoutParams.FLAG_SECURE)
        }
    }
}

