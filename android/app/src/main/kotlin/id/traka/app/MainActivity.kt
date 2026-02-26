package id.traka.app

import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Looper
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {

    private val channelName = "traka/location"
    private var fusedLocationClient: FusedLocationProviderClient? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLocationWithMockCheck" -> getLocationWithMockCheck(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun getLocationWithMockCheck(result: MethodChannel.Result) {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }
        val latch = CountDownLatch(1)
        var locationResult: Location? = null
        var isMock = false
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            TimeUnit.SECONDS.toMillis(15)
        ).apply {
            setWaitForAccurateLocation(false)
            setMaxUpdates(1)
        }.build()
        val callback = object : LocationCallback() {
            override fun onLocationResult(lr: LocationResult) {
                lr.lastLocation?.let { loc ->
                    locationResult = loc
                    isMock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        loc.isMock
                    } else {
                        @Suppress("DEPRECATION")
                        loc.isFromMockProvider
                    }
                }
                latch.countDown()
            }
        }
        fusedLocationClient?.requestLocationUpdates(locationRequest, callback, Looper.getMainLooper())
            ?: run {
                result.error("UNAVAILABLE", "Location client not available", null)
                return
            }
        Thread {
            if (!latch.await(20, TimeUnit.SECONDS)) {
                runOnUiThread {
                    fusedLocationClient?.removeLocationUpdates(callback)
                    result.error("TIMEOUT", "Location request timeout", null)
                }
                return@Thread
            }
            runOnUiThread {
                fusedLocationClient?.removeLocationUpdates(callback)
                val loc = locationResult
                if (loc == null) {
                    result.error("NULL_LOCATION", "Could not get location", null)
                    return@runOnUiThread
                }
                val map = hashMapOf<String, Any>(
                    "latitude" to loc.latitude,
                    "longitude" to loc.longitude,
                    "isMock" to isMock
                )
                result.success(map)
            }
        }.start()
    }
}
