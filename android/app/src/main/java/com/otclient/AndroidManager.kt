package com.otclient

import android.app.PendingIntent
import android.content.Intent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.isVisible
import androidx.core.content.pm.PackageInfoCompat
import java.io.File
import java.security.MessageDigest

class AndroidManager(
    private val context: Context,
    private val editText: FakeEditText,
    private val previewContainer: View,
    private val previewText: TextView,
    private val pasteButton: ImageButton,
    private val copyButton: ImageButton,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var isImeVisible = false
    private var shouldShowPreview = false
    private var pendingPreviewText: String = ""
    private var imeHeight: Int = 0

    // Widget position from C++ (in game pixels, maps 1:1 to screen pixels)
    private var widgetX: Int = -1
    private var widgetY: Int = -1
    private var widgetW: Int = -1
    private var widgetH: Int = -1

    init {
        pasteButton.setOnClickListener {
            val clipText = getClipboardText()
            if (clipText.isNotEmpty() && editText.visibility == View.VISIBLE) {
                try {
                    editText.ic.commitText(clipText, 1)
                } catch (_: Exception) { }
            }
        }

        copyButton.setOnClickListener {
            if (editText.visibility == View.VISIBLE) {
                try {
                    val text = pendingPreviewText
                    if (text.isNotEmpty()) {
                        setClipboardText(text)
                    }
                } catch (_: Exception) { }
            }
        }
    }

    /*
     * Methods called from JNI
     */

    fun showSoftKeyboard() {
        handler.post {
            editText.visibility = View.VISIBLE
            editText.requestFocus()
            val imm = editText.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(editText, 0)
        }
    }

    fun hideSoftKeyboard() {
        handler.post {
            editText.visibility = View.INVISIBLE
            val imm = editText.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.hideSoftInputFromWindow(editText.windowToken, 0)
            hidePreviewInternal(clearText = false)
        }
    }

    fun showInputPreview(text: String, widgetX: Int, widgetY: Int, widgetW: Int, widgetH: Int) {
        handler.post {
            pendingPreviewText = text
            this.widgetX = widgetX
            this.widgetY = widgetY
            this.widgetW = widgetW
            this.widgetH = widgetH
            shouldShowPreview = true
            if (isImeVisible) showPreviewInternal()
        }
    }

    fun updateInputPreview(text: String) {
        handler.post {
            pendingPreviewText = text
            if (shouldShowPreview && isImeVisible) showPreviewInternal(animate = false)
        }
    }

    fun hideInputPreview() {
        handler.post {
            shouldShowPreview = false
            pendingPreviewText = ""
            widgetX = -1
            widgetY = -1
            widgetW = -1
            widgetH = -1
            hidePreviewInternal(clearText = true)
        }
    }

    fun onImeVisibilityChanged(visible: Boolean, imeHeight: Int) {
        nativeOnImeVisibilityChanged(visible, if (visible) imeHeight else 0)
        handler.post {
            isImeVisible = visible
            this.imeHeight = imeHeight
            if (visible) {
                if (shouldShowPreview) showPreviewInternal()
            } else {
                hidePreviewInternal(clearText = false)
            }
        }
    }

    fun getDisplayDensity(): Float = context.resources.displayMetrics.density

    fun getPackageName(): String = context.packageName

    fun getVersionCode(): Int = PackageInfoCompat.getLongVersionCode(
        context.packageManager.getPackageInfo(context.packageName, 0),
    ).toInt()

    fun getFileSize(path: String): Long = validatedUpdateFile(path)?.length() ?: -1

    fun sha256File(path: String): String {
        val file = validatedUpdateFile(path) ?: return ""
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
    }

    fun installApk(path: String): Int {
        val apk = validatedUpdateFile(path) ?: return 0
        val requiresSourcePermission = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()

        if (requiresSourcePermission) {
            handler.post {
                try {
                    val settingsIntent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${context.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(settingsIntent)
                } catch (_: Exception) {
                    showInstallError("Não foi possível abrir as configurações de instalação.")
                }
            }
            return 1
        }

        Thread({
            try {
                val installer = context.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                    setAppPackageName(context.packageName)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                        setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
                    }
                }
                val sessionId = installer.createSession(params)
                try {
                    installer.openSession(sessionId).use { session ->
                        apk.inputStream().buffered().use { input ->
                            session.openWrite(apk.name, 0, apk.length()).use { output ->
                                input.copyTo(output)
                                session.fsync(output)
                            }
                        }

                        val callbackIntent = Intent(context, AndroidInstallReceiver::class.java)
                            .setAction("${context.packageName}.INSTALL_STATUS.$sessionId")
                        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                                PendingIntent.FLAG_MUTABLE
                            } else {
                                0
                            }
                        val statusCallback = PendingIntent.getBroadcast(
                            context,
                            sessionId,
                            callbackIntent,
                            pendingFlags,
                        )
                        session.commit(statusCallback.intentSender)
                    }
                } catch (error: Exception) {
                    installer.abandonSession(sessionId)
                    throw error
                }
            } catch (error: Exception) {
                showInstallError("Não foi possível preparar a instalação: ${error.message ?: "erro desconhecido"}")
            }
        }, "otclient-apk-installer").apply {
            isDaemon = true
            start()
        }
        return 2
    }

    private fun showInstallError(message: String) {
        handler.post {
            Toast.makeText(context, message, Toast.LENGTH_LONG).show()
        }
    }

    private fun validatedUpdateFile(path: String): File? {
        val apk = try {
            File(path).canonicalFile
        } catch (_: Exception) {
            return null
        }
        val updatesDirectory = try {
            File(context.filesDir, "game_data/updates").canonicalFile
        } catch (_: Exception) {
            return null
        }
        return apk.takeIf {
            it.isFile && it.path.startsWith(updatesDirectory.path + File.separator)
        }
    }

    fun getClipboardText(): String {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip ?: return ""
        if (clip.itemCount == 0) return ""
        return clip.getItemAt(0).coerceToText(context).toString()
    }

    fun setClipboardText(text: String) {
        handler.post {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("OTClient", text))
            // Refresh paste button visibility after clipboard change
            pasteButton.visibility = View.VISIBLE
        }
    }

    external fun nativeInit()
    external fun nativeSetAudioEnabled(enabled: Boolean)
    external fun nativeOnImeVisibilityChanged(visible: Boolean, imeHeight: Int)

    private fun showPreviewInternal(animate: Boolean = true) {
        previewContainer.animate().cancel()

        // Update text and visibility
        val hasText = pendingPreviewText.isNotEmpty()
        previewText.text = pendingPreviewText
        previewText.visibility = if (hasText) View.VISIBLE else View.GONE

        // Show/hide copy based on content
        copyButton.visibility = if (hasText) View.VISIBLE else View.GONE

        // Show/hide paste based on clipboard content
        val hasClip = getClipboardText().isNotEmpty()
        pasteButton.visibility = if (hasClip) View.VISIBLE else View.GONE

        if (!previewContainer.isVisible) {
            previewContainer.alpha = if (animate) 0f else 1f
            previewContainer.isVisible = true
        }

        // Position after making visible so measurement works
        previewContainer.post { positionNearWidget() }

        if (animate && previewContainer.alpha < 1f) {
            previewContainer.animate()
                .alpha(1f)
                .setDuration(120L)
                .start()
        }
    }

    private fun positionNearWidget() {
        previewContainer.measure(
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val toolbarW = previewContainer.measuredWidth.coerceAtLeast(1)
        val toolbarH = previewContainer.measuredHeight.coerceAtLeast(1)

        val parent = previewContainer.parent as? View ?: return
        val screenW = parent.width
        val screenH = parent.height
        if (screenH <= 0) return

        val gap = (6 * context.resources.displayMetrics.density).toInt()
        val keyboardTop = screenH - imeHeight

        // TODO: Smart positioning — use widgetX/widgetY/widgetW/widgetH (already passed from C++)
        // to position the toolbar near the focused input field. Try all directions:
        // 1. Above the widget  2. Below the widget  3. Left  4. Right
        // Fall back to above-keyboard only if none fit without overlapping the input.
        // Currently: always above keyboard (simple, predictable, never overlaps).
        val targetY = (keyboardTop - toolbarH - gap).coerceIn(0, screenH - toolbarH)
        val targetX = ((screenW - toolbarW) / 2).coerceAtLeast(0)

        val params = previewContainer.layoutParams as? FrameLayout.LayoutParams ?: return
        params.topMargin = targetY
        params.marginStart = targetX
        previewContainer.layoutParams = params
    }

    private fun hidePreviewInternal(animate: Boolean = true, clearText: Boolean) {
        previewContainer.animate().cancel()
        if (!previewContainer.isVisible) {
            if (clearText) previewText.text = ""
            return
        }

        val cleanup = {
            previewContainer.isVisible = false
            previewContainer.alpha = 1f
            if (clearText) previewText.text = ""
            // Reset position so it doesn't stick in a corner
            val params = previewContainer.layoutParams as? FrameLayout.LayoutParams
            if (params != null) {
                params.topMargin = 0
                params.marginStart = 0
                previewContainer.layoutParams = params
            }
        }

        if (animate) {
            previewContainer.animate()
                .alpha(0f)
                .setDuration(120L)
                .withEndAction(cleanup)
                .start()
        } else {
            cleanup()
        }
    }
}
