package com.miagendaia.mi_agenda_ia
import android.content.Context
object PendingAlarmActions {private const val PREFS="agenda_pending_actions";fun set(context:Context,action:String,itemId:String){context.getSharedPreferences(PREFS,Context.MODE_PRIVATE).edit().putString("action",action).putString("itemId",itemId).apply()} fun consume(context:Context):Map<String,String>?{val p=context.getSharedPreferences(PREFS,Context.MODE_PRIVATE);val a=p.getString("action",null)?:return null;val id=p.getString("itemId",null)?:return null;p.edit().clear().apply();return mapOf("action" to a,"itemId" to id)}}
