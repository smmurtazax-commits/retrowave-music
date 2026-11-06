package com.murtazarizvi.retrowave_music

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.provider.Settings
import android.view.ViewGroup
import androidx.mediarouter.app.MediaRouteButton
import androidx.mediarouter.media.MediaRouteSelector
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.Session
import com.google.android.gms.cast.framework.SessionManagerListener
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * RetroWave native side.
 *
 * Channel "retrowave/audiofx": the phone's built-in audio effects engine
 * (android.media.audiofx) attached to the player's audio session — the
 * equalizer, bass boost and virtualizer — plus helpers for the phone's
 * own effects page, the playback channel's lock-screen visibility, and
 * the system app-settings page.
 *
 * Channel "retrowave/cast": Google Cast session handling. The Dart side
 * serves the song files over the local network; this side owns the Cast
 * session and loads the queue onto the receiver.
 */
class MainActivity : FlutterFragmentActivity() {

    private val fxChannelName = "retrowave/audiofx"
    private val castChannelName = "retrowave/cast"
    private val playbackChannelId = "com.murtazarizvi.retrowave.channel.audio"

    // --- audiofx ---
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var currentSession: Int = -1

    // --- cast ---
    private var castChannel: MethodChannel? = null
    private var castContext: CastContext? = null
    private var sessionListener: SessionManagerListener<Session>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupFxChannel(flutterEngine)
        setupCastChannel(flutterEngine)
    }

    // ------------------------------------------------------------------
    // Audio effects channel
    // ------------------------------------------------------------------

    private fun setupFxChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fxChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "init" -> {
                            val session = call.argument<Int>("sessionId") ?: -1
                            if (session >= 0) {
                                initEffects(session)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }
                        "info" -> result.success(effectsInfo())
                        "setBandLevel" -> {
                            val band = call.argument<Int>("band") ?: 0
                            val level = call.argument<Int>("level") ?: 0
                            equalizer?.setBandLevel(band.toShort(), level.toShort())
                            result.success(true)
                        }
                        "usePreset" -> {
                            val preset = call.argument<Int>("preset") ?: 0
                            equalizer?.usePreset(preset.toShort())
                            result.success(true)
                        }
                        "setBassBoost" -> {
                            val strength = call.argument<Int>("strength") ?: 0
                            bassBoost?.let {
                                it.enabled = strength > 0
                                if (strength > 0) it.setStrength(strength.toShort())
                            }
                            result.success(true)
                        }
                        "setVirtualizer" -> {
                            val strength = call.argument<Int>("strength") ?: 0
                            virtualizer?.let {
                                it.enabled = strength > 0
                                if (strength > 0) it.setStrength(strength.toShort())
                            }
                            result.success(true)
                        }
                        "openSystemEffects" -> {
                            openSystemEffects()
                            result.success(true)
                        }
                        "setLockScreenControls" -> {
                            val on = call.argument<Boolean>("on") ?: true
                            setLockScreenControls(on)
                            result.success(true)
                        }
                        "openAppSettings" -> {
                            openAppSettings()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("AUDIOFX_ERROR", e.message, null)
                }
            }
    }

    private fun initEffects(session: Int) {
        if (session == currentSession && equalizer != null) return
        releaseEffects()
        currentSession = session
        equalizer = Equalizer(0, session).apply { enabled = true }
        try {
            bassBoost = BassBoost(0, session)
        } catch (e: Exception) {
            bassBoost = null
        }
        try {
            virtualizer = Virtualizer(0, session)
        } catch (e: Exception) {
            virtualizer = null
        }
    }

    private fun releaseEffects() {
        try { equalizer?.release() } catch (e: Exception) {}
        try { bassBoost?.release() } catch (e: Exception) {}
        try { virtualizer?.release() } catch (e: Exception) {}
        equalizer = null
        bassBoost = null
        virtualizer = null
        currentSession = -1
    }

    private fun effectsInfo(): Map<String, Any> {
        val eq = equalizer ?: return mapOf("available" to false)
        return try {
            val bands = eq.numberOfBands.toInt()
            val range = eq.bandLevelRange
            mapOf(
                "available" to true,
                "bands" to bands,
                "low" to range[0].toInt(),
                "high" to range[1].toInt(),
                "freqs" to (0 until bands).map { eq.getCenterFreq(it.toShort()) },
                "levels" to (0 until bands).map { eq.getBandLevel(it.toShort()).toInt() },
                "presets" to (0 until eq.numberOfPresets.toInt()).map {
                    eq.getPresetName(it.toShort())
                },
                "currentPreset" to eq.currentPreset.toInt()
            )
        } catch (e: Exception) {
            mapOf("available" to false)
        }
    }

    private fun openSystemEffects() {
        // 1) The phone's own audio-effects panel for this session
        //    (on Samsung this can open SoundAlive / the effects page).
        try {
            val panel = Intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL).apply {
                if (currentSession >= 0) {
                    putExtra(AudioEffect.EXTRA_AUDIO_SESSION, currentSession)
                }
                putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
                putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
            }
            startActivity(panel)
            return
        } catch (e: Exception) {
            // fall through to sound settings
        }
        // 2) Fallback: system sound settings.
        try {
            startActivity(Intent(Settings.ACTION_SOUND_SETTINGS))
        } catch (e: Exception) {
            // Nothing else we can do — the user can open Settings manually.
        }
    }

    /**
     * Creates the playback notification channel early with the saved
     * lock-screen visibility, so the "Control music from Lock screen"
     * setting decides whether the media controls appear on the lock
     * screen. (Channel visibility is fixed at channel creation, so this
     * runs at app start, before the playback service creates its own.)
     */
    private fun setLockScreenControls(on: Boolean) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                playbackChannelId,
                "RetroWave playback",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.lockscreenVisibility =
                if (on) android.app.Notification.VISIBILITY_PUBLIC
                else android.app.Notification.VISIBILITY_SECRET
            nm.createNotificationChannel(channel)
        } catch (e: Exception) {
            // Non-fatal: playback controls simply keep the default behaviour.
        }
    }

    private fun openAppSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (e: Exception) {
            // ignore
        }
    }

    // ------------------------------------------------------------------
    // Cast channel
    // ------------------------------------------------------------------

    private fun setupCastChannel(flutterEngine: FlutterEngine) {
        castChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, castChannelName)
        castChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "showRoutePicker" -> {
                        showCastPicker()
                        result.success(true)
                    }
                    "loadQueue" -> {
                        val items = call.argument<List<Map<String, Any>>>("items")
                            ?: emptyList()
                        val start = call.argument<Int>("startIndex") ?: 0
                        loadCastQueue(items, start)
                        result.success(true)
                    }
                    "stopCasting" -> {
                        castContext?.sessionManager?.endCurrentSession(true)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("CAST_ERROR", e.message, null)
            }
        }
        try {
            castContext = CastContext.getSharedInstance(this)
            val listener = object : SessionManagerListener<Session> {
                override fun onSessionStarted(session: Session, sessionId: String) {
                    castChannel?.invokeMethod("sessionStarted", null)
                }
                override fun onSessionEnded(session: Session, reason: Int) {
                    castChannel?.invokeMethod("sessionEnded", null)
                }
                override fun onSessionStarting(session: Session) {}
                override fun onSessionStartFailed(session: Session, error: Int) {}
                override fun onSessionEnding(session: Session) {}
                override fun onSessionResuming(session: Session, sessionId: String) {}
                override fun onSessionResumed(session: Session, wasSuspended: Boolean) {
                    castChannel?.invokeMethod("sessionStarted", null)
                }
                override fun onSessionResumeFailed(session: Session, error: Int) {}
                override fun onSessionSuspended(session: Session, reason: Int) {}
            }
            sessionListener = listener
            castContext?.sessionManager?.addSessionManagerListener(
                listener, Session::class.java
            )
        } catch (e: Exception) {
            // Cast unavailable on this device (e.g. no Play services):
            // the rest of the app is unaffected.
            castContext = null
        }
    }

    private fun showCastPicker() {
        val button = MediaRouteButton(this)
        button.routeSelector = MediaRouteSelector.Builder()
            .addControlCategory(
                CastMediaControlIntent.categoryForCast(
                    CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID
                )
            )
            .build()
        // MediaRouteButton can only show its chooser dialog while attached
        // to a window, so attach it invisibly (1x1) and click it.
        addContentView(button, ViewGroup.LayoutParams(1, 1))
        button.performClick()
    }

    private fun loadCastQueue(items: List<Map<String, Any>>, startIndex: Int) {
        val session = castContext?.sessionManager?.currentCastSession ?: return
        val client = session.remoteMediaClient ?: return
        val queueItems = items.map { m ->
            val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK)
            meta.putString(MediaMetadata.KEY_TITLE, m["title"] as? String ?: "")
            meta.putString(MediaMetadata.KEY_ARTIST, m["artist"] as? String ?: "")
            meta.putString(MediaMetadata.KEY_ALBUM_TITLE, m["album"] as? String ?: "")
            val url = m["url"] as? String ?: ""
            val info = MediaInfo.Builder(url)
                .setContentUrl(url)
                .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                .setContentType(m["mime"] as? String ?: "audio/mpeg")
                .setMetadata(meta)
                .setStreamDuration((m["durationMs"] as? Number)?.toLong() ?: 0L)
                .build()
            MediaQueueItem.Builder(info).setAutoplay(true).build()
        }.toTypedArray()
        client.queueLoad(queueItems, startIndex, MediaStatus.REPEAT_MODE_ALL, null)
    }

    override fun onDestroy() {
        releaseEffects()
        try {
            sessionListener?.let {
                castContext?.sessionManager?.removeSessionManagerListener(
                    it, Session::class.java
                )
            }
        } catch (e: Exception) {
            // ignore
        }
        super.onDestroy()
    }
}
