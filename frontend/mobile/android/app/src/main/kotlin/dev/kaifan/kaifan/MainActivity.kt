package dev.kaifan.kaifan

import android.app.AlertDialog
import android.os.Build
import android.text.InputFilter
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.WindowManager
import android.widget.EditText
import android.widget.FrameLayout
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var textEditor: AlertDialog? = null
    private var inputChannel: MethodChannel? = null
    private val isWsa: Boolean
        get() = Build.MODEL.contains("Subsystem for Android", ignoreCase = true) ||
            Build.PRODUCT.startsWith("windows_")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        inputChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kaifan/input_compat")
        inputChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isWsa" -> result.success(isWsa)
                "editRecipeText" -> editRecipeText(call.arguments as? Map<*, *>, result)
                "resetAfterClear" -> {
                    val view = flutterView(window.decorView)
                    if (isWsa && view != null && view.hasWindowFocus()) {
                        // WSA can retain the old composing buffer after hardware-key deletion.
                        // Restart using Flutter's current editable state; do not synthesize keys.
                        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).restartInput(view)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun editRecipeText(arguments: Map<*, *>?, result: MethodChannel.Result) {
        if (!isWsa) { result.notImplemented(); return }
        if (textEditor != null) { result.error("editor_busy", "An editor is already open", null); return }
        val initial = arguments?.get("text") as? String ?: ""
        val title = arguments?.get("title") as? String ?: "编辑文本"
        val multiline = arguments?.get("multiline") == true
        val number = arguments?.get("number") == true
        val limit = (arguments?.get("maxLength") as? Number)?.toInt()
        val editor = EditText(this).apply {
            inputType = if (number) InputType.TYPE_CLASS_NUMBER else
                InputType.TYPE_CLASS_TEXT or (if (multiline) InputType.TYPE_TEXT_FLAG_MULTI_LINE else 0)
            setSingleLine(!multiline)
            imeOptions = if (multiline) EditorInfo.IME_FLAG_NO_ENTER_ACTION or EditorInfo.IME_ACTION_NONE else EditorInfo.IME_ACTION_DONE
            if (multiline) setOnEditorActionListener { _, _, event ->
                // WSA may deliver Return as an IME action rather than a key.
                if (event == null || event.keyCode == KeyEvent.KEYCODE_ENTER) {
                    if (event == null || event.action == KeyEvent.ACTION_DOWN) {
                        val from = selectionStart.coerceAtLeast(0)
                        val to = selectionEnd.coerceAtLeast(from)
                        text.replace(from, to, "\n")
                    }
                    true
                } else false
            }
            if (multiline) { minLines = 6; maxLines = 12; gravity = Gravity.TOP or Gravity.START }
            setText(initial)
            setSelection(text.length)
            hint = arguments?.get("hint") as? String
            if (limit != null && limit > 0) filters = arrayOf(InputFilter.LengthFilter(limit))
            setTextSize(18f)
        }
        val padding = (20 * resources.displayMetrics.density).toInt()
        val container = FrameLayout(this).apply {
            setPadding(padding, padding / 2, padding, 0)
            addView(editor, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT))
        }
        var delivered = false
        fun complete(value: String?) {
            if (!delivered) { delivered = true; result.success(value) }
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(title)
            .setView(container)
            .setPositiveButton("完成") { _, _ -> complete(editor.text.toString()) }
            .setNegativeButton("取消") { _, _ -> complete(null) }
            .setNeutralButton("清空", null)
            .create()
        textEditor = dialog
        dialog.setOnDismissListener { complete(null); textEditor = null }
        dialog.show()
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        val availableWidth = window.decorView.width.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels
        val editorWidth = (availableWidth * 0.9f).toInt().coerceAtMost((900 * resources.displayMetrics.density).toInt())
        dialog.window?.setLayout(editorWidth, WindowManager.LayoutParams.WRAP_CONTENT)
        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener { editor.text.clear(); editor.requestFocus() }
        editor.requestFocus()
    }

    private fun flutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                flutterView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        textEditor?.dismiss()
        textEditor = null
        inputChannel?.setMethodCallHandler(null)
        inputChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
