import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

const red = Color(0xffc62828), navy = Color(0xff17324d), bg = Color(0xfff7f8fa);
String hash(String value) => sha256.convert(utf8.encode(value)).toString();
String now() => DateTime.now().toIso8601String();
String fmt(String? v) => v == null ? '—' : DateFormat('yyyy/MM/dd – HH:mm').format(DateTime.parse(v));

class Db {
  static Database? _db;
  static Future<Database> get db async => _db ??= await openDatabase(p.join(await getDatabasesPath(), 'asaafni_database.db'), version: 1, onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'), onCreate: (d, v) async {
    await d.execute('CREATE TABLE Users(id INTEGER PRIMARY KEY AUTOINCREMENT, fullName TEXT NOT NULL, phone TEXT UNIQUE NOT NULL, email TEXT, passwordHash TEXT NOT NULL, role TEXT NOT NULL, createdAt TEXT)');
    await d.execute('CREATE TABLE Patients(id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER, patientName TEXT NOT NULL, phone TEXT, age INTEGER, gender TEXT, FOREIGN KEY(userId) REFERENCES Users(id) ON DELETE CASCADE)');
    await d.execute('CREATE TABLE Ambulances(id INTEGER PRIMARY KEY AUTOINCREMENT, vehicleNumber TEXT UNIQUE NOT NULL, ambulanceType TEXT, status TEXT, driverId INTEGER, latitude REAL, longitude REAL)');
    await d.execute('CREATE TABLE Drivers(id INTEGER PRIMARY KEY AUTOINCREMENT, fullName TEXT NOT NULL, phone TEXT, ambulanceId INTEGER, availabilityStatus TEXT)');
    await d.execute('CREATE TABLE AmbulanceRequests(id INTEGER PRIMARY KEY AUTOINCREMENT, requestNumber TEXT UNIQUE NOT NULL, userId INTEGER, patientId INTEGER, emergencyType TEXT, description TEXT, severity TEXT, latitude REAL, longitude REAL, address TEXT, neighborhood TEXT, landmark TEXT, requestDate TEXT, requestTime TEXT, status TEXT, ambulanceId INTEGER, driverId INTEGER, cancellationReason TEXT, FOREIGN KEY(userId) REFERENCES Users(id), FOREIGN KEY(patientId) REFERENCES Patients(id))');
    await d.execute('CREATE TABLE Notifications(id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER, requestId INTEGER, title TEXT, message TEXT, createdAt TEXT, isRead INTEGER DEFAULT 0)');
    await d.execute('CREATE TABLE RequestStatusHistory(id INTEGER PRIMARY KEY AUTOINCREMENT, requestId INTEGER, oldStatus TEXT, newStatus TEXT, changedAt TEXT, notes TEXT)');
    await d.execute('CREATE TABLE AppSettings(id INTEGER PRIMARY KEY AUTOINCREMENT, settingKey TEXT UNIQUE, settingValue TEXT)');
    await seed(d);
  });
  static Future<void> seed(Database d) async {
    final u = await d.insert('Users', {'fullName':'مستخدم تجريبي','phone':'0912345678','email':'demo@asaafni.local','passwordHash':hash('123456'),'role':'patient','createdAt':now()});
    await d.insert('Users', {'fullName':'سائق تجريبي','phone':'0999999999','email':'driver@asaafni.local','passwordHash':hash('123456'),'role':'driver','createdAt':now()});
    await d.insert('Users', {'fullName':'مدير النظام','phone':'admin@asaafni.local','email':'admin@asaafni.local','passwordHash':hash('admin123'),'role':'admin','createdAt':now()});
    await d.insert('Drivers', {'fullName':'سائق تجريبي','phone':'0999999999','availabilityStatus':'متاح'});
    await d.insert('Ambulances', {'vehicleNumber':'ATB-001','ambulanceType':'إسعاف أساسي','status':'متاحة'});
    await d.insert('Ambulances', {'vehicleNumber':'ATB-002','ambulanceType':'إسعاف مجهز','status':'متاحة'});
    await d.insert('Ambulances', {'vehicleNumber':'ATB-003','ambulanceType':'إسعاف أساسي','status':'خارج الخدمة'});
    await d.insert('AppSettings', {'settingKey':'emergencyPhone','settingValue':'123'});
    await d.insert('Patients', {'userId':u,'patientName':'مستخدم تجريبي','phone':'0912345678','age':30,'gender':'ذكر'});
  }
  static Future<List<Map<String,dynamic>>> q(String sql,[List<Object?> args=const[]]) async => (await db).rawQuery(sql,args);
}

class AppState extends ChangeNotifier {
  Map<String,dynamic>? user; List<Map<String,dynamic>> requests=[]; List<Map<String,dynamic>> notifications=[];
  Future<bool> login(String id,String pass) async { final r=await Db.q('SELECT * FROM Users WHERE (phone=? OR email=?) AND passwordHash=?',[id,id,hash(pass)]); if(r.isEmpty)return false; user=r.first; await load(); notifyListeners(); return true; }
  Future<bool> register(String name,String phone,String email,String pass) async { try { final d=await Db.db; await d.insert('Users',{'fullName':name,'phone':phone,'email':email,'passwordHash':hash(pass),'role':'patient','createdAt':now()}); return await login(phone,pass); } catch(_){return false;} }
  Future<void> load() async { if(user==null)return; requests=await Db.q('SELECT * FROM AmbulanceRequests WHERE userId=? ORDER BY id DESC',[user!['id']]); notifications=await Db.q('SELECT * FROM Notifications WHERE userId=? ORDER BY id DESC',[user!['id']]); }
  Future<String> createRequest(Map<String,dynamic> data) async { final d=await Db.db; final n='ASF-${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}'; final patient=await d.insert('Patients',{'userId':user!['id'],'patientName':data['patientName'],'phone':data['patientPhone'],'age':data['age'],'gender':data['gender']}); final payload=Map<String,dynamic>.from(data)..remove('patientName')..remove('patientPhone')..remove('age')..remove('gender')..['patientId']=patient; final id=await d.insert('AmbulanceRequests',{...payload,'requestNumber':n,'userId':user!['id'],'requestDate':DateFormat('yyyy-MM-dd').format(DateTime.now()),'requestTime':now(),'status':'تم استلام الطلب'}); await d.insert('RequestStatusHistory',{'requestId':id,'newStatus':'تم استلام الطلب','changedAt':now(),'notes':'تم إنشاء الطلب'}); await d.insert('Notifications',{'userId':user!['id'],'requestId':id,'title':'تم استلام الطلب','message':'رقم طلبك $n','createdAt':now()}); await load(); notifyListeners(); return n; }
  Future<void> logout() async {user=null;requests=[];notifyListeners();}
}

void main() async { WidgetsFlutterBinding.ensureInitialized(); await Db.db; runApp(ChangeNotifierProvider(create:(_)=>AppState(),child:const AsaafniApp())); }
  class AsaafniApp extends StatelessWidget { const AsaafniApp({super.key}); @override Widget build(BuildContext c)=>MaterialApp(debugShowCheckedModeBanner:false,title:'أسعفني',theme:ThemeData(useMaterial3:true,scaffoldBackgroundColor:bg,colorScheme:ColorScheme.fromSeed(seedColor:red),fontFamily:'sans-serif'),builder:(c,w)=>Directionality(textDirection:ui.TextDirection.rtl,child:w!),home:const Splash()); }
class Splash extends StatefulWidget {
  const Splash({super.key});
  @override State<Splash> createState() => _SplashState();
}
class _SplashState extends State<Splash> {
  @override void initState() { super.initState(); Future.delayed(const Duration(milliseconds:900), () { if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Login())); }); }
  @override Widget build(BuildContext c) => Scaffold(
    backgroundColor: red,
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
      Icon(Icons.local_hospital, size: 96, color: Colors.white),
      SizedBox(height: 18),
      Text('أسعفني Asaafni', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text('معك في حالات الطوارئ', style: TextStyle(color: Colors.white70, fontSize: 17)),
    ])),
  );
}

InputDecoration dec(String label,{String? hint})=>InputDecoration(labelText:label,hintText:hint,filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none));
Widget field(TextEditingController x,String label,{bool obscure=false,TextInputType? type})=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:x,obscureText:obscure,keyboardType:type,decoration:dec(label)));
class Login extends StatefulWidget {
  const Login({super.key});
  @override State<Login> createState() => _LoginState();
}
class _LoginState extends State<Login> {
  final id=TextEditingController(), pw=TextEditingController();
  Future<void> go() async { final ok=await context.read<AppState>().login(id.text.trim(),pw.text); if(!mounted)return; if(ok) Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const Home())); else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('بيانات الدخول غير صحيحة'))); }
  @override Widget build(BuildContext c)=>Scaffold(body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[const SizedBox(height:35),const Icon(Icons.local_hospital,color:red,size:72),const Text('تسجيل الدخول',textAlign:TextAlign.center,style:TextStyle(fontSize:28,fontWeight:FontWeight.bold,color:navy)),const SizedBox(height:25),field(id,'رقم الهاتف أو البريد الإلكتروني'),field(pw,'كلمة المرور',obscure:true),ElevatedButton(onPressed:go,style:ElevatedButton.styleFrom(backgroundColor:red,foregroundColor:Colors.white),child:const Text('تسجيل الدخول')),TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const Register())),child:const Text('إنشاء حساب جديد')),const Card(child:Padding(padding:EdgeInsets.all(12),child:Text('تجريبي: 0912345678 / 123456\nالمدير: admin@asaafni.local / admin123',textAlign:TextAlign.center)))])));
}
class Register extends StatefulWidget { const Register({super.key}); @override State<Register> createState()=>_RegisterState(); }
class _RegisterState extends State<Register> {
 final n=TextEditingController(),p=TextEditingController(),e=TextEditingController(),a=TextEditingController(),b=TextEditingController();
 Future<void> go() async { if(n.text.isEmpty||p.text.isEmpty||a.text.length<6||a.text!=b.text){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تحقق من البيانات وكلمة المرور')));return;} final ok=await context.read<AppState>().register(n.text,p.text,e.text,a.text); if(!mounted)return; if(ok)Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const Home()),(_)=>false); else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('رقم الهاتف مستخدم مسبقاً'))); }
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('إنشاء حساب')),body:ListView(padding:const EdgeInsets.all(20),children:[field(n,'الاسم الكامل'),field(p,'رقم الهاتف'),field(e,'البريد الإلكتروني'),field(a,'كلمة المرور',obscure:true),field(b,'تأكيد كلمة المرور',obscure:true),ElevatedButton(onPressed:go,style:ElevatedButton.styleFrom(backgroundColor:red,foregroundColor:Colors.white),child:const Text('إنشاء الحساب'))]));
}
class Home extends StatelessWidget { const Home({super.key}); @override Widget build(BuildContext c){final s=c.watch<AppState>(); return Scaffold(appBar:AppBar(title:const Text('أسعفني'),actions:[IconButton(onPressed:()=>c.read<AppState>().logout().then((_){if(c.mounted)Navigator.pushAndRemoveUntil(c,MaterialPageRoute(builder:(_)=>const Login()),(_)=>false);}),icon:const Icon(Icons.logout))]),body:ListView(padding:const EdgeInsets.all(18),children:[Text('مرحباً، ${s.user?['fullName']}',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:navy)),const SizedBox(height:18),Card(color:red,child:InkWell(onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const RequestPage())),child:const Padding(padding:EdgeInsets.all(25),child:Center(child:Text('اطلب سيارة إسعاف الآن',style:TextStyle(color:Colors.white,fontSize:21,fontWeight:FontWeight.bold))))),),const SizedBox(height:12),Row(children:[Expanded(child:_tile(c,'السجل',Icons.history,()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const History())))),const SizedBox(width:10),Expanded(child:_tile(c,'الملف الشخصي',Icons.person,()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const Profile()))))]),const SizedBox(height:18),const Text('آخر الطلبات',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),...s.requests.take(3).map((r)=>Card(child:ListTile(title:Text(r['requestNumber']),subtitle:Text('${r['emergencyType']} – ${r['status']}'),onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>Track(r:r))))))]));}}
Widget _tile(BuildContext c,String t,IconData i,VoidCallback f)=>Card(child:InkWell(onTap:f,child:Padding(padding:const EdgeInsets.all(18),child:Column(children:[Icon(i,color:red,size:32),Text(t)]))));
class RequestPage extends StatefulWidget { const RequestPage({super.key}); @override State<RequestPage> createState()=>_RequestState(); }
class _RequestState extends State<RequestPage> {
 final name=TextEditingController(),phone=TextEditingController(),age=TextEditingController(),desc=TextEditingController(),neigh=TextEditingController(),land=TextEditingController(),addr=TextEditingController(); String type='مرض مفاجئ',gender='ذكر',severity='متوسطة'; double? lat,lon;
 Future<void> gps() async { try{final x=await Geolocator.getCurrentPosition();setState((){lat=x.latitude;lon=x.longitude;addr.text='الموقع الحالي عبر GPS';});}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر تحديد الموقع؛ أدخل العنوان يدوياً')));}}
 Future<void> send() async {if(name.text.isEmpty||phone.text.isEmpty||(addr.text.isEmpty&&neigh.text.isEmpty&&lat==null)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أكمل بيانات المريض والموقع')));return;} final n=await context.read<AppState>().createRequest({'patientName':name.text,'patientPhone':phone.text,'age':int.tryParse(age.text),'gender':gender,'emergencyType':type,'description':desc.text,'severity':severity,'latitude':lat,'longitude':lon,'address':addr.text,'neighborhood':neigh.text,'landmark':land.text});if(mounted)Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>Confirmation(number:n)));}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('طلب سيارة إسعاف')),body:ListView(padding:const EdgeInsets.all(18),children:[const Text('بيانات المريض',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold,color:navy)),field(name,'اسم المريض الكامل'),field(phone,'رقم الهاتف'),field(age,'العمر'),DropdownButtonFormField(value:gender,decoration:dec('الجنس'),items:['ذكر','أنثى','آخر'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x)=>setState(()=>gender=x!)),const SizedBox(height:12),DropdownButtonFormField(value:type,decoration:dec('نوع الحالة'),items:['مرض مفاجئ','حادث مروري','إصابة','حالة أخرى'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x)=>setState(()=>type=x!)),DropdownButtonFormField(value:severity,decoration:dec('درجة الخطورة'),items:['منخفضة','متوسطة','عالية','حرجة'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x)=>setState(()=>severity=x!)),field(desc,'وصف الحالة'),OutlinedButton.icon(onPressed:gps,icon:const Icon(Icons.my_location),label:const Text('استخدام موقعي الحالي')),if(lat!=null)Text('الإحداثيات: $lat, $lon'),field(addr,'العنوان اليدوي'),field(neigh,'اسم الحي'),field(land,'أقرب معلم'),ElevatedButton(onPressed:send,style:ElevatedButton.styleFrom(backgroundColor:red,foregroundColor:Colors.white),child:const Text('إرسال طلب الإسعاف'))]));
}
class Confirmation extends StatelessWidget { final String number; const Confirmation({super.key,required this.number}); @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('تأكيد الطلب')),body:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.check_circle,color:Colors.green,size:90),const Text('تم استلام طلبك بنجاح',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),Text('رقم الطلب: $number',style:const TextStyle(fontSize:20,color:red)),ElevatedButton(onPressed:()=>Navigator.pushAndRemoveUntil(c,MaterialPageRoute(builder:(_)=>const Home()),(_)=>false),child:const Text('الرئيسية'))]))); }
class Track extends StatelessWidget { final Map<String,dynamic> r; const Track({super.key,required this.r}); static const stages=['تم استلام الطلب','جارٍ البحث عن سيارة إسعاف','تم قبول الطلب','سيارة الإسعاف في الطريق','وصلت سيارة الإسعاف','تم إكمال الطلب']; @override Widget build(BuildContext c){final idx=max(0,stages.indexOf(r['status']));return Scaffold(appBar:AppBar(title:Text(r['requestNumber'])),body:ListView(padding:const EdgeInsets.all(20),children:[Text('${r['emergencyType']} – ${r['severity']}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text('الموقع: ${r['address']??r['neighborhood']??'—'}'),...List.generate(stages.length,(i)=>ListTile(leading:CircleAvatar(backgroundColor:i<=idx?red:Colors.grey,child:Icon(i<=idx?Icons.check:Icons.circle_outlined,color:Colors.white)),title:Text(stages[i]),subtitle:i==idx?const Text('الحالة الحالية'):null))]));}}
class History extends StatelessWidget {
  const History({super.key});
  @override Widget build(BuildContext c) {
    final rs=c.watch<AppState>().requests;
    final items=rs.map<Widget>((r) => ListTile(
      title: Text(r['requestNumber']),
      subtitle: Text('${r['emergencyType']} – ${r['status']}'),
      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Track(r: r))),
    )).toList();
    return Scaffold(appBar: AppBar(title: const Text('سجل الطلبات')), body: ListView(children: items));
  }
}
class Profile extends StatelessWidget { const Profile({super.key}); @override Widget build(BuildContext c){final u=c.watch<AppState>().user!;return Scaffold(appBar:AppBar(title:const Text('الملف الشخصي')),body:ListView(padding:const EdgeInsets.all(20),children:[CircleAvatar(radius:42,backgroundColor:red,child:Text((u['fullName'] as String).substring(0,1),style:const TextStyle(fontSize:32,color:Colors.white))),const SizedBox(height:20),Card(child:ListTile(title:Text(u['fullName']),subtitle:Text('${u['phone']}\n${u['email']??'لا يوجد بريد'}'))),const SizedBox(height:20),const Text('النسخة المحلية: البيانات محفوظة على هذا الهاتف فقط.',textAlign:TextAlign.center)]));}}
