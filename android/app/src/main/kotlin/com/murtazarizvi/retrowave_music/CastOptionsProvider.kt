package com.murtazarizvi.retrowave_music

import android.content.Context
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

/**
 * Google Cast options: use the default media receiver, so no custom
 * receiver registration is needed. Referenced from AndroidManifest via
 * the OPTIONS_PROVIDER_CLASS_NAME meta-data.
 */
class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions {
        return CastOptions.Builder()
            .setReceiverApplicationId(
                CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID
            )
            .build()
    }

    override fun getAdditionalSessionProviders(
        context: Context
    ): MutableList<SessionProvider>? = null
}
