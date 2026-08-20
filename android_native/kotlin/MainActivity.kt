package com.miagendaia.mi_agenda_ia
import android.Manifest
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
class MainActivity:FlutterActivity(){override fun configureFlutterEngine(engine:FlutterEngine){super.configureFlutterEngine(engine);MethodChannel(engine.dartExecutor.binaryMessenger,"com.miagendaia/alarm").setMethodCallHandler{call,result->when(call.method){"scheduleAlarm"->{AlarmScheduler.schedule(this,call.argument<String>("id")?:"",call.argument<String>("title")?:"Recordatorio",call.argument<Number>("timestamp")?.toLong()?:0L,call.argument<String>("alertMode")?:"soundAndVibration",call.argument<String>("occurrenceKey")?:"0");result.success(null)};"cancelItem"->{AlarmScheduler.cancelItem(this,call.argument<String>("id")?:"");result.success(null)};"consumePendingAction"->result.success(PendingAlarmActions.consume(this));"requestAlarmPermissions"->{requestAlarmPermissions();result.success(null)};else->result.notImplemented()}}}
 private fun requestAlarmPermissions(){if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.TIRAMISU)ActivityCompat.requestPermissions(this,arrayOf(Manifest.permission.POST_NOTIFICATIONS),2001);if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.S){val am=getSystemService(Context.ALARM_SERVICE) as AlarmManager;if(!am.canScheduleExactAlarms())startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,Uri.parse("package:$packageName")))};if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.UPSIDE_DOWN_CAKE)try{startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,Uri.parse("package:$packageName")))}catch(_:Exception){}}
}
