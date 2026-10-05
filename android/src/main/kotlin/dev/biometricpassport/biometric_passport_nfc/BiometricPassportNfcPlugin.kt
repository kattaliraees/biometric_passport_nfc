package dev.biometricpassport.biometric_passport_nfc

import android.app.Activity
import android.app.Application
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.TagLostException
import android.nfc.tech.IsoDep
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.HapticFeedbackConstants
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.sf.scuba.smartcards.CardService
import net.sf.scuba.smartcards.CardServiceException
import net.sf.scuba.smartcards.IsoDepCardService
import org.jmrtd.AccessDeniedException
import org.jmrtd.BACDeniedException
import org.jmrtd.BACKey
import org.jmrtd.BACKeySpec
import org.jmrtd.PassportService
import org.jmrtd.lds.CardAccessFile
import org.jmrtd.lds.PACEInfo
import org.jmrtd.lds.icao.DG1File
import org.jmrtd.lds.icao.DG2File
import org.spongycastle.jce.provider.BouncyCastleProvider
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.security.Security
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Reads ICAO 9303 passports via Android reader mode + JMRTD.
 *
 * Reader mode needs a foreground Activity, so the plugin tracks the attached Activity's
 * pause/resume itself and re-enables reader mode when a read is in progress.
 */
class BiometricPassportNfcPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, Application.ActivityLifecycleCallbacks {

    companion object {
        private const val TAG = "BiometricPassportNfc"
        private const val METHOD_CHANNEL = "biometric_passport_nfc/method"
        private const val EVENT_CHANNEL = "biometric_passport_nfc/events"

        // Longer presence-check interval means fewer idle "are you there?" pings to the chip,
        // which on many devices (notably Samsung) cause spurious TagLostExceptions mid-read.
        // Kept moderate so a removed passport is still noticed quickly and re-taps are detected.
        private const val PRESENCE_CHECK_DELAY_MS = 500

        // Per-APDU timeout. Long enough for slow PACE/BAC crypto on the chip, short enough
        // that a weakly coupled chip fails fast instead of freezing the UI.
        private const val ISO_DEP_TIMEOUT_MS = 5000

        // Immediate reconnects on the same Tag object before asking the user to re-tap.
        private const val MAX_IN_PLACE_RECONNECTS = 2

        // Transient (non-credential) failures tolerated across re-taps before giving up.
        private const val MAX_TRANSIENT_FAILURES = 6

        private const val SW_AUTH_FAILED = 0x6300
        private const val SW_SECURITY_STATUS_NOT_SATISFIED = 0x6982
        private const val SW_FILE_NOT_FOUND = 0x6A82

        init {
            try {
                Security.removeProvider("BC")
                Security.insertProviderAt(org.bouncycastle.jce.provider.BouncyCastleProvider(), 1)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to register BouncyCastle provider", e)
            }
            try {
                Security.insertProviderAt(BouncyCastleProvider(), 2)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to register SpongyCastle provider", e)
            }
        }
    }

    /**
     * State that survives across taps of a single scan request. When the chip connection drops
     * mid-read, the next tap resumes from here instead of starting over: the working auth method is
     * remembered and data groups (including a partially read DG2) are not re-read.
     */
    private class ScanSession(
        val docNumber: String,
        val dob: String,
        val expiry: String,
    ) {
        var paceInfo: PACEInfo? = null
        var skipPace = false
        var paceSucceeded = false
        var bacSucceeded = false
        var dg1Bytes: ByteArray? = null
        val dg2Buffer = ByteArrayOutputStream()
        var dg2Length = -1
        var dg2Done = false
        var transientFailures = 0
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var activity: Activity? = null
    private var nfcAdapter: NfcAdapter? = null
    private var pendingResult: MethodChannel.Result? = null

    @Volatile
    private var session: ScanSession? = null
    private val readInProgress = AtomicBoolean(false)

    private val mainHandler = Handler(Looper.getMainLooper())

    // region FlutterPlugin / ActivityAware

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also { it.setStreamHandler(this) }
        nfcAdapter = NfcAdapter.getDefaultAdapter(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cancelSession("Plugin detached")
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attachActivity(binding.activity)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attachActivity(binding.activity)

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onDetachedFromActivity() = detachActivity()

    private fun attachActivity(newActivity: Activity) {
        activity = newActivity
        newActivity.application.registerActivityLifecycleCallbacks(this)
        if (session != null) enableReaderMode()
    }

    private fun detachActivity() {
        disableReaderMode()
        activity?.application?.unregisterActivityLifecycleCallbacks(this)
        activity = null
    }

    // endregion

    // region Activity lifecycle (reader mode must be re-enabled on every resume)

    override fun onActivityResumed(a: Activity) {
        if (a === activity && session != null) enableReaderMode()
    }

    override fun onActivityPaused(a: Activity) {
        if (a === activity) disableReaderMode()
    }

    override fun onActivityCreated(a: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(a: Activity) {}
    override fun onActivityStopped(a: Activity) {}
    override fun onActivitySaveInstanceState(a: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(a: Activity) {}

    // endregion

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readPassport" -> {
                if (pendingResult != null) {
                    result.error("SCAN_IN_PROGRESS", "A scan is already in progress", null)
                    return
                }
                val adapter = nfcAdapter
                if (adapter == null) {
                    result.error("NFC_NOT_AVAILABLE", "This device does not support NFC", null)
                    return
                }
                if (!adapter.isEnabled) {
                    result.error("NFC_DISABLED", "NFC is turned off. Please enable it in device settings.", null)
                    return
                }
                if (activity == null) {
                    result.error("READ_ERROR", "No foreground activity to attach the NFC reader to", null)
                    return
                }

                val docNumber = call.argument<String>("documentNumber") ?: ""
                val dob = call.argument<String>("dateOfBirth") ?: ""
                val expiry = call.argument<String>("dateOfExpiry") ?: ""
                if (docNumber.isBlank() || dob.isBlank() || expiry.isBlank()) {
                    result.error("INVALID_ARGUMENTS", "Document number, date of birth and expiry date are required", null)
                    return
                }

                pendingResult = result
                session = ScanSession(docNumber = docNumber, dob = dob, expiry = expiry)

                enableReaderMode()
                sendEvent(
                    "waitingForTag",
                    "Lay the phone flat on the passport and hold still. The chip may be in the front cover, back cover or photo page."
                )
            }
            "cancel" -> {
                cancelSession("Scan was cancelled by user")
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun cancelSession(reason: String) {
        disableReaderMode()
        session = null
        pendingResult?.error("SCAN_CANCELLED", reason, null)
        pendingResult = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun enableReaderMode() {
        val adapter = nfcAdapter ?: return
        val currentActivity = activity ?: return
        val flags = NfcAdapter.FLAG_READER_NFC_A or
                NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
        val extras = Bundle().apply {
            putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, PRESENCE_CHECK_DELAY_MS)
        }
        try {
            adapter.enableReaderMode(currentActivity, { tag -> onTagDiscovered(tag) }, flags, extras)
        } catch (e: IllegalStateException) {
            // Activity not resumed yet; onActivityResumed will enable it.
            Log.i(TAG, "Reader mode deferred until activity resumes: ${e.message}")
        }
    }

    private fun disableReaderMode() {
        val currentActivity = activity ?: return
        try {
            nfcAdapter?.disableReaderMode(currentActivity)
        } catch (e: IllegalStateException) {
            Log.i(TAG, "disableReaderMode ignored: ${e.message}")
        }
    }

    private fun sendEvent(step: String, message: String, progress: Int? = null) {
        mainHandler.post {
            val event = mutableMapOf<String, Any>("step" to step, "message" to message)
            if (progress != null) event["progress"] = progress
            eventSink?.success(event)
        }
    }

    private fun onTagDiscovered(tag: Tag) {
        val s = session ?: return

        val isoDep = IsoDep.get(tag)
        if (isoDep == null) {
            sendEvent("waitingForTag", "That doesn't look like a passport chip. Lay the phone flat on the passport.")
            return
        }

        // A re-discovered tag can arrive while the previous read is still unwinding; ignore it.
        if (!readInProgress.compareAndSet(false, true)) return

        sendEvent("tagDiscovered", "Passport detected. Hold still...")

        thread {
            try {
                readWithReconnect(isoDep, s)
            } finally {
                try {
                    isoDep.close()
                } catch (_: Exception) {
                }
                readInProgress.set(false)
            }
        }
    }

    /**
     * Runs a read on [isoDep]. On a dropped connection it first tries to reconnect to the same tag
     * (covers brief coupling glitches without the user noticing), then falls back to waiting for a
     * re-tap with reader mode left on. Progress is kept in [s] so nothing is re-read.
     */
    private fun readWithReconnect(isoDep: IsoDep, s: ScanSession) {
        var reconnects = 0
        while (true) {
            if (session !== s) return
            try {
                val resultMap = readPassport(isoDep, s)
                finishSuccess(s, resultMap)
                return
            } catch (e: Exception) {
                if (session !== s) return
                Log.w(TAG, "Read attempt failed", e)

                if (isCredentialError(e)) {
                    finishError(s, "Authentication failed. Please verify the passport number, date of birth and expiry date.")
                    return
                }

                s.transientFailures++
                if (s.transientFailures > MAX_TRANSIENT_FAILURES) {
                    finishError(s, "Failed to read passport: ${e.localizedMessage ?: e.message ?: "Unknown error"}")
                    return
                }

                if (reconnects < MAX_IN_PLACE_RECONNECTS && tryReconnect(isoDep)) {
                    reconnects++
                    sendEvent("tagConnected", "Reconnected. Hold still...")
                    continue
                }

                mainHandler.post { activity?.window?.decorView?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS) }
                val resumeHint = when {
                    s.dg2Length > 0 -> " Progress is saved (${dg2Percent(s)}%)."
                    s.dg1Bytes != null -> " Progress is saved."
                    else -> ""
                }
                sendEvent(
                    "connectionLost",
                    "Connection lost. Place the phone back on the passport and keep it still.$resumeHint"
                )
                return
            }
        }
    }

    private fun tryReconnect(isoDep: IsoDep): Boolean {
        return try {
            try {
                isoDep.close()
            } catch (_: Exception) {
            }
            isoDep.connect()
            true
        } catch (e: Exception) {
            Log.i(TAG, "In-place reconnect failed: ${e.message}")
            false
        }
    }

    private fun readPassport(isoDep: IsoDep, s: ScanSession): Map<String, Any?> {
        if (!isoDep.isConnected) isoDep.connect()
        isoDep.timeout = ISO_DEP_TIMEOUT_MS
        val cardService: CardService = try {
            IsoDepCardService(isoDep)
        } catch (e: Throwable) {
            CardService.getInstance(isoDep)
        }
        cardService.open()

        val service = PassportService(
            cardService,
            PassportService.NORMAL_MAX_TRANCEIVE_LENGTH,
            PassportService.DEFAULT_MAX_BLOCKSIZE,
            false,
            false
        )
        service.open()

        sendEvent("tagConnected", "Connected to passport chip. Hold still...")

        authenticate(service, s)

        // DG1 (Identity / MRZ) - small, read in one go and cached across taps
        if (s.dg1Bytes == null) {
            sendEvent("readingDg1", "Reading personal details... Hold still.")
            s.dg1Bytes = readFileFully(service, PassportService.EF_DG1)
            sendEvent("dg1Success", "DG1 read successfully")
        }
        val dg1File = DG1File(ByteArrayInputStream(s.dg1Bytes))

        // DG2 (Facial image) - large; read incrementally so a dropped connection resumes mid-file
        var faceImageBytes: ByteArray? = null
        if (!s.dg2Done) {
            try {
                readDg2Resumable(service, s)
            } catch (e: Exception) {
                // Access denied / file not found won't change on retry; finish without the photo.
                // Anything else (tag lost, garbled secure-messaging response from weak coupling)
                // is retried, resuming from the bytes already read.
                val sw = findStatusWord(e)
                if (sw != SW_SECURITY_STATUS_NOT_SATISFIED && sw != SW_FILE_NOT_FOUND) throw e
                Log.w(TAG, "DG2 not readable (SW=${Integer.toHexString(sw)}), skipping photo")
            }
        }
        if (s.dg2Done) {
            try {
                faceImageBytes = extractFaceImage(s.dg2Buffer.toByteArray())
            } catch (e: Exception) {
                Log.w(TAG, "DG2 parsing failed: ${e.message}")
            }
        }

        val mrz = dg1File.mrzInfo
        return mapOf(
            "documentNumber" to (mrz.documentNumber?.replace("<", "")?.trim() ?: s.docNumber),
            "surname" to (mrz.primaryIdentifier?.replace("<", " ")?.trim() ?: ""),
            "givenNames" to (mrz.secondaryIdentifier?.replace("<", " ")?.trim() ?: ""),
            "nationality" to (mrz.nationality ?: ""),
            "dateOfBirth" to (mrz.dateOfBirth ?: s.dob),
            "sex" to (mrz.gender?.toString() ?: ""),
            "dateOfExpiry" to (mrz.dateOfExpiry ?: s.expiry),
            "faceImage" to faceImageBytes,
            "paceSucceeded" to s.paceSucceeded,
            "bacSucceeded" to s.bacSucceeded,
            "dg1Read" to true,
            "dg2Read" to (faceImageBytes != null),
            "passiveAuthentication" to false,
            "rawMrz" to dg1File.toString()
        )
    }

    /**
     * PACE if the chip offers it, otherwise BAC. Whatever is learned (PACE params, or that PACE
     * doesn't work with this chip) is cached in [s] so a re-tap skips straight to what works.
     */
    private fun authenticate(service: PassportService, s: ScanSession) {
        val bacKey: BACKeySpec = BACKey(s.docNumber, s.dob, s.expiry)
        var paceOk = false
        var paceFailed = false
        s.paceSucceeded = false
        s.bacSucceeded = false

        if (!s.skipPace) {
            try {
                val paceInfo = s.paceInfo ?: CardAccessFile(service.getInputStream(PassportService.EF_CARD_ACCESS))
                    .securityInfos
                    .filterIsInstance<PACEInfo>()
                    .firstOrNull()
                    .also { s.paceInfo = it }

                if (paceInfo == null) {
                    s.skipPace = true
                } else {
                    sendEvent("authenticating", "Authenticating (PACE)... Hold still.")
                    service.doPACE(
                        bacKey,
                        paceInfo.objectIdentifier,
                        PACEInfo.toParameterSpec(paceInfo.parameterId),
                        null
                    )
                    paceOk = true
                    s.paceSucceeded = true
                    sendEvent("paceSuccess", "PACE authentication succeeded")
                }
            } catch (e: Exception) {
                if (isConnectionLost(e)) throw e
                Log.i(TAG, "PACE failed, falling back to BAC: ${e.message}")
                paceFailed = true
            }
        }

        service.sendSelectApplet(paceOk)

        if (!paceOk) {
            sendEvent("authenticating", "Authenticating (BAC)... Hold still.")
            service.doBAC(bacKey)
            s.bacSucceeded = true
            // Only stop trying PACE once BAC is known to work; a PACE failure caused by a
            // flaky connection shouldn't lock a PACE-only chip out on the next tap.
            if (paceFailed) s.skipPace = true
            sendEvent("bacSuccess", "BAC authentication succeeded")
        }
    }

    private fun readFileFully(service: PassportService, fid: Short): ByteArray {
        val input = service.getInputStream(fid)
        val bytes = ByteArray(input.length)
        DataInputStream(input).readFully(bytes)
        return bytes
    }

    private fun readDg2Resumable(service: PassportService, s: ScanSession) {
        val input = service.getInputStream(PassportService.EF_DG2)
        s.dg2Length = input.length
        val alreadyRead = s.dg2Buffer.size()
        if (alreadyRead > 0) {
            // CardFileInputStream.skip() just moves the file offset; no bytes are transferred.
            input.skip(alreadyRead.toLong())
        }

        var lastReported = -1
        sendEvent("readingDg2", "Reading photo... Hold still.", dg2Percent(s))
        val chunk = ByteArray(PassportService.DEFAULT_MAX_BLOCKSIZE)
        while (s.dg2Buffer.size() < s.dg2Length) {
            val toRead = minOf(chunk.size, s.dg2Length - s.dg2Buffer.size())
            val n = input.read(chunk, 0, toRead)
            if (n < 0) break
            // Only bytes actually returned are committed, so a drop mid-chunk leaves a valid prefix.
            s.dg2Buffer.write(chunk, 0, n)

            val percent = dg2Percent(s)
            if (percent >= lastReported + 5) {
                lastReported = percent
                sendEvent("readingDg2", "Reading photo... Hold still.", percent)
            }
        }
        s.dg2Done = true
        sendEvent("dg2Success", "DG2 read successfully", 100)
    }

    private fun dg2Percent(s: ScanSession): Int =
        if (s.dg2Length <= 0) 0 else (s.dg2Buffer.size() * 100 / s.dg2Length)

    private fun extractFaceImage(dg2Bytes: ByteArray): ByteArray? {
        val dg2File = DG2File(ByteArrayInputStream(dg2Bytes))
        val faceImageInfo = dg2File.faceInfos
            .flatMap { it.faceImageInfos }
            .firstOrNull() ?: return null
        val buffer = ByteArray(faceImageInfo.imageLength)
        DataInputStream(faceImageInfo.imageInputStream).readFully(buffer)
        return buffer
    }

    private fun isConnectionLost(e: Throwable): Boolean {
        var t: Throwable? = e
        while (t != null) {
            if (t is TagLostException) return true
            val msg = t.message?.lowercase() ?: ""
            if ("tag was lost" in msg || "transceive failed" in msg || "connection lost" in msg ||
                "out of date" in msg || "not connected" in msg || "tag is lost" in msg
            ) return true
            t = t.cause
        }
        return false
    }

    /** Status word of the first [CardServiceException] in the cause chain, or -1. */
    private fun findStatusWord(e: Throwable): Int {
        var t: Throwable? = e
        while (t != null) {
            if (t is CardServiceException && t.sw != CardServiceException.SW_NONE) return t.sw
            t = t.cause
        }
        return -1
    }

    /** Wrong document number / DOB / expiry: retrying won't help, so fail immediately. */
    private fun isCredentialError(e: Exception): Boolean {
        if (isConnectionLost(e)) return false
        var t: Throwable? = e
        while (t != null) {
            if (t is BACDeniedException || t is AccessDeniedException) return true
            t = t.cause
        }
        return findStatusWord(e) == SW_AUTH_FAILED
    }

    private fun finishSuccess(s: ScanSession, resultMap: Map<String, Any?>) {
        mainHandler.post {
            if (session !== s) return@post
            session = null
            disableReaderMode()
            sendEvent("completed", "Passport reading completed successfully")
            pendingResult?.success(resultMap)
            pendingResult = null
        }
    }

    private fun finishError(s: ScanSession, errorMsg: String) {
        mainHandler.post {
            if (session !== s) return@post
            session = null
            disableReaderMode()
            sendEvent("error", errorMsg)
            pendingResult?.error("READ_ERROR", errorMsg, null)
            pendingResult = null
        }
    }
}
