package com.miagendaia.mi_agenda_ia
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
object AlarmScheduler {
 private const val PREFS="agenda_alarm_requests"
 fun schedule(context:Context,id:String,title:String,triggerAt:Long,alertMode:String,occurrenceKey:String){val am=context.getSystemService(Context.ALARM_SERVICE) as AlarmManager;val code=("$id|$occurrenceKey".hashCode() and 0x7fffffff);val intent=Intent(context,AlarmReceiver::class.java).apply{putExtra("id",id);putExtra("title",title);putExtra("alertMode",alertMode)};val pi=PendingIntent.getBroadcast(context,code,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE);if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.S&&!am.canScheduleExactAlarms())am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,triggerAt,pi)else am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,triggerAt,pi);val prefs=context.getSharedPreferences(PREFS,Context.MODE_PRIVATE);val set=prefs.getStringSet(id,emptySet())?.toMutableSet()?:mutableSetOf();set.add(code.toString());prefs.edit().putStringSet(id,set).apply()}
 fun cancelItem(context:Context,id:String){val am=context.getSystemService(Context.ALARM_SERVICE) as AlarmManager;val prefs=context.getSharedPreferences(PREFS,Context.MODE_PRIVATE);for(raw in prefs.getStringSet(id,emptySet())?:emptySet()){val code=raw.toIntOrNull()?:continue;val pi=PendingIntent.getBroadcast(context,code,Intent(context,AlarmReceiver::class.java),PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE);if(pi!=null){am.cancel(pi);pi.cancel()}};prefs.edit().remove(id).apply();AlarmService.stopAlarm(context)}
}
