package uz.hisobchi.hisobchi_app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "uz.hisobchi.hisobchi_app/installer"
    private val vaultAlias = "hisobchi_vault_aes256"
    private val vaultPrefsName = "hisobchi_secure_vault"
    private var pendingApkPath: String? = null
    private var pendingDocResult: MethodChannel.Result? = null
    private val pickDocRequestCode = 4201
    private val micPermRequestCode = 4202
    private var voiceRecorder: MediaRecorder? = null
    private var voiceFile: File? = null

    private fun getOrCreateVaultKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = ks.getEntry(vaultAlias, null) as? KeyStore.SecretKeyEntry
        if (existing != null) {
            return existing.secretKey
        }
        val keyGen = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        val spec = KeyGenParameterSpec.Builder(
            vaultAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGen.init(spec)
        return keyGen.generateKey()
    }

    private fun vaultWrite(key: String, value: String) {
        val secretKey = getOrCreateVaultKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val iv = cipher.iv
        val encrypted = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        val encoded = Base64.encodeToString(iv, Base64.NO_WRAP) +
            ":" +
            Base64.encodeToString(encrypted, Base64.NO_WRAP)
        getSharedPreferences(vaultPrefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(key, encoded)
            .apply()
    }

    private fun vaultRead(key: String): String? {
        val raw = getSharedPreferences(vaultPrefsName, Context.MODE_PRIVATE)
            .getString(key, null) ?: return null
        val parts = raw.split(":", limit = 2)
        if (parts.size != 2) return null
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val cipherBytes = Base64.decode(parts[1], Base64.NO_WRAP)
        val secretKey = getOrCreateVaultKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
        val plain = cipher.doFinal(cipherBytes)
        return String(plain, StandardCharsets.UTF_8)
    }

    private fun vaultDelete(key: String) {
        getSharedPreferences(vaultPrefsName, Context.MODE_PRIVATE)
            .edit()
            .remove(key)
            .apply()
    }

    private fun releaseVoiceRecorder() {
        try {
            voiceRecorder?.stop()
        } catch (_: Exception) {
        }
        try {
            voiceRecorder?.release()
        } catch (_: Exception) {
        }
        voiceRecorder = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        if (BuildConfig.IS_PLAY_STORE) {
                            result.error(
                                "UNSUPPORTED_FLAVOR",
                                "Google Play versiyasi yangilanishlarni Play Market orqali oladi",
                                null,
                            )
                            return@setMethodCallHandler
                        }
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
                        val allowedRoot = cacheDir.canonicalPath
                        val canonicalTarget = file.canonicalPath
                        if (!canonicalTarget.startsWith(allowedRoot + File.separator)) {
                            result.error("FORBIDDEN_PATH", "Ruxsat etilmagan fayl yo'li", null)
                            return@setMethodCallHandler
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()
                            ) {
                                pendingApkPath = canonicalTarget
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
                    "secureWrite" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key.isNullOrBlank() || value == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            vaultWrite(key, value)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "secureRead" -> {
                        val key = call.argument<String>("key")
                        if (key.isNullOrBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(vaultRead(key))
                        } catch (_: Exception) {
                            result.success(null)
                        }
                    }
                    "secureDelete" -> {
                        val key = call.argument<String>("key")
                        if (!key.isNullOrBlank()) {
                            try {
                                vaultDelete(key)
                            } catch (_: Exception) {
                            }
                        }
                        result.success(true)
                    }
                    "setScreenSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        runOnUiThread {
                            try {
                                if (secure) {
                                    window.setFlags(
                                        WindowManager.LayoutParams.FLAG_SECURE,
                                        WindowManager.LayoutParams.FLAG_SECURE,
                                    )
                                } else {
                                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                                }
                            } catch (_: Exception) {
                            }
                        }
                        result.success(true)
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
                        val parsed = Uri.parse(url.trim())
                        val scheme = parsed.scheme?.lowercase()
                        if (scheme != "https" && scheme != "tg") {
                            result.error("FORBIDDEN_SCHEME", "Faqat https:// yoki tg:// havolalar ruxsat etilgan", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, parsed).apply {
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
                    "startVoiceRecord" -> {
                        if (ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.RECORD_AUDIO
                            ) != PackageManager.PERMISSION_GRANTED
                        ) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.RECORD_AUDIO),
                                micPermRequestCode
                            )
                            result.success("PERMISSION_REQUESTED")
                            return@setMethodCallHandler
                        }
                        try {
                            releaseVoiceRecorder()
                            val out = File(cacheDir, "hisobchi_voice.m4a")
                            if (out.exists()) out.delete()
                            val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                MediaRecorder(this)
                            } else {
                                @Suppress("DEPRECATION")
                                MediaRecorder()
                            }
                            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
                            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                            rec.setAudioSamplingRate(16000)
                            rec.setAudioEncodingBitRate(64000)
                            rec.setMaxDuration(60000)
                            rec.setOutputFile(out.absolutePath)
                            rec.prepare()
                            rec.start()
                            voiceRecorder = rec
                            voiceFile = out
                            result.success("STARTED")
                        } catch (e: Exception) {
                            releaseVoiceRecorder()
                            result.error("MIC_ERROR", e.localizedMessage ?: e.toString(), null)
                        }
                    }
                    "stopVoiceRecord" -> {
                        val out = voiceFile
                        voiceFile = null
                        releaseVoiceRecorder()
                        if (out != null && out.exists() && out.length() > 256) {
                            result.success(
                                mapOf(
                                    "path" to out.absolutePath,
                                    "name" to "voice.m4a",
                                )
                            )
                        } else {
                            result.success(null)
                        }
                    }
                    "cancelVoiceRecord" -> {
                        val out = voiceFile
                        voiceFile = null
                        releaseVoiceRecorder()
                        try {
                            out?.delete()
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        releaseVoiceRecorder()
        super.onDestroy()
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
