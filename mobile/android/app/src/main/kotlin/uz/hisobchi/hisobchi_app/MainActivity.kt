package uz.hisobchi.hisobchi_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "uz.hisobchi.hisobchi_app/installer"
    private var pendingApkPath: String? = null
    private var pendingDocResult: MethodChannel.Result? = null
    private val pickDocRequestCode = 4201

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK fayl manzili bo'sh", null)
                            return@setMethodCallHandler
                        }
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("NOT_FOUND", "APK fayl topilmadi: $path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()
                            ) {
                                pendingApkPath = path
                                val permIntent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                ).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(permIntent)
                                result.success("PERMISSION_REQUESTED")
                            } else {
                                launchPackageInstaller(file)
                                result.success("INSTALLER_LAUNCHED")
                            }
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.localizedMessage ?: e.toString(), null)
                        }
                    }
                    "pickDocument" -> {
                        if (pendingDocResult != null) {
                            result.error("BUSY", "Fayl tanlash oynasi allaqachon ochiq", null)
                            return@setMethodCallHandler
                        }
                        try {
                            pendingDocResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                            }
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, pickDocRequestCode)
                        } catch (e: Exception) {
                            pendingDocResult = null
                            result.error("PICK_ERROR", e.localizedMessage ?: e.toString(), null)
                        }
                    }
                    "openExternalUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("INVALID_URL", "Havola bo'sh", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_ERROR", e.localizedMessage ?: e.toString(), null)
                        }
                    }
                    "canUseBiometric" -> {
                        try {
                            val mgr = BiometricManager.from(this)
                            val status = mgr.canAuthenticate(
                                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                                    BiometricManager.Authenticators.BIOMETRIC_WEAK
                            )
                            result.success(status == BiometricManager.BIOMETRIC_SUCCESS)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "authenticateBiometric" -> {
                        val title = call.argument<String>("title") ?: "Hisobchi — Tasdiqlash"
                        val subtitle = call.argument<String>("subtitle")
                            ?: "Ilovaga kirish uchun barmoq izini tasdiqlang"
                        val replied = AtomicBoolean(false)
                        fun finish(ok: Boolean) {
                            if (replied.compareAndSet(false, true)) {
                                runOnUiThread { result.success(ok) }
                            }
                        }
                        try {
                            val executor = ContextCompat.getMainExecutor(this)
                            val prompt = BiometricPrompt(
                                this,
                                executor,
                                object : BiometricPrompt.AuthenticationCallback() {
                                    override fun onAuthenticationSucceeded(
                                        res: BiometricPrompt.AuthenticationResult
                                    ) {
                                        super.onAuthenticationSucceeded(res)
                                        finish(true)
                                    }

                                    override fun onAuthenticationError(
                                        errorCode: Int,
                                        errString: CharSequence
                                    ) {
                                        super.onAuthenticationError(errorCode, errString)
                                        finish(false)
                                    }
                                }
                            )
                            val info = BiometricPrompt.PromptInfo.Builder()
                                .setTitle(title)
                                .setSubtitle(subtitle)
                                .setNegativeButtonText("PIN kod bilan kirish")
                                .build()
                            prompt.authenticate(info)
                        } catch (_: Exception) {
                            finish(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickDocRequestCode) {
            val res = pendingDocResult
            pendingDocResult = null
            if (res == null) return
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                res.success(null)
                return
            }
            try {
                var displayName = "yespos.xlsx"
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIdx >= 0 && cursor.moveToFirst()) {
                        val candidate = cursor.getString(nameIdx)
                        if (!candidate.isNullOrBlank()) {
                            displayName = candidate
                        }
                    }
                }
                val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val outFile = File(cacheDir, safeName)
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(outFile).use { output ->
                        input.copyTo(output)
                    }
                } ?: run {
                    res.error("READ_ERROR", "Faylni o'qib bo'lmadi", null)
                    return
                }
                res.success(
                    mapOf(
                        "path" to outFile.absolutePath,
                        "name" to displayName
                    )
                )
            } catch (e: Exception) {
                res.error("COPY_ERROR", e.localizedMessage ?: e.toString(), null)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        val path = pendingApkPath
        if (!path.isNullOrBlank() &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.canRequestPackageInstalls()
        ) {
            pendingApkPath = null
            val file = File(path)
            if (file.exists()) {
                try {
                    launchPackageInstaller(file)
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun launchPackageInstaller(file: File) {
        val uri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.apkprovider",
            file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
