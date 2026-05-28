package com.example.facedetection

import android.app.Activity
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform Channel bridge for Tencent eKYC (HuiYan Overseas) SDK.
 *
 * Compiles without the SDK AARs by using reflection. When AARs are dropped into
 * [android/app/libs] and Gradle dependencies are enabled, [isSdkPresent] becomes true
 * and [startLiveness] invokes `HuiYanOsApi.startHuiYanAuth`.
 *
 * SDK docs: https://www.tencentcloud.com/document/product/1061/46853
 */
class TencentEkycPlugin(
    private var activity: Activity?,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "TencentEkycPlugin"
        const val CHANNEL_NAME = "com.facedetection/tencent_ekyc"

        private const val SDK_API_CLASS = "com.tencent.could.huiyansdk.api.HuiYanOsApi"
        private const val SDK_CONFIG_CLASS = "com.tencent.could.huiyansdk.entity.HuiYanOsConfig"
        private const val SDK_CALLBACK_CLASS =
            "com.tencent.could.huiyansdk.api.HuiYanOsAuthCallBack"

        @Volatile
        private var initialized = false

        fun registerWith(flutterEngine: FlutterEngine, activity: Activity) {
            val plugin = TencentEkycPlugin(activity)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
                .setMethodCallHandler(plugin)
        }
    }

    fun attachActivity(activity: Activity) {
        this.activity = activity
    }

    fun detachActivity() {
        this.activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isSdkPresent())
            "startLiveness" -> {
                val sdkToken = call.argument<String>("sdkToken")
                if (sdkToken.isNullOrBlank()) {
                    result.success(
                        mapOf(
                            "success" to false,
                            "errorCode" to "INVALID_TOKEN",
                            "errorMessage" to "sdkToken is required",
                        ),
                    )
                    return
                }

                val currentActivity = activity
                if (currentActivity == null) {
                    result.success(
                        mapOf(
                            "success" to false,
                            "errorCode" to "NO_ACTIVITY",
                            "errorMessage" to "Host Activity is not available",
                        ),
                    )
                    return
                }

                if (!isSdkPresent()) {
                    result.success(
                        mapOf(
                            "success" to false,
                            "errorCode" to "SDK_NOT_CONFIGURED",
                            "errorMessage" to
                                "Tencent eKYC SDK not found. Add AAR files to android/app/libs " +
                                "and enable Gradle dependencies (see README).",
                        ),
                    )
                    return
                }

                startLiveness(currentActivity, sdkToken, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun isSdkPresent(): Boolean {
        return try {
            Class.forName(SDK_API_CLASS)
            true
        } catch (_: ClassNotFoundException) {
            false
        }
    }

    private fun ensureInitialized(context: android.content.Context): Boolean {
        if (initialized) return true
        return try {
            val apiClass = Class.forName(SDK_API_CLASS)
            val initMethod = apiClass.getMethod("init", android.content.Context::class.java)
            initMethod.invoke(null, context.applicationContext)
            initialized = true
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize Tencent eKYC SDK", e)
            false
        }
    }

    private fun startLiveness(
        activity: Activity,
        sdkToken: String,
        result: MethodChannel.Result,
    ) {
        if (!ensureInitialized(activity.applicationContext)) {
            result.success(
                mapOf(
                    "success" to false,
                    "errorCode" to "SDK_INIT_FAILED",
                    "errorMessage" to "Failed to initialize Tencent eKYC SDK",
                ),
            )
            return
        }

        try {
            val configClass = Class.forName(SDK_CONFIG_CLASS)
            val config = configClass.getConstructor().newInstance()

            // License file must live in assets/ — contact Tencent to obtain YTFaceSDK.license
            val setAuthLicense = configClass.getMethod("setAuthLicense", String::class.java)
            setAuthLicense.invoke(config, "YTFaceSDK.license")

            val callbackClass = Class.forName(SDK_CALLBACK_CLASS)
            val callback = java.lang.reflect.Proxy.newProxyInstance(
                callbackClass.classLoader,
                arrayOf(callbackClass),
            ) { _, method, args ->
                when (method.name) {
                    "onSuccess" -> {
                        val authResult = args?.getOrNull(0)
                        val extra = mutableMapOf<String, Any?>()
                        authResult?.javaClass?.methods
                            ?.filter { it.parameterCount == 0 && it.name.startsWith("get") }
                            ?.forEach { getter ->
                                val key = getter.name.removePrefix("get")
                                    .replaceFirstChar { it.lowercase() }
                                runCatching { getter.invoke(authResult) }
                                    .getOrNull()
                                    ?.let { extra[key] = it.toString() }
                            }
                        activity.runOnUiThread {
                            result.success(
                                mapOf(
                                    "success" to true,
                                    "extra" to extra,
                                ),
                            )
                        }
                    }
                    "onFail" -> {
                        val errorCode = args?.getOrNull(0) as? Int ?: -1
                        val errorMsg = args?.getOrNull(1) as? String ?: "Unknown error"
                        val token = args?.getOrNull(2) as? String
                        activity.runOnUiThread {
                            result.success(
                                mapOf(
                                    "success" to false,
                                    "errorCode" to errorCode.toString(),
                                    "errorMessage" to errorMsg,
                                    "extra" to mapOf(
                                        "sdkToken" to token,
                                    ),
                                ),
                            )
                        }
                    }
                }
                null
            }

            val apiClass = Class.forName(SDK_API_CLASS)
            val startMethod = apiClass.getMethod(
                "startHuiYanAuth",
                String::class.java,
                configClass,
                callbackClass,
            )
            startMethod.invoke(null, sdkToken, config, callback)
        } catch (e: Exception) {
            Log.e(TAG, "startHuiYanAuth failed", e)
            result.success(
                mapOf(
                    "success" to false,
                    "errorCode" to "SDK_START_FAILED",
                    "errorMessage" to (e.message ?: e.toString()),
                ),
            )
        }
    }
}
