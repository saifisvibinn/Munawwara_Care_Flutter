package com.munawwaracare.android

import android.content.Context
import android.location.Location
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class LocationHeartbeatWorker(
    private val context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        const val WORK_NAME = "tameny_location_heartbeat"
        const val TAG = "TamenyHeartbeat"
    }

    override suspend fun doWork(): Result {
        Log.d(TAG, "WorkManager job fired — getting location")
        
        return try {
            val location = getCurrentLocation()
            if (location != null) {
                sendHeartbeat(location)
                Log.d(TAG, "Heartbeat sent: ${location.latitude}, ${location.longitude}")
                Result.success()
            } else {
                Log.w(TAG, "Could not get location")
                Result.retry()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Heartbeat failed: ${e.message}")
            Result.retry()
        }
    }

    private suspend fun getCurrentLocation(): Location? {
        return suspendCancellableCoroutine { continuation ->
            val fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)
            val cancellationToken = CancellationTokenSource()
            
            try {
                fusedLocationClient.getCurrentLocation(
                    Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                    cancellationToken.token
                ).addOnSuccessListener { location ->
                    continuation.resume(location)
                }.addOnFailureListener { exception ->
                    continuation.resumeWithException(exception)
                }
                
                continuation.invokeOnCancellation {
                    cancellationToken.cancel()
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "Location permission denied")
                continuation.resume(null)
            }
        }
    }

    private fun sendHeartbeat(location: Location) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        val token = prefs.getString("flutter.pilgrim_auth_token", null) ?: return
        val serverUrl = prefs.getString("flutter.server_url", null) ?: return
        
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
        
        val json = JSONObject().apply {
            put("latitude", location.latitude)
            put("longitude", location.longitude)
            put("accuracy", location.accuracy)
            put("source", "workmanager_periodic")
            put("timestamp", System.currentTimeMillis())
        }
        
        val body = json.toString().toRequestBody("application/json".toMediaType())
        
        val request = Request.Builder()
            .url("$serverUrl/api/location/heartbeat")
            .post(body)
            .addHeader("Authorization", "Bearer $token")
            .addHeader("Content-Type", "application/json")
            .build()
        
        client.newCall(request).execute().use { response ->
            Log.d(TAG, "Heartbeat response: ${response.code}")
        }
    }
}
