package com.khush.movienight.data

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Transaction
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface LibraryDao {
    @Query("SELECT * FROM sources ORDER BY addedAt")
    fun sources(): Flow<List<LibrarySource>>

    @Query("SELECT * FROM sources")
    suspend fun allSources(): List<LibrarySource>

    @Query("SELECT * FROM sources WHERE id = :id")
    suspend fun source(id: String): LibrarySource?

    @Upsert
    suspend fun upsert(source: LibrarySource)

    @Delete
    suspend fun delete(source: LibrarySource)

    @Query("SELECT * FROM items")
    fun items(): Flow<List<MediaItem>>

    @Query("SELECT * FROM items WHERE sourceId = :sourceId")
    suspend fun items(sourceId: String): List<MediaItem>

    @Query("SELECT * FROM items WHERE `key` = :key")
    suspend fun item(key: String): MediaItem?

    @Upsert
    suspend fun upsert(items: List<MediaItem>)

    @Query("DELETE FROM items WHERE `key` IN (:keys)")
    suspend fun deleteItems(keys: List<String>)

    @Query("UPDATE items SET progressSeconds = :seconds, lastPlayedAt = :playedAt, isFinished = :finished WHERE `key` = :key")
    suspend fun setWatchState(key: String, seconds: Double, playedAt: Long?, finished: Boolean)

    @Query("SELECT * FROM watch_records WHERE nameKey = :nameKey")
    suspend fun records(nameKey: String): List<WatchRecord>

    @Insert
    suspend fun insert(records: List<WatchRecord>)

    @Query("DELETE FROM watch_records WHERE id = :id")
    suspend fun deleteRecord(id: Long)

    @Transaction
    suspend fun replaceItems(upserts: List<MediaItem>, deletions: List<String>) {
        if (deletions.isNotEmpty()) deleteItems(deletions)
        if (upserts.isNotEmpty()) upsert(upserts)
    }
}

@Database(entities = [LibrarySource::class, MediaItem::class, WatchRecord::class], version = 1)
abstract class LibraryDatabase : RoomDatabase() {
    abstract fun dao(): LibraryDao

    companion object {
        fun open(context: Context): LibraryDatabase =
            Room.databaseBuilder(context, LibraryDatabase::class.java, "library.db").build()
    }
}
