// تطبيق Smart Invoice Scanner (المبسط لمشروع التخرج)
// ** تم تعديل الكود الآن ليشمل زر "اختبار اتصال Gemini" وحل مشاكل التسميات القديمة **

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
// يجب أن يكون الإصدار المثبت هو ^0.4.7
import 'package:google_generative_ai/google_generative_ai.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🚨🚨 التنبيه الأهم: الإعدادات 🚨🚨
// 1. يجب أن يكون ملف firebase_options.dart مولدًا (باستخدام flutterfire configure).
import 'firebase_options.dart'; 
// 2. تم تحديث هذا المتغير بالمفتاح الجديد والفعلي الذي أرسلته.
const String geminiApiKey = "AIzaSyAoHLLE4LM6N4DAwHqJZ4fNGbsD_u10pVI"; // ⬅️ المفتاح الجديد تم وضعه هنا

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const InvoiceScannerApp());
}

// ====================================================================
// أولاً: نماذج البيانات المبسّطة (Simple Data Model)
// ====================================================================

class SimpleInvoice {
  final String id;
  final String invoiceNumber;
  final String dateTime;
  final double netValue;
  final double tax;
  final double total;
  
  SimpleInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.dateTime,
    required this.netValue,
    required this.tax,
    required this.total,
  });

  factory SimpleInvoice.fromJson(Map<String, dynamic> json) {
    return SimpleInvoice(
      id: json['id'] ?? UniqueKey().toString(),
      invoiceNumber: json['invoice_number'] ?? 'غير محدد',
      dateTime: json['date_time'] ?? 'غير محدد',
      netValue: (json['net_value'] as num?)?.toDouble() ?? 0.0, 
      tax: (json['tax'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoice_number': invoiceNumber,
        'date_time': dateTime,
        'net_value': netValue,
        'tax': tax,
        'total': total,
      };
}

// ====================================================================
// ثانياً: خدمة التخزين المحلي (Local Storage Service)
// ====================================================================

class LocalStorageService {
  static const _keyInvoices = 'invoices_list';

  static Future<List<SimpleInvoice>> loadInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    final String? invoicesString = prefs.getString(_keyInvoices);
    if (invoicesString == null) return [];

    final List<dynamic> invoicesJson = jsonDecode(invoicesString);
    return invoicesJson.map((json) => SimpleInvoice.fromJson(json)).toList();
  }

  static Future<void> saveInvoices(List<SimpleInvoice> invoices) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> invoicesJson =
        invoices.map((i) => i.toJson()).toList();
    await prefs.setString(_keyInvoices, jsonEncode(invoicesJson));
  }
}

// ====================================================================
// ثالثاً: هيكل التطبيق والمصادقة
// ====================================================================

class InvoiceScannerApp extends StatelessWidget {
  const InvoiceScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Invoice Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      // لضمان اللغة العربية من اليمين لليسار في كل مكان
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const AuthGate(),
    );
  }
}

// يتحقق من حالة المصادقة ويعرض شاشة الدخول أو الماسح الضوئي
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AuthScreen();
        }
        return const InvoiceScannerScreen();
      },
    );
  }
}

// ====================================================================
// رابعاً: شاشة المصادقة (Auth Screen)
// ====================================================================

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLogin = true; // للتبديل بين تسجيل الدخول والتسجيل
  String? _errorMessage;

  Future<void> _authenticate() async {
    setState(() => _errorMessage = null);
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'user-not-found') {
          _errorMessage = 'لم يتم العثور على هذا المستخدم.';
        } else if (e.code == 'wrong-password') {
          _errorMessage = 'كلمة المرور غير صحيحة.';
        } else if (e.code == 'email-already-in-use') {
          _errorMessage = 'هذا البريد الإلكتروني مُسجل بالفعل.';
        } else if (e.code == 'invalid-email') {
          _errorMessage = 'صيغة البريد الإلكتروني غير صحيحة.';
        } else if (e.code == 'weak-password') {
          _errorMessage = 'كلمة المرور ضعيفة جداً (أقل من 6 أحرف).';
        } else {
          _errorMessage = 'حدث خطأ في المصادقة: ${e.message}';
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isLogin ? 'تسجيل الدخول' : 'إنشاء حساب جديد'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.receipt_long, size: 80, color: Colors.teal),
              const SizedBox(height: 20),
              
              Text(
                'Smart Invoice Scanner',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
              ),
              const SizedBox(height: 30),

              // حقل البريد الإلكتروني
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 16),

              // حقل كلمة المرور
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 24),
              
              // عرض رسالة الخطأ
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),

              // زر التسجيل/الدخول
              ElevatedButton(
                onPressed: _authenticate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  isLogin ? 'تسجيل الدخول' : 'إنشاء حساب',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 12),

              // زر التبديل
              TextButton(
                onPressed: () {
                  setState(() {
                    isLogin = !isLogin;
                    _errorMessage = null;
                  });
                },
                child: Text(
                  isLogin ? 'ليس لديك حساب؟ قم بالتسجيل' : 'لديك حساب بالفعل؟ سجل الدخول',
                  style: const TextStyle(color: Colors.teal, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// خامساً: شاشة الماسح الضوئي الرئيسية (Main Scanner Screen)
// ====================================================================

class InvoiceScannerScreen extends StatefulWidget {
  const InvoiceScannerScreen({super.key});

  @override
  State<InvoiceScannerScreen> createState() => _InvoiceScannerScreenState();
}

class _InvoiceScannerScreenState extends State<InvoiceScannerScreen> {
  List<SimpleInvoice> _invoices = [];
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  late final GenerativeModel _generativeModel;

  @override
  void initState() {
    super.initState();
    // تهيئة نموذج Gemini
    _generativeModel = GenerativeModel(model: 'gemini-2.5-flash', apiKey: geminiApiKey);
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    final loadedInvoices = await LocalStorageService.loadInvoices();
    setState(() {
      _invoices = loadedInvoices;
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  // ====================================================================
  // منطق التقاط الصورة ومعالجة Gemini
  // ====================================================================

  void _showErrorDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title, textAlign: TextAlign.right),
          content: Text(content, textAlign: TextAlign.right),
          actions: <Widget>[
            TextButton(child: const Text('حسناً'), onPressed: () => Navigator.of(context).pop()),
          ],
        );
      },
    );
  }

  // ⬅️ **الدالة الجديدة: اختبار اتصال Gemini بالنص فقط**
  Future<void> _testGeminiConnection() async {
    // ⬅️ تم إزالة التحقق من المفتاح الوهمي
    
    setState(() => _isLoading = true);
    try {
      const testPrompt = "قل مرحبا، هذا اختبار الاتصال ناجح.";
      final response = await _generativeModel.generateContent([
        Content.text(testPrompt),
      ]);

      setState(() => _isLoading = false);

      if (response.text != null && response.text!.isNotEmpty) {
        // إذا نجح الرد، نظهره
        _showTestSuccessDialog(response.text!);
      } else {
        // إذا فشل الرد أو كان فارغاً
        _showErrorDialog('خطأ في الاتصال', 'المفتاح لم يُرجع رداً صالحاً. قد يكون محظوراً أو غير مفعل.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      // إذا حدث خطأ (عادة 403 أو 400)، نظهر رسالة خطأ
      _showErrorDialog('فشل في الاتصال الأولي', 'تأكد من تفعيل الفوترة وقيود المفتاح في Google Cloud. الخطأ الفعلي: $e');
    }
  }

  void _showTestSuccessDialog(String responseText) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('✅ اتصال Gemini ناجح!', textAlign: TextAlign.right),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                const Text('تم الاتصال بالخدمة بنجاح.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                const SizedBox(height: 10),
                const Text('رد Gemini:', style: TextStyle(color: Colors.grey)),
                Text(responseText, style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(child: const Text('حسناً'), onPressed: () => Navigator.of(context).pop()),
          ],
        );
      },
    );
  }
  // ⬅️ نهاية الدالة الجديدة

  Future<void> _pickImage(ImageSource source) async {
    // ⬅️ تم إزالة التحقق من المفتاح هنا أيضاً (لضمان عمل الدالة)
    
    final XFile? image = await _picker.pickImage(source: source);

    if (image != null) {
      setState(() => _isLoading = true);
      try {
        await _processImage(image);
      } catch (e) {
        _showErrorDialog('خطأ في التحليل',
            'حدث خطأ أثناء التواصل مع Gemini. الرجاء التأكد من مفتاح API والإنترنت.');
        print('Gemini Error: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _processImage(XFile image) async {
    final imageBytes = await image.readAsBytes();

    // تحويل الصورة إلى Base64
    final base64Image = base64Encode(imageBytes);

    // توجيهات لنموذج Gemini لاستخراج JSON فقط
    const prompt =
        'Extract ONLY the following financial data from the invoice image and return it as a structured JSON object. Focus on: invoice number, date and time (in YYYY-MM-DD HH:MM:SS format), net value (without tax), tax amount, and the final total. If any field other than invoice_number and total is missing or unclear, omit it from the JSON. Return ONLY valid JSON without any markdown formatting. ';

    try {
      final response = await _generativeModel.generateContent(
        [Content.text('$prompt\n\nImage (base64): data:image/jpeg;base64,$base64Image')],
      );

      // فحص وتحليل استجابة Gemini
      if (response.text != null && response.text!.isNotEmpty) {
        try {
          final cleanJson = response.text!
              .trim()
              .replaceAll('```json', '')
              .replaceAll('```', '');
          final Map<String, dynamic> jsonResult = jsonDecode(cleanJson);

          final newInvoice = SimpleInvoice.fromJson({
            ...jsonResult,
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
          });

          final updatedInvoices = List<SimpleInvoice>.from(_invoices)
            ..add(newInvoice);
          await LocalStorageService.saveInvoices(updatedInvoices);

          _showSuccessDialog(newInvoice);
          _loadInvoices();
        } catch (e) {
          _showErrorDialog(
              'خطأ في قراءة البيانات',
              'تم استلام بيانات غير صالحة من Gemini. الرجاء المحاولة مرة أخرى.\nالاستجابة: ${response.text}');
        }
      } else {
        _showErrorDialog('لم يتم العثور على بيانات',
            'لم يتمكن Gemini من استخراج بيانات من الصورة.');
      }
    } catch (e) {
      _showErrorDialog('خطأ في التحليل', 'حدث خطأ: $e');
    }
  }

  // ====================================================================
  // عرض النتائج
  // ====================================================================
  
  void _showSuccessDialog(SimpleInvoice invoice) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('تم تحليل الفاتورة بنجاح!', textAlign: TextAlign.right),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildResultRow('رقم الفاتورة:', invoice.invoiceNumber),
              _buildResultRow('التاريخ والوقت:', invoice.dateTime),
              const Divider(),
              _buildResultRow('القيمة الصافية:', '${invoice.netValue.toStringAsFixed(2)}'),
              _buildResultRow('الضريبة:', '${invoice.tax.toStringAsFixed(2)}'),
              _buildResultRow('الإجمالي النهائي:', '${invoice.total.toStringAsFixed(2)}', isTotal: true),
            ],
          ),
          actions: <Widget>[
            TextButton(child: const Text('إغلاق'), onPressed: () => Navigator.pop(context)),
          ],
        );
      },
    );
  }
  
  Widget _buildResultRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text('$value ريال', style: TextStyle(fontWeight: isTotal ? FontWeight.bold : FontWeight.w600, color: isTotal ? Colors.teal : Colors.black)),
        ],
      ),
    );
  }

  // ====================================================================
  // تصميم واجهة الماسح الضوئي الرئيسية
  // ====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Invoice Scanner'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.teal),
                  SizedBox(height: 20),
                  Text('جاري تحليل الفاتورة بواسطة الذكاء الاصطناعي...', style: TextStyle(fontSize: 16)),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // زر إضافة فاتورة جديدة (التقاط أو رفع)
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      // ⬅️ **الزر الجديد: اختبار الاتصال**
                      OutlinedButton.icon(
                        onPressed: _testGeminiConnection,
                        icon: const Icon(Icons.link, color: Colors.grey),
                        label: const Text('اختبار اتصال Gemini (نص)', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: const BorderSide(color: Colors.grey, width: 1),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // أزرار الكاميرا والمعرض
                      ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt, color: Colors.white),
                        label: const Text('التقاط صورة فاتورة جديدة', style: TextStyle(fontSize: 18, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library, color: Colors.teal),
                        label: const Text('رفع صورة من المعرض', style: TextStyle(fontSize: 18, color: Colors.teal)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: const BorderSide(color: Colors.teal, width: 2),
                        ),
                      ),
                    ],
                  ),
                ),

                // قائمة الفواتير المحفوظة
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Text(
                    'آخر الفواتير المحفوظة (${_invoices.length})',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.teal.shade700),
                  ),
                ),
                Expanded(
                  child: _invoices.isEmpty
                      ? const Center(child: Text('لا توجد فواتير محفوظة بعد.'))
                      : ListView.builder(
                          itemCount: _invoices.length,
                          itemBuilder: (context, index) {
                            final invoice = _invoices.reversed.toList()[index]; // الأحدث أولاً
                            return ListTile(
                              leading: const Icon(Icons.receipt, color: Colors.teal),
                              title: Text('رقم الفاتورة: ${invoice.invoiceNumber}'),
                              subtitle: Text('التاريخ: ${invoice.dateTime.split(' ')[0]} | الصافي: ${invoice.netValue.toStringAsFixed(2)} ريال'),
                              trailing: Text('الإجمالي:\n${invoice.total.toStringAsFixed(2)} ريال', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                              onTap: () {
                                _showSuccessDialog(invoice); // عرض التفاصيل
                              },
                              onLongPress: () {
                                // إمكانية حذف الفاتورة
                                _deleteInvoice(invoice.id);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
  
  Future<void> _deleteInvoice(String id) async {
    final updatedList = _invoices.where((i) => i.id != id).toList();
    await LocalStorageService.saveInvoices(updatedList);
    _loadInvoices(); // إعادة تحميل القائمة
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الفاتورة.')));
  }
}