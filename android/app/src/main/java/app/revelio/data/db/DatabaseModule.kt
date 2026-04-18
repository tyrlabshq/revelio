package app.revelio.data.db

import android.content.Context
import androidx.room.Room
import app.revelio.data.auth.SecureTokenStore
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import net.sqlcipher.database.SupportFactory
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(
        @ApplicationContext context: Context,
        tokenStore: SecureTokenStore,
    ): RevelioDatabase {
        val passphrase = tokenStore.getOrCreateDbPassphrase()
        // SQLCipher for Android wants the key as a byte array; we copy it to
        // avoid holding the CharArray after handoff. The SupportFactory zeroes
        // the passphrase once it's been consumed by the native layer.
        val passBytes = String(passphrase).toByteArray(Charsets.UTF_8)
        val factory = SupportFactory(passBytes)

        return Room.databaseBuilder(
            context.applicationContext,
            RevelioDatabase::class.java,
            "revelio.db",
        )
            .openHelperFactory(factory)
            .fallbackToDestructiveMigration()
            .build()
    }

    @Provides
    fun provideScanHistoryDao(db: RevelioDatabase): ScanHistoryDao = db.scanHistoryDao()

    @Provides
    fun providePantryDao(db: RevelioDatabase): PantryDao = db.pantryDao()
}
