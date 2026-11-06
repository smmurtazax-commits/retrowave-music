package com.murtazarizvi.retrowave_music

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.ViewGroup
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
 *
 * Channel "retrowave/media": the device media library — permission
 * checks/requests plus MediaStore queries for songs, albums, artists
 * and album artwork. This replaces the unmaintained on_audio_query
 * plugin, whose Android module cannot build on current AGP versions.
 */
class MainActivity : FlutterFragmentActivity() {

    private val fxChannelName = "retrowave/audiofx"
    private val castChannelName = "retrowave/cast"
    private val mediaChannelName = "retrowave/media"
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
        setupMediaChannel(flutterEngine)
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
    // Media library channel (MediaStore)
    // ------------------------------------------------------------------

    private val mediaPermRequestCode = 9201
    private var pendingPermResult: MethodChannel.Result? = null

    private fun audioPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            Manifest.permission.READ_MEDIA_AUDIO
        else
            Manifest.permission.READ_EXTERNAL_STORAGE

    private fun setupMediaChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "permissionsStatus" -> result.success(
                            ContextCompat.checkSelfPermission(
                                this, audioPermission()
                            ) == PackageManager.PERMISSION_GRANTED
                        )
                        "permissionsRequest" -> {
                            if (ContextCompat.checkSelfPermission(
                                    this, audioPermission()
                                ) == PackageManager.PERMISSION_GRANTED
                            ) {
                                result.success(true)
                            } else {
                                pendingPermResult = result
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(audioPermission()),
                                    mediaPermRequestCode
                                )
                            }
                        }
                        "querySongs" -> runMediaQuery(result) { querySongsList(null, null) }
                        "queryAlbums" -> runMediaQuery(result) { queryAlbumsList() }
                        "queryArtists" -> runMediaQuery(result) { queryArtistsList() }
                        "queryAudiosFrom" -> {
                            val type = call.argument<String>("type") ?: "album"
                            val id = (call.argument<Number>("id"))?.toLong() ?: -1L
                            val column =
                                if (type == "artist") MediaStore.Audio.Media.ARTIST_ID
                                else MediaStore.Audio.Media.ALBUM_ID
                            runMediaQuery(result) {
                                querySongsList("$column = ?", arrayOf(id.toString()))
                            }
                        }
                        "queryArtwork" -> {
                            val id = (call.argument<Number>("id"))?.toLong() ?: -1L
                            val type = call.argument<String>("type") ?: "AUDIO"
                            runMediaQuery(result) { artworkBytes(id, type) }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("MEDIA_ERROR", e.message, null)
                }
            }
    }

    /** MediaStore work runs off the main thread; results post back to it. */
    private fun runMediaQuery(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            try {
                val value = work()
                Handler(Looper.getMainLooper()).post { result.success(value) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result.error("MEDIA_ERROR", e.message, null)
                }
            }
        }.start()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == mediaPermRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermResult?.success(granted)
            pendingPermResult = null
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun querySongsList(
        selection: String?,
        selectionArgs: Array<String>?
    ): List<Map<String, Any?>> {
        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA
        )
        val sel = if (selection == null)
            MediaStore.Audio.Media.IS_MUSIC + " != 0"
        else
            MediaStore.Audio.Media.IS_MUSIC + " != 0 AND (" + selection + ")"
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            uri, projection, sel, selectionArgs, MediaStore.Audio.Media.TITLE + " ASC"
        )?.use { c ->
            val iId = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val iTitle = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val iArtist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val iAlbum = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val iAlbumId = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val iDuration = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val iData = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            while (c.moveToNext()) {
                val id = c.getLong(iId)
                val data = c.getString(iData) ?: ""
                var title = c.getString(iTitle)
                if (title.isNullOrBlank()) {
                    title = data.substringAfterLast('/').substringBeforeLast('.')
                }
                val ext = data.substringAfterLast('.', "").lowercase()
                out.add(
                    mapOf(
                        "id" to id,
                        "data" to data,
                        "uri" to ContentUris.withAppendedId(uri, id).toString(),
                        "title" to title,
                        "artist" to c.getString(iArtist),
                        "album" to c.getString(iAlbum),
                        "albumId" to c.getLong(iAlbumId),
                        "duration" to c.getLong(iDuration),
                        "fileExtension" to ext.ifEmpty { null }
                    )
                )
            }
        }
        return out
    }

    private fun queryAlbumsList(): List<Map<String, Any?>> {
        val uri = MediaStore.Audio.Albums.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Albums._ID,
            MediaStore.Audio.Albums.ALBUM,
            MediaStore.Audio.Albums.ARTIST,
            MediaStore.Audio.Albums.NUMBER_OF_SONGS
        )
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            uri, projection, null, null, MediaStore.Audio.Albums.ALBUM + " ASC"
        )?.use { c ->
            val iId = c.getColumnIndexOrThrow(MediaStore.Audio.Albums._ID)
            val iAlbum = c.getColumnIndexOrThrow(MediaStore.Audio.Albums.ALBUM)
            val iArtist = c.getColumnIndexOrThrow(MediaStore.Audio.Albums.ARTIST)
            val iCount = c.getColumnIndexOrThrow(MediaStore.Audio.Albums.NUMBER_OF_SONGS)
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(iId),
                        "album" to c.getString(iAlbum),
                        "artist" to c.getString(iArtist),
                        "numOfSongs" to c.getInt(iCount)
                    )
                )
            }
        }
        return out
    }

    private fun queryArtistsList(): List<Map<String, Any?>> {
        val uri = MediaStore.Audio.Artists.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Artists._ID,
            MediaStore.Audio.Artists.ARTIST,
            MediaStore.Audio.Artists.NUMBER_OF_TRACKS,
            MediaStore.Audio.Artists.NUMBER_OF_ALBUMS
        )
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            uri, projection, null, null, MediaStore.Audio.Artists.ARTIST + " ASC"
        )?.use { c ->
            val iId = c.getColumnIndexOrThrow(MediaStore.Audio.Artists._ID)
            val iArtist = c.getColumnIndexOrThrow(MediaStore.Audio.Artists.ARTIST)
            val iTracks = c.getColumnIndexOrThrow(MediaStore.Audio.Artists.NUMBER_OF_TRACKS)
            val iAlbums = c.getColumnIndexOrThrow(MediaStore.Audio.Artists.NUMBER_OF_ALBUMS)
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(iId),
                        "artist" to c.getString(iArtist),
                        "numberOfTracks" to c.getInt(iTracks),
                        "numberOfAlbums" to c.getInt(iAlbums)
                    )
                )
            }
        }
        return out
    }

    private fun artworkBytes(id: Long, type: String): ByteArray? {
        val albumId: Long = when (type) {
            "ALBUM" -> id
            "ARTIST" -> return null // MediaStore has no reliable artist art
            else -> { // AUDIO: resolve the song's album first
                var found: Long? = null
                contentResolver.query(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Audio.Media.ALBUM_ID),
                    MediaStore.Audio.Media._ID + " = ?",
                    arrayOf(id.toString()),
                    null
                )?.use { c ->
                    if (c.moveToFirst()) found = c.getLong(0)
                }
                found ?: return null
            }
        }
        val artUri = ContentUris.withAppendedId(
            Uri.parse("content://media/external/audio/albumart"), albumId
        )
        return try {
            contentResolver.openInputStream(artUri)?.use { it.readBytes() }
        } catch (e: Exception) {
            null
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
