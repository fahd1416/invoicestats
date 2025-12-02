// تطبيق Smart Invoice Scanner (المبسط لمشروع التخرج)
// ** تم استبدال google_generative_ai بكود مخصص يستخدم HTTP مباشرة **

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🚨🚨 التنبيه الأهم: الإعدادات 🚨🚨
// 1. يجب أن يكون ملف firebase_options.dart مولدًا (باستخدام flutterfire configure).
import 'auth_screen.dart';
import 'firebase_options.dart';

// 2. يجب استبدال هذا المتغير بمفتاح Gemini API الفعلي الذي نسخته.
const String geminiApiKey =
    "AIzaSyAGAaOWCis3WJM3bQ46DYIRGU4WK1mtjkw"; // ⬅️ ضع المفتاح هنا

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
// ثانياً: خدمة Gemini AI المخصصة (Custom Gemini Service)
// ====================================================================

class GeminiService {
  final String apiKey;
  static const String baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  GeminiService({required this.apiKey});

  /// استدعاء Gemini API مع صورة و JSON schema
  Future<String?> generateContentWithImage({
    required Uint8List imageBytes,
    required String prompt,
    required Map<String, dynamic> responseSchema,
    String model = 'gemini-2.0-flash-exp',
  }) async {
    try {
      // تحويل الصورة إلى base64
      final base64Image = base64Encode(imageBytes);

      // بناء الطلب
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
              },
            ],
          },
        ],
        'generationConfig': {
          'response_mime_type': 'application/json',
          'response_schema': responseSchema,
        },
      };

      // إرسال الطلب
      final url = Uri.parse('$baseUrl/$model:generateContent?key=$apiKey');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);

        // استخراج النص من الاستجابة
        final candidates = jsonResponse['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return parts[0]['text'] as String?;
          }
        }
        return null;
      } else {
        print('Gemini API Error: ${response.statusCode}');
        print('Response body: ${response.body}');
        throw Exception('فشل الاتصال بـ Gemini API: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in GeminiService: $e');
      rethrow;
    }
  }
}

// ====================================================================
// ثالثاً: خدمة التخزين المحلي (Local Storage Service)
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
    final List<Map<String, dynamic>> invoicesJson = invoices
        .map((i) => i.toJson())
        .toList();
    await prefs.setString(_keyInvoices, jsonEncode(invoicesJson));
  }
}

// ====================================================================
// رابعاً: هيكل التطبيق والمصادقة
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
        return Directionality(textDirection: TextDirection.rtl, child: child!);
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
// سادساً: شاشة الماسح الضوئي الرئيسية (Main Scanner Screen)
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
  late final GeminiService _geminiService;

  @override
  void initState() {
    super.initState();
    // تهيئة خدمة Gemini المخصصة
    _geminiService = GeminiService(apiKey: geminiApiKey);
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
            TextButton(
              child: const Text('حسناً'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    if (geminiApiKey == "YOUR_GEMINI_API_KEY_HERE") {
      _showErrorDialog(
        'خطأ في الإعدادات',
        'الرجاء استبدال مفتاح API في الكود بالمفتاح الفعلي أولاً.',
      );
      return;
    }

    final XFile? image = await _picker.pickImage(source: source);

    if (image != null) {
      setState(() => _isLoading = true);
      try {
        await _processImage(image);
      } catch (e) {
        _showErrorDialog(
          'خطأ في التحليل',
          'حدث خطأ أثناء التواصل مع Gemini. الرجاء التأكد من مفتاح API والإنترنت.',
        );
        print('Gemini Error: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _processImage(XFile image) async {
    final imageBytes = await image.readAsBytes();

    // 💡 تحديد مخطط JSON المطلوب (JSON Schema)
    final Map<String, dynamic> responseSchema = {
      'type': 'object',
      'properties': {
        "invoice_number": {'type': 'string', 'description': "رقم الفاتورة"},
        "date_time": {
          'type': 'string',
          'description': "تاريخ ووقت الفاتورة بصيغة YYYY-MM-DD HH:MM:SS",
        },
        "net_value": {
          'type': 'number',
          'description': "قيمة الفاتورة بدون ضريبة (الصافي)",
        },
        "tax": {'type': 'number', 'description': "قيمة الضريبة المضافة"},
        "total": {'type': 'number', 'description': "المجموع النهائي للفاتورة"},
      },
      'required': ["invoice_number", "date_time", "net_value", "tax", "total"],
    };

    // توجيهات لنموذج Gemini لاستخراج JSON فقط
    const prompt =
        'Extract ONLY the following financial data from the invoice image and return it as a structured JSON object. Focus on: invoice number, date and time (in YYYY-MM-DD HH:MM:SS format), net value (without tax), tax amount, and the final total.';

    // استدعاء خدمة Gemini المخصصة
    final responseText = await _geminiService.generateContentWithImage(
      imageBytes: imageBytes,
      prompt: prompt,
      responseSchema: responseSchema,
    );

    // فحص وتحليل استجابة Gemini
    if (responseText != null && responseText.isNotEmpty) {
      try {
        // تنظيف الاستجابة لضمان أنها JSON صالح
        final cleanJson = responseText
            .trim()
            .replaceAll('```json', '')
            .replaceAll('```', '');
        final Map<String, dynamic> jsonResult = jsonDecode(cleanJson);

        final newInvoice = SimpleInvoice.fromJson({
          ...jsonResult,
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
        });

        // حفظ الفاتورة الجديدة محلياً
        final updatedInvoices = List<SimpleInvoice>.from(_invoices)
          ..add(newInvoice);
        await LocalStorageService.saveInvoices(updatedInvoices);

        _showSuccessDialog(newInvoice);
        _loadInvoices(); // إعادة تحميل القائمة
      } catch (e) {
        _showErrorDialog(
          'خطأ في قراءة البيانات',
          'تم استلام بيانات غير صالحة من Gemini. الرجاء المحاولة مرة أخرى.\nالاستجابة: $responseText',
        );
      }
    } else {
      _showErrorDialog(
        'لم يتم العثور على بيانات',
        'لم يتمكن Gemini من استخراج بيانات من الصورة.',
      );
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
          title: const Text(
            'تم تحليل الفاتورة بنجاح!',
            textAlign: TextAlign.right,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildResultRow('رقم الفاتورة:', invoice.invoiceNumber),
              _buildResultRow('التاريخ والوقت:', invoice.dateTime),
              const Divider(),
              _buildResultRow(
                'القيمة الصافية:',
                invoice.netValue.toStringAsFixed(2),
              ),
              _buildResultRow('الضريبة:', invoice.tax.toStringAsFixed(2)),
              _buildResultRow(
                'الإجمالي النهائي:',
                invoice.total.toStringAsFixed(2),
                isTotal: true,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('إغلاق'),
              onPressed: () => Navigator.pop(context),
            ),
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
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '$value ريال',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: isTotal ? Colors.teal : Colors.black,
            ),
          ),
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
                  Text(
                    'جاري تحليل الفاتورة بواسطة الذكاء الاصطناعي...',
                    style: TextStyle(fontSize: 16),
                  ),
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
                      ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt, color: Colors.white),
                        label: const Text(
                          'التقاط صورة فاتورة جديدة',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(
                          Icons.photo_library,
                          color: Colors.teal,
                        ),
                        label: const Text(
                          'رفع صورة من المعرض',
                          style: TextStyle(fontSize: 18, color: Colors.teal),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(color: Colors.teal, width: 2),
                        ),
                      ),
                    ],
                  ),
                ),

                // قائمة الفواتير المحفوظة
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    'آخر الفواتير المحفوظة (${_invoices.length})',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.teal.shade700,
                    ),
                  ),
                ),
                Expanded(
                  child: _invoices.isEmpty
                      ? const Center(child: Text('لا توجد فواتير محفوظة بعد.'))
                      : ListView.builder(
                          itemCount: _invoices.length,
                          itemBuilder: (context, index) {
                            final invoice = _invoices.reversed
                                .toList()[index]; // الأحدث أولاً
                            return ListTile(
                              leading: const Icon(
                                Icons.receipt,
                                color: Colors.teal,
                              ),
                              title: Text(
                                'رقم الفاتورة: ${invoice.invoiceNumber}',
                              ),
                              subtitle: Text(
                                'التاريخ: ${invoice.dateTime.split(' ')[0]} | الصافي: ${invoice.netValue.toStringAsFixed(2)} ريال',
                              ),
                              trailing: Text(
                                'الإجمالي:\n${invoice.total.toStringAsFixed(2)} ريال',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حذف الفاتورة.')));
  }
}
