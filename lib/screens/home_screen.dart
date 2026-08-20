import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/agenda_item.dart';
import '../services/alarm_bridge.dart';
import '../services/intent_parser.dart';
import '../services/storage_service.dart';
import '../widgets/item_card.dart';

enum HomeFilter { all, tasks, reminders }

class HomeScreen extends StatefulWidget { const HomeScreen({super.key}); @override State<HomeScreen> createState()=>_HomeScreenState(); }

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final stt.SpeechToText _speech=stt.SpeechToText();
  final IntentParser _parser=IntentParser(); final StorageService _storage=StorageService(); final AlarmBridge _alarms=AlarmBridge();
  final TextEditingController _typedController=TextEditingController();
  List<AgendaItem> _items=[]; bool _listening=false, _speechReady=false; String? _speechLocaleId; String _heard='', _userName=''; int _tabIndex=0; HomeFilter _homeFilter=HomeFilter.all;

  @override void initState(){ super.initState(); WidgetsBinding.instance.addObserver(this); unawaited(_load()); unawaited(_initializeSpeech()); }
  @override void dispose(){ WidgetsBinding.instance.removeObserver(this); unawaited(_speech.cancel()); _typedController.dispose(); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state){ if(state==AppLifecycleState.resumed) unawaited(_consumeAlarmAction()); }

  Future<void> _load() async { final items=await _storage.loadItems(); final name=await _storage.loadUserName(); if(!mounted)return; setState((){_items=items;_userName=name?.trim()??'';}); await _consumeAlarmAction(); if(_userName.isEmpty){ WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)unawaited(_askName());});}}
  Future<void> _consumeAlarmAction() async { final a=await _alarms.consumePendingAction(); if(a==null||!mounted)return; final i=_items.indexWhere((e)=>e.id==a.itemId); if(i<0)return; final item=_items[i]; if(a.action=='ok'){ if(item.type==AgendaItemType.reminder||item.type==AgendaItemType.event){ final ended=item.recurrence==RecurrenceType.none||(item.recurrenceEnd!=null&&item.recurrenceEnd!.isBefore(DateTime.now())); if(ended){ await _replaceItem(_clone(item, archived:true, archivedAt:DateTime.now(), updatedAt:DateTime.now()), reschedule:false); } } return; } if(a.action=='reprogram'){ WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)unawaited(_openEditor(item,isNew:false));}); }}
  AgendaItem _clone(AgendaItem i,{bool? archived,DateTime? archivedAt,DateTime? updatedAt})=>AgendaItem(id:i.id,type:i.type,title:i.title,rawText:i.rawText,dateTime:i.dateTime,completed:i.completed,progress:i.progress,alertMode:i.alertMode,ringtoneUri:i.ringtoneUri,ringtoneTitle:i.ringtoneTitle,recurrence:i.recurrence,weekdays:i.weekdays,recurrenceEnd:i.recurrenceEnd,archived:archived??i.archived,archivedAt:archivedAt??i.archivedAt,createdAt:i.createdAt,updatedAt:updatedAt??i.updatedAt);
  Future<void> _replaceItem(AgendaItem item,{required bool reschedule}) async { final u=[item,..._items.where((e)=>e.id!=item.id)]..sort((a,b)=>b.updatedAt.compareTo(a.updatedAt)); setState(()=>_items=u); await _storage.saveItems(u); if(reschedule) await _alarms.scheduleItem(item); else await _alarms.cancelItem(item.id); }

  Future<void> _askName() async { var draft=_userName; final result=await showDialog<String>(context:context,barrierDismissible:_userName.isNotEmpty,builder:(c)=>AlertDialog(title:Text(_userName.isEmpty?'¿Cómo te llamas?':'Editar nombre'),content:TextFormField(initialValue:_userName,autofocus:true,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'Tu nombre',border:OutlineInputBorder()),onChanged:(v)=>draft=v,onFieldSubmitted:(v){final t=v.trim();if(t.isNotEmpty)Navigator.pop(c,t);}),actions:[if(_userName.isNotEmpty)TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancelar')),FilledButton(onPressed:(){final t=draft.trim();if(t.isNotEmpty)Navigator.pop(c,t);},child:const Text('Guardar'))])); if(result==null||!mounted)return; await _storage.saveUserName(result); if(mounted)setState(()=>_userName=result); }

  Future<void> _initializeSpeech() async { try{final available=await _speech.initialize();String? localeId;if(available){final locales=await _speech.locales();for(final preferred in ['es_EC','es-EC','es_ES','es-ES']){for(final l in locales){if(l.localeId.toLowerCase()==preferred.toLowerCase()){localeId=l.localeId;break;}}if(localeId!=null)break;} localeId??=locales.where((l)=>l.localeId.toLowerCase().startsWith('es')).map((l)=>l.localeId).firstOrNull;} if(mounted)setState((){_speechReady=available;_speechLocaleId=localeId;});}catch(_){if(mounted)setState(()=>_speechReady=false);} }
  Future<void> _startListening() async { if(!_speechReady){_showTypedFallback();return;} setState((){_listening=true;_heard='';}); try{await _speech.listen(listenOptions:stt.SpeechListenOptions(localeId:_speechLocaleId,partialResults:true,cancelOnError:true,listenMode:stt.ListenMode.confirmation,pauseFor:const Duration(seconds:4),listenFor:const Duration(seconds:30)),onResult:(r){if(!mounted)return;final x=r.recognizedWords.trim();setState(()=>_heard=x);if(r.finalResult&&x.isNotEmpty){unawaited(_speech.stop());setState(()=>_listening=false);unawaited(_createFromText(x));}});}catch(_){if(mounted){setState(()=>_listening=false);_showTypedFallback();}} }
  Future<void> _stopListening() async { await _speech.stop(); if(!mounted)return;setState(()=>_listening=false);final t=_heard.trim();if(t.isNotEmpty)await _createFromText(t); }
  void _showTypedFallback(){_typedController.clear();showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('Escribe tu orden'),content:TextField(controller:_typedController,autofocus:true,maxLines:3,decoration:const InputDecoration(hintText:'Ej.: Recuérdame llamar mañana a las 9',border:OutlineInputBorder())),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancelar')),FilledButton(onPressed:(){final t=_typedController.text.trim();Navigator.pop(c);if(t.isNotEmpty)unawaited(_createFromText(t));},child:const Text('Interpretar'))]));}
  Future<void> _createFromText(String text) async {final p=_parser.parse(text),now=DateTime.now();await _openEditor(AgendaItem(id:now.microsecondsSinceEpoch.toString(),type:p.type,title:p.title,rawText:p.rawText,dateTime:p.dateTime,createdAt:now,updatedAt:now),isNew:true);}

  Future<void> _openEditor(AgendaItem item,{required bool isNew}) async {
    var title=item.title,type=item.type,date=item.dateTime,alert=item.alertMode,recurrence=item.recurrence,end=item.recurrenceEnd,progress=item.type==AgendaItemType.task?item.progress:0,weekdays=List<int>.from(item.weekdays);bool delete=false;
    final result=await showModalBottomSheet<AgendaItem>(context:context,isScrollControlled:true,useSafeArea:true,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(28))),builder:(sheet)=>StatefulBuilder(builder:(sheet,setS){final needs=type!=AgendaItemType.note;
      Future<void> pickDate() async{final now=DateTime.now(),initial=date!=null&&date!.isAfter(now.subtract(const Duration(days:1)))?date!:now.add(const Duration(hours:1));final d=await showDatePicker(context:sheet,firstDate:DateTime(now.year,now.month,now.day),lastDate:DateTime(now.year+10,12,31),initialDate:initial);if(d==null||!sheet.mounted)return;final t=await showTimePicker(context:sheet,initialTime:TimeOfDay.fromDateTime(initial));if(t!=null)setS(()=>date=DateTime(d.year,d.month,d.day,t.hour,t.minute));}
      Future<void> pickEnd() async{final start=date??DateTime.now();final d=await showDatePicker(context:sheet,firstDate:DateTime(start.year,start.month,start.day),lastDate:DateTime(start.year+10,12,31),initialDate:end??start.add(const Duration(days:30)));if(d!=null)setS(()=>end=DateTime(d.year,d.month,d.day,23,59));}
      Future<void> pickTone() async {
        final selected = await _alarms.pickRingtone(toneUri);
        if (selected != null && sheet.mounted) {
          setS(() {
            toneUri = selected.uri;
            toneTitle = selected.title;
          });
        }
      }

      Future<void> previewTone() async {
        if (toneUri == null) {
          final selected = await _alarms.pickRingtone(toneUri);
          if (selected == null || !sheet.mounted) return;
          setS(() {
            toneUri = selected.uri;
            toneTitle = selected.title;
          });
        }
        if (toneUri != null) {
          await _alarms.previewRingtone(toneUri!);
        }
      }

      final usesSound = alert == AlertMode.soundAndVibration ||
          alert == AlertMode.strong ||
          alert == AlertMode.soundOnly;

      return SingleChildScrollView(padding:EdgeInsets.fromLTRB(22,22,22,MediaQuery.of(sheet).viewInsets.bottom+26),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(isNew?'Confirmar actividad':'Editar actividad',style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:18),TextFormField(initialValue:item.title,maxLines:2,decoration:const InputDecoration(labelText:'Título',border:OutlineInputBorder()),onChanged:(v)=>title=v),const SizedBox(height:14),DropdownButtonFormField<AgendaItemType>(initialValue:type,decoration:const InputDecoration(labelText:'Tipo',border:OutlineInputBorder()),items:AgendaItemType.values.map((v)=>DropdownMenuItem(value:v,child:Text(_typeName(v)))).toList(),onChanged:(v)=>setS((){type=v??type;if(type==AgendaItemType.note){date=null;progress=0;recurrence=RecurrenceType.none;end=null;}})),if(needs)...[const SizedBox(height:12),ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.event),title:Text(date==null?'Fecha y hora obligatorias':_formatDate(date!)),subtitle:const Text('Toca para seleccionar o cambiar'),onTap:pickDate),DropdownButtonFormField<AlertMode>(initialValue:alert,decoration:const InputDecoration(labelText:'Tipo de alarma',border:OutlineInputBorder()),items:AlertMode.values.map((v)=>DropdownMenuItem(value:v,child:Text(_alertName(v)))).toList(),onChanged:(v)=>setS(()=>alert=v??alert)),if(usesSound)...[const SizedBox(height:10),Card(elevation:0,color:const Color(0xFFF6F8FC),child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.music_note),title:Text(toneTitle??'Elegir tono del teléfono'),subtitle:const Text('Puedes escoger tonos de llamada, mensajes o alarmas'),trailing:const Icon(Icons.chevron_right),onTap:pickTone),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:previewTone,icon:const Icon(Icons.play_arrow),label:const Text('Probar tono'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:_alarms.stopRingtonePreview,icon:const Icon(Icons.stop),label:const Text('Detener prueba')))])]))],const SizedBox(height:12),DropdownButtonFormField<RecurrenceType>(initialValue:recurrence,decoration:const InputDecoration(labelText:'Repetición',border:OutlineInputBorder()),items:RecurrenceType.values.map((v)=>DropdownMenuItem(value:v,child:Text(_recurrenceName(v)))).toList(),onChanged:(v)=>setS((){recurrence=v??recurrence;if(recurrence==RecurrenceType.none){end=null;weekdays=[];}})),if(recurrence==RecurrenceType.weekly)...[const SizedBox(height:10),Wrap(spacing:6,children:List.generate(7,(i){final d=i+1;return FilterChip(label:Text(_weekdayShort(d)),selected:weekdays.contains(d),onSelected:(s)=>setS((){if(s)weekdays.add(d);else weekdays.remove(d);}));}))],if(recurrence!=RecurrenceType.none)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.event_repeat),title:Text(end==null?'Fecha final obligatoria':'Hasta ${_formatDateOnly(end!)}'),onTap:pickEnd)],if(type==AgendaItemType.task)...[const SizedBox(height:16),Text('Avance: $progress%',style:const TextStyle(fontWeight:FontWeight.w700)),Slider(value:progress.toDouble(),min:0,max:100,divisions:20,label:'$progress%',onChanged:(v)=>setS(()=>progress=v.round()))],const SizedBox(height:18),SizedBox(width:double.infinity,height:52,child:FilledButton(onPressed:(){final t=title.trim();if(t.isEmpty){_snack(sheet,'Escribe un título.');return;}if(needs&&date==null){_snack(sheet,'Debes seleccionar fecha y hora.');return;}if(recurrence!=RecurrenceType.none&&end==null){_snack(sheet,'Selecciona hasta qué fecha se repetirá.');return;}if(recurrence==RecurrenceType.weekly&&weekdays.isEmpty){_snack(sheet,'Selecciona al menos un día.');return;}final p=type==AgendaItemType.task?progress:0,done=type==AgendaItemType.task&&p==100;Navigator.pop(sheet,AgendaItem(id:item.id,type:type,title:t,rawText:item.rawText,dateTime:needs?date:null,completed:done,progress:p,alertMode:alert,ringtoneUri:toneUri,ringtoneTitle:toneTitle,recurrence:recurrence,weekdays:weekdays,recurrenceEnd:end,archived:done,archivedAt:done?DateTime.now():null,createdAt:item.createdAt,updatedAt:DateTime.now()));},child:Text(isNew?'Guardar':'Guardar cambios'))),if(!isNew)TextButton.icon(onPressed:()async{final ok=await showDialog<bool>(context:sheet,builder:(c)=>AlertDialog(title:const Text('Eliminar actividad'),content:const Text('Esta acción no se puede deshacer.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Eliminar'))]));if(ok==true&&sheet.mounted){delete=true;Navigator.pop(sheet);}},icon:const Icon(Icons.delete_outline),label:const Text('Eliminar actividad'))]));}));
    if(!mounted)return;if(delete){await _alarms.cancelItem(item.id);final u=_items.where((e)=>e.id!=item.id).toList();setState(()=>_items=u);await _storage.saveItems(u);return;}if(result!=null)await _replaceItem(result,reschedule:!result.archived&&result.type!=AgendaItemType.note);
  }

  Future<void> _exportNotes() async{final notes=_items.where((e)=>e.type==AgendaItemType.note).toList();if(notes.isEmpty){_snack(context,'No tienes notas para exportar.');return;}final b=StringBuffer('MIS NOTAS - MI AGENDA IA\n\n');for(final n in notes){b..writeln(n.title)..writeln('Creada: ${_formatDate(n.createdAt)}')..writeln(n.rawText)..writeln('----------------------------------------');}final f=XFile.fromData(utf8.encode(b.toString()),mimeType:'text/plain');await SharePlus.instance.share(ShareParams(title:'Exportar notas',text:'Notas exportadas desde Mi Agenda IA',files:[f],fileNameOverrides:const ['mis_notas_mi_agenda.txt']));}

  List<AgendaItem> get _active=>_items.where((e)=>!e.archived).toList();List<AgendaItem> get _history=>_items.where((e)=>e.archived).toList()..sort((a,b)=>(b.archivedAt??b.updatedAt).compareTo(a.archivedAt??a.updatedAt));
  int _count(AgendaItemType t)=>_active.where((e)=>e.type==t).length;List<AgendaItem> get _home{switch(_homeFilter){case HomeFilter.all:return _active;case HomeFilter.tasks:return _active.where((e)=>e.type==AgendaItemType.task).toList();case HomeFilter.reminders:return _active.where((e)=>e.type==AgendaItemType.reminder).toList();}}
  List<AgendaItem> _of(AgendaItemType t)=>_active.where((e)=>e.type==t).toList()..sort((a,b){final x=a.dateTime,y=b.dateTime;if(x==null&&y==null)return b.updatedAt.compareTo(a.updatedAt);if(x==null)return 1;if(y==null)return -1;return x.compareTo(y);});

  @override Widget build(BuildContext context){final pages=[_buildHome(),_category('Calendario','Tus eventos programados',AgendaItemType.event),_notes(),_profile()];return Scaffold(backgroundColor:Colors.white,body:SafeArea(child:IndexedStack(index:_tabIndex,children:pages)),bottomNavigationBar:NavigationBar(selectedIndex:_tabIndex,onDestinationSelected:(i)=>setState(()=>_tabIndex=i),destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Inicio'),NavigationDestination(icon:Icon(Icons.calendar_month_outlined),selectedIcon:Icon(Icons.calendar_month),label:'Calendario'),NavigationDestination(icon:Icon(Icons.sticky_note_2_outlined),selectedIcon:Icon(Icons.sticky_note_2),label:'Notas'),NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'Perfil')]));}
  Future<void> _showVoiceHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Qué puedo decir?'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NOTA', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('“Anota revisar la postulación.”'),
              SizedBox(height: 14),
              Text('TAREA', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('“Tengo que entregar el informe el viernes a las 4.”'),
              SizedBox(height: 14),
              Text('RECORDATORIO', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('“Recuérdame tomar la pastilla mañana a las 8.”'),
              SizedBox(height: 14),
              Text('CALENDARIO', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('“Agenda reunión con el director el jueves a las 3.”'),
              SizedBox(height: 14),
              Text(
                'Después de hablar podrás corregir el tipo, la fecha, el tono y la repetición antes de guardar.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Widget _buildHome(){final f=_home;return CustomScrollView(slivers:[SliverPadding(padding:const EdgeInsets.fromLTRB(20,18,20,0),sliver:SliverList.list(children:[Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(_userName.isEmpty?'¡Hola! 👋':'¡Hola, $_userName! 👋',style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900)),const Text('Tu asistente personal',style:TextStyle(color:Color(0xFF64748B)))])),IconButton(onPressed:()=>setState(()=>_tabIndex=3),icon:const Icon(Icons.settings_outlined))]),const SizedBox(height:18),Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF0759D8),Color(0xFF0B78F0)]),borderRadius:BorderRadius.circular(22)),child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[_summary('Recordatorios',_count(AgendaItemType.reminder),Icons.notifications_none),_summary('Tareas',_count(AgendaItemType.task),Icons.task_alt),_summary('Notas',_count(AgendaItemType.note),Icons.sticky_note_2_outlined)])),const SizedBox(height:26),Row(children:[const Expanded(child:Text('Dímelo y yo lo organizo',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))),TextButton.icon(onPressed:_showVoiceHelp,icon:const Icon(Icons.help_outline),label:const Text('¿Qué puedo decir?'))]),const SizedBox(height:8),const Text('Habla de forma natural. Yo intento clasificarlo y tú confirmas antes de guardar.',style:TextStyle(color:Color(0xFF64748B))),const SizedBox(height:16),Center(child:GestureDetector(onTap:_listening?_stopListening:_startListening,onLongPress:_showTypedFallback,child:Container(width:132,height:132,decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFF075FE4)),child:Icon(_listening?Icons.stop_rounded:Icons.mic_rounded,color:Colors.white,size:58)))),const SizedBox(height:10),Center(child:Text(_listening?(_heard.isEmpty?'Te escucho…':_heard):'Toca para hablar · Mantén para escribir')),const SizedBox(height:24),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Organizador',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800)),TextButton(onPressed:_showTypedFallback,child:const Text('Añadir manual'))]),Wrap(spacing:8,children:[ChoiceChip(label:const Text('Todos'),selected:_homeFilter==HomeFilter.all,onSelected:(_)=>setState(()=>_homeFilter=HomeFilter.all)),ChoiceChip(label:const Text('Tareas'),selected:_homeFilter==HomeFilter.tasks,onSelected:(_)=>setState(()=>_homeFilter=HomeFilter.tasks)),ChoiceChip(label:const Text('Recordatorios'),selected:_homeFilter==HomeFilter.reminders,onSelected:(_)=>setState(()=>_homeFilter=HomeFilter.reminders))]),const SizedBox(height:12)])),if(f.isEmpty)const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.all(28),child:Center(child:Text('No hay elementos en esta categoría.'))))else SliverPadding(padding:const EdgeInsets.fromLTRB(20,0,20,32),sliver:SliverList.builder(itemCount:f.length,itemBuilder:(c,i)=>ItemCard(item:f[i],onTap:()=>_openEditor(f[i],isNew:false))))]);}
  Widget _category(String title,String sub,AgendaItemType type){final x=_of(type);return CustomScrollView(slivers:[SliverPadding(padding:const EdgeInsets.all(20),sliver:SliverList.list(children:[Text(title,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900)),Text(sub)])),if(x.isEmpty)const SliverToBoxAdapter(child:Center(child:Text('No hay elementos.')))else SliverPadding(padding:const EdgeInsets.symmetric(horizontal:20),sliver:SliverList.builder(itemCount:x.length,itemBuilder:(c,i)=>ItemCard(item:x[i],onTap:()=>_openEditor(x[i],isNew:false))))]);}
  Widget _notes(){final x=_of(AgendaItemType.note);return CustomScrollView(slivers:[SliverPadding(padding:const EdgeInsets.all(20),sliver:SliverList.list(children:[Row(children:[const Expanded(child:Text('Mis notas',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900))),FilledButton.icon(onPressed:_exportNotes,icon:const Icon(Icons.download_outlined),label:const Text('Exportar TXT'))])])),if(x.isEmpty)const SliverToBoxAdapter(child:Center(child:Text('Todavía no tienes notas.')))else SliverPadding(padding:const EdgeInsets.symmetric(horizontal:20),sliver:SliverList.builder(itemCount:x.length,itemBuilder:(c,i)=>ItemCard(item:x[i],onTap:()=>_openEditor(x[i],isNew:false))))]);}
  Widget _profile()=>ListView(padding:const EdgeInsets.all(20),children:[const Text('Perfil',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900)),const SizedBox(height:14),ListTile(leading:const Icon(Icons.person),title:Text(_userName.isEmpty?'Sin nombre':_userName),subtitle:const Text('Editar nombre'),onTap:_askName),ListTile(leading:const Icon(Icons.history),title:const Text('Historial'),subtitle:Text('${_history.length} elementos'),onTap:_showHistory),ListTile(leading:const Icon(Icons.alarm),title:const Text('Permisos de alarmas'),subtitle:const Text('Activa notificaciones, alarmas exactas y pantalla completa'),onTap:_alarms.requestPermissions)]);
  Future<void> _showHistory() async{final h=_history;await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(sheet)=>DraggableScrollableSheet(expand:false,initialChildSize:.8,maxChildSize:.95,builder:(c,ctrl)=>ListView(controller:ctrl,padding:const EdgeInsets.all(20),children:[const Text('Historial',style:TextStyle(fontSize:26,fontWeight:FontWeight.w900)),const SizedBox(height:12),if(h.isEmpty)const Text('Todavía no hay historial.')else...h.map((e)=>ItemCard(item:e,onTap:(){Navigator.pop(sheet);unawaited(_openEditor(e,isNew:false));}))])));}
  Widget _summary(String l,int v,IconData i)=>Column(children:[Icon(i,color:Colors.white),Text('$v',style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.bold)),Text(l,style:const TextStyle(color:Colors.white,fontSize:12))]);
  static void _snack(BuildContext c,String t)=>ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text(t)));
  static String _typeName(AgendaItemType t)=>switch(t){AgendaItemType.note=>'Nota',AgendaItemType.task=>'Tarea',AgendaItemType.reminder=>'Recordatorio',AgendaItemType.event=>'Calendario'};
  static String _alertName(AlertMode a)=>switch(a){AlertMode.soundAndVibration=>'Sonido + vibración',AlertMode.strong=>'Alarma fuerte + vibración',AlertMode.soundOnly=>'Solo sonido',AlertMode.vibrationOnly=>'Solo vibración',AlertMode.silent=>'Silencioso'};
  static String _recurrenceName(RecurrenceType r)=>switch(r){RecurrenceType.none=>'No repetir',RecurrenceType.daily=>'Todos los días',RecurrenceType.weekly=>'Días de la semana',RecurrenceType.monthly=>'Cada mes'};
  static String _weekdayShort(int d)=>switch(d){1=>'Lun',2=>'Mar',3=>'Mié',4=>'Jue',5=>'Vie',6=>'Sáb',7=>'Dom',_=>'?'};
  static String _formatDate(DateTime d){final h=d.hour.toString().padLeft(2,'0'),m=d.minute.toString().padLeft(2,'0');return '${d.day}/${d.month}/${d.year} · $h:$m';}
  static String _formatDateOnly(DateTime d)=>'${d.day}/${d.month}/${d.year}';
}
