import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JnvApp());
}

class JnvApp extends StatelessWidget {
  const JnvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JNV Parent Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'jnv_session_user';
  static const _apiBaseKey = 'jnv_api_base';
  static const _authTokenKey = 'jnv_auth_token';

  bool _isAuthenticated = false;
  bool _isLoadingOverview = false;
  bool _needsChildLinking = false;
  bool _isPendingApproval = false;
  bool _firebaseReady = false;
  SessionUser? _sessionUser;
  ParentStudent? _linkedStudent;
  List<ParentScore> _linkedScores = const [];
  String _apiBase = 'http://192.168.1.8:8080';
  String _authToken = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _isLoadingOverview = true);
    await _initializeFirebase();
    await _restoreSession();
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (_) {
      _firebaseReady = false;
    }
  }

  Future<void> _restoreSession() async {
    setState(() => _isLoadingOverview = true);
    try {
      final savedApiBase = await _storage.read(key: _apiBaseKey);
      final sessionRaw = await _storage.read(key: _sessionKey);
      final savedAuthToken = await _storage.read(key: _authTokenKey);
      if (savedApiBase != null && savedApiBase.isNotEmpty) {
        _apiBase = savedApiBase;
      }
      if (savedAuthToken != null && savedAuthToken.isNotEmpty) {
        _authToken = savedAuthToken;
      } else if (_firebaseReady && FirebaseAuth.instance.currentUser != null) {
        _authToken = await FirebaseAuth.instance.currentUser!.getIdToken() ?? '';
      }
      if (sessionRaw == null || sessionRaw.isEmpty) {
        return;
      }

      final parsed = jsonDecode(sessionRaw);
      if (parsed is! Map<String, dynamic>) {
        return;
      }

      _sessionUser = SessionUser.fromJson(parsed);
      await _refreshParentOverview();
    } catch (_) {
      // Ignore parse/storage errors and fallback to login.
    } finally {
      if (mounted) {
        setState(() => _isLoadingOverview = false);
      }
    }
  }

  Future<void> _persistSession(SessionUser user, String apiBase, String authToken) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(user.toJson()));
    await _storage.write(key: _apiBaseKey, value: apiBase);
    await _storage.write(key: _authTokenKey, value: authToken);
  }

  Future<void> _clearSession() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _authTokenKey);
    if (_firebaseReady) {
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _refreshParentOverview() async {
    final user = _sessionUser;
    if (user == null) return;
    setState(() => _isLoadingOverview = true);
    try {
      final client = BackendClient(_apiBase);
      if (_firebaseReady && FirebaseAuth.instance.currentUser != null) {
        _authToken = await FirebaseAuth.instance.currentUser!.getIdToken(true) ?? '';
      } else if (_authToken.isEmpty) {
        _authToken = 'dev:${user.phone}:parent';
      }
      final overview = await client.getParentOverview(_authToken);
      if (!mounted) return;
      setState(() {
        _linkedStudent = overview.student;
        _linkedScores = overview.scores;
        _needsChildLinking = overview.status == 'not_linked';
        _isPendingApproval = overview.status == 'pending';
        _isAuthenticated = overview.status == 'approved' && overview.student != null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _needsChildLinking = true;
        _isPendingApproval = false;
        _isAuthenticated = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingOverview = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingOverview) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_needsChildLinking && _sessionUser != null) {
      return LinkChildScreen(
        apiBase: _apiBase,
        authToken: _authToken,
        onRequested: () {
          setState(() {
            _needsChildLinking = false;
          });
          _refreshParentOverview();
        },
        onLogout: () {
          _clearSession();
          setState(() {
            _needsChildLinking = false;
            _isAuthenticated = false;
            _sessionUser = null;
          });
        },
      );
    }

    if (_isPendingApproval) {
      return PendingApprovalScreen(
        onCheckStatus: _refreshParentOverview,
        onBackToLogin: () {
          _clearSession();
          setState(() {
            _isPendingApproval = false;
            _isAuthenticated = false;
            _sessionUser = null;
          });
        },
      );
    }

    if (_isAuthenticated) {
      return ParentShell(
        sessionUser: _sessionUser,
        student: _linkedStudent,
        scores: _linkedScores,
        onLogout: () async {
          await _clearSession();
          if (!mounted) return;
          setState(() {
            _isAuthenticated = false;
            _sessionUser = null;
            _linkedStudent = null;
            _linkedScores = const [];
          });
        },
      );
    }
    return AuthScreen(
      initialApiBase: _apiBase,
      firebaseEnabled: _firebaseReady,
      onAuthSuccess: (sessionUser, apiBase, authToken) {
        setState(() {
          _apiBase = apiBase;
          _authToken = authToken;
          _sessionUser = sessionUser;
          _needsChildLinking = false;
          _isAuthenticated = false;
          _isPendingApproval = false;
        });
        _persistSession(sessionUser, apiBase, authToken);
        _refreshParentOverview();
      },
    );
  }
}

class SessionUser {
  final String id;
  final String name;
  final String phone;
  final String role;
  final String schoolID;

  const SessionUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.schoolID,
  });

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    return SessionUser(
      id: (json['id'] ?? '').toString(),
      name: (json['full_name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      schoolID: (json['school_id'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': name,
      'phone': phone,
      'role': role,
      'school_id': schoolID,
    };
  }
}

class ParentStudent {
  final String id;
  final String fullName;
  final String classLabel;
  final int rollNumber;
  final String house;

  const ParentStudent({
    required this.id,
    required this.fullName,
    required this.classLabel,
    required this.rollNumber,
    required this.house,
  });

  factory ParentStudent.fromJson(Map<String, dynamic> json) {
    return ParentStudent(
      id: (json['id'] ?? '').toString(),
      fullName: (json['full_name'] ?? '').toString(),
      classLabel: (json['class_label'] ?? '').toString(),
      rollNumber: int.tryParse((json['roll_number'] ?? '').toString()) ?? 0,
      house: (json['house'] ?? '').toString(),
    );
  }
}

class ParentScore {
  final String subject;
  final double score;
  final double maxScore;
  final String grade;
  final DateTime? createdAt;

  const ParentScore({
    required this.subject,
    required this.score,
    required this.maxScore,
    required this.grade,
    required this.createdAt,
  });

  factory ParentScore.fromJson(Map<String, dynamic> json) {
    return ParentScore(
      subject: (json['subject'] ?? '').toString(),
      score: double.tryParse((json['score'] ?? '').toString()) ?? 0,
      maxScore: double.tryParse((json['max_score'] ?? '').toString()) ?? 100,
      grade: (json['grade'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }
}

class ParentOverview {
  final String status;
  final ParentStudent? student;
  final List<ParentScore> scores;

  const ParentOverview({
    required this.status,
    required this.student,
    required this.scores,
  });
}

class BackendClient {
  final String baseUrl;

  const BackendClient(this.baseUrl);

  Future<SessionUser> loginWithToken(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/session'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Login failed (${response.statusCode}): ${_extractError(response.body)}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>;
    return SessionUser.fromJson(user);
  }

  Future<void> requestParentLinkByClassRoll(
    String token,
    String district,
    String classLabel,
    int rollNumber,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/parent-links/request'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'district': district,
        'class_label': classLabel,
        'roll_number': rollNumber,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Signup request failed (${response.statusCode}): ${_extractError(response.body)}');
    }
  }

  Future<List<String>> fetchDistricts(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/reference/districts'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Districts fetch failed (${response.statusCode}): ${_extractError(response.body)}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = body['districts'];
    if (raw is! List) {
      return const [];
    }
    return raw.map((item) => item.toString()).toList();
  }

  Future<ParentOverview> getParentOverview(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/parents/me/overview'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Overview fetch failed (${response.statusCode}): ${_extractError(response.body)}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final status = (body['status'] ?? '').toString();
    final studentJson = body['student'];
    final scoresJson = body['scores'];

    return ParentOverview(
      status: status,
      student: studentJson is Map<String, dynamic> ? ParentStudent.fromJson(studentJson) : null,
      scores: scoresJson is List
          ? scoresJson
              .whereType<Map<String, dynamic>>()
              .map(ParentScore.fromJson)
              .toList()
          : const [],
    );
  }

  String _extractError(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        final message = parsed['error']?.toString();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      // fall through to raw body
    }
    return body.isEmpty ? 'unknown error' : body;
  }
}

enum AuthMode { login, signup }

class AuthScreen extends StatefulWidget {
  final String initialApiBase;
  final bool firebaseEnabled;
  final void Function(SessionUser user, String apiBase, String authToken) onAuthSuccess;

  const AuthScreen({
    super.key,
    required this.initialApiBase,
    required this.firebaseEnabled,
    required this.onAuthSuccess,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode _mode = AuthMode.login;
  bool _otpSent = false;
  bool _loading = false;
  String _status = '';
  late String _apiBase;
  String _verificationId = '';
  int? _resendToken;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiBase = widget.initialApiBase;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    final onlyDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (onlyDigits.length < 10) {
      setState(() => _status = 'Enter a valid phone number.');
      return;
    }
    setState(() {
      _loading = true;
      _status = '';
    });

    if (!widget.firebaseEnabled) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      setState(() {
        _loading = false;
        _otpSent = true;
        _status = 'Firebase not configured. Use 123456 for demo login.';
      });
      _startResendCountdown();
      return;
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _normalizedPhone(),
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {},
        verificationFailed: (FirebaseAuthException exception) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _status = 'OTP send failed: ${exception.message ?? exception.code}';
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _otpSent = true;
            _verificationId = verificationId;
            _resendToken = resendToken;
            _status = 'OTP sent successfully.';
          });
          _startResendCountdown();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'OTP send failed: ${err.toString()}';
      });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _status = 'Enter 6-digit OTP.');
      return;
    }

    setState(() {
      _loading = true;
      _status = '';
    });
    try {
      final client = BackendClient(_apiBase.trim());
      String authToken;

      if (widget.firebaseEnabled) {
        final credential = PhoneAuthProvider.credential(
          verificationId: _verificationId,
          smsCode: otp,
        );
        final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        final firebaseUser = userCredential.user;
        if (firebaseUser == null) {
          throw Exception('Firebase user is null');
        }
        authToken = await firebaseUser.getIdToken(true) ?? '';
      } else {
        if (otp != '123456') {
          throw Exception('Invalid OTP. Use 123456 for demo.');
        }
        final phone = _normalizedPhone();
        authToken = 'dev:$phone:parent';
      }

      final sessionUser = await client.loginWithToken(authToken);
      widget.onAuthSuccess(sessionUser, _apiBase.trim(), authToken);
    } catch (err) {
      setState(() {
        _loading = false;
        _status = 'Auth failed: ${err.toString()}';
      });
      return;
    }
  }

  String _normalizedPhone() {
    final raw = _phoneController.text.trim();
    if (raw.startsWith('+')) return raw;
    return '+91${raw.replaceAll(RegExp(r'[^0-9]'), '')}';
  }

  @override
  Widget build(BuildContext context) {
    final isSignup = _mode == AuthMode.signup;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF312E81), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'JNV Parent Portal',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isSignup ? 'Create your parent account' : 'Login with phone and OTP',
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      initialValue: _apiBase,
                      decoration: const InputDecoration(labelText: 'API Base URL'),
                      onChanged: (value) => _apiBase = value,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                      _mode = AuthMode.login;
                                      _otpSent = false;
                                      _status = '';
                                    }),
                            child: const Text('Login'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                      _mode = AuthMode.signup;
                                      _otpSent = false;
                                      _status = '';
                                    }),
                            child: const Text('Signup'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone Number'),
                    ),
                    const SizedBox(height: 10),
                    if (_otpSent)
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'OTP'),
                      ),
                    if (_otpSent) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: (_loading || _resendSeconds > 0) ? null : _sendOtp,
                          child: Text(
                            _resendSeconds > 0
                                ? 'Resend in ${_resendSeconds}s'
                                : 'Resend OTP',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : (_otpSent ? _verifyOtp : _sendOtp),
                        child: Text(_loading
                            ? 'Please wait...'
                            : (_otpSent ? 'Verify OTP' : 'Send OTP')),
                      ),
                    ),
                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _status,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LinkChildScreen extends StatefulWidget {
  final String apiBase;
  final String authToken;
  final VoidCallback onRequested;
  final VoidCallback onLogout;

  const LinkChildScreen({
    super.key,
    required this.apiBase,
    required this.authToken,
    required this.onRequested,
    required this.onLogout,
  });

  @override
  State<LinkChildScreen> createState() => _LinkChildScreenState();
}

class _LinkChildScreenState extends State<LinkChildScreen> {
  final TextEditingController _classController = TextEditingController();
  final TextEditingController _rollController = TextEditingController();
  String _status = '';
  bool _loading = false;
  bool _loadingDistricts = false;
  List<String> _districts = const [];
  String? _selectedDistrict;

  @override
  void initState() {
    super.initState();
    _loadDistricts();
  }

  Future<void> _loadDistricts() async {
    setState(() {
      _loadingDistricts = true;
      _status = '';
    });
    try {
      final client = BackendClient(widget.apiBase);
      final districts = await client.fetchDistricts(widget.authToken);
      if (!mounted) return;
      setState(() {
        _districts = districts;
        _selectedDistrict = districts.isNotEmpty ? districts.first : null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _status = 'Failed to load districts: ${err.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingDistricts = false);
      }
    }
  }

  @override
  void dispose() {
    _classController.dispose();
    _rollController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final district = _selectedDistrict ?? '';
    final classLabel = _classController.text.trim();
    final roll = int.tryParse(_rollController.text.trim());
    if (district.isEmpty || classLabel.isEmpty || roll == null || roll <= 0) {
      setState(() => _status = 'Enter valid district, class and roll number.');
      return;
    }

    setState(() {
      _loading = true;
      _status = '';
    });
    try {
      final client = BackendClient(widget.apiBase);
      await client.requestParentLinkByClassRoll(widget.authToken, district, classLabel, roll);
      widget.onRequested();
    } catch (err) {
      setState(() {
        _loading = false;
        _status = 'Link request failed: ${err.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF312E81), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Link Your Child',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter district, class and roll number to request student access.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 16),
                    if (_loadingDistricts)
                      const LinearProgressIndicator()
                    else
                      DropdownButtonFormField<String>(
                        value: _selectedDistrict,
                        decoration: const InputDecoration(labelText: 'District'),
                        items: _districts
                            .map((district) => DropdownMenuItem<String>(
                                  value: district,
                                  child: Text(district),
                                ))
                            .toList(),
                        onChanged: (value) => setState(() => _selectedDistrict = value),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _classController,
                      decoration: const InputDecoration(labelText: 'Class (example: Class 10)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _rollController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Roll Number'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: Text(_loading ? 'Submitting...' : 'Submit request'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : widget.onLogout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                      ),
                    ),
                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(_status, style: const TextStyle(color: Color(0xFF475569))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PendingApprovalScreen extends StatelessWidget {
  final VoidCallback onBackToLogin;
  final VoidCallback onCheckStatus;

  const PendingApprovalScreen({
    super.key,
    required this.onBackToLogin,
    required this.onCheckStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF312E81), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 48, color: Color(0xFF4F46E5)),
                const SizedBox(height: 12),
                const Text(
                  'Request Submitted',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your signup is complete. Please wait for admin approval to access student data.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onCheckStatus,
                  child: const Text('Check approval status'),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: onBackToLogin,
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ParentShell extends StatefulWidget {
  final SessionUser? sessionUser;
  final ParentStudent? student;
  final List<ParentScore> scores;
  final VoidCallback onLogout;

  const ParentShell({
    super.key,
    required this.onLogout,
    required this.sessionUser,
    required this.student,
    required this.scores,
  });

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(sessionUser: widget.sessionUser, student: widget.student, scores: widget.scores),
      const AcademicScreen(),
      const EventsScreen(),
      const NewsScreen(),
      ProfileScreen(
        onLogout: widget.onLogout,
        sessionUser: widget.sessionUser,
        student: widget.student,
        scores: widget.scores,
      ),
    ];

    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Academic'),
          NavigationDestination(icon: Icon(Icons.event_outlined), label: 'Events'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'News'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

class HeaderBar extends StatelessWidget {
  final String subtitle;

  const HeaderBar({super.key, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFF6366F1),
                child: Icon(Icons.menu_book, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'JNV Parent Portal',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFFDCE3FF), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white24,
            child: Icon(Icons.menu, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  final SessionUser? sessionUser;
  final ParentStudent? student;
  final List<ParentScore> scores;

  const DashboardScreen({
    super.key,
    required this.sessionUser,
    required this.student,
    required this.scores,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const HeaderBar(subtitle: 'Dashboard'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StudentSummaryCard(sessionUser: sessionUser, student: student),
                const SizedBox(height: 16),
                const SectionHeader(
                  icon: Icons.menu_book_rounded,
                  iconColor: Color(0xFF16A34A),
                  title: 'Recent Scores',
                  subtitle: 'Last 4 tests',
                ),
                const SizedBox(height: 12),
                RecentScoresCard(scores: scores),
                const SizedBox(height: 20),
                const SectionHeader(
                  icon: Icons.event_available_rounded,
                  iconColor: Color(0xFF7C3AED),
                  title: 'Upcoming Events',
                  subtitle: 'Next 3 events',
                ),
                const SizedBox(height: 12),
                const UpcomingEventsCard(),
                const SizedBox(height: 20),
                const SectionHeader(
                  icon: Icons.notifications_active_rounded,
                  iconColor: Color(0xFFF97316),
                  title: 'Announcements',
                  subtitle: 'Recent updates',
                ),
                const SizedBox(height: 12),
                const AnnouncementsCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class StudentSummaryCard extends StatelessWidget {
  final SessionUser? sessionUser;
  final ParentStudent? student;

  const StudentSummaryCard({super.key, required this.sessionUser, required this.student});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(
                  child: Text(
                    'A',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (student?.fullName.isNotEmpty ?? false)
                          ? student!.fullName
                          : (sessionUser?.name.isNotEmpty ?? false)
                              ? sessionUser!.name
                              : 'Parent User',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4),
                    Text(
                      (student != null && student!.classLabel.isNotEmpty)
                          ? '${student!.classLabel} • Roll ${student!.rollNumber}'
                          : (sessionUser?.phone.isNotEmpty ?? false)
                              ? sessionUser!.phone
                          : 'Class 10-A • JNV2024-1045',
                      style: TextStyle(color: Color(0xFFE5E7FF), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(
                child: StatCard(title: 'GPA', value: '9.2'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: StatCard(title: 'Attend', value: '94.5%'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: StatCard(title: 'Rank', value: '#3'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;

  const StatCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Color(0xFFE5E7FF), fontSize: 11)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ],
        ),
        const Text('View All', style: TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.w600, fontSize: 12)),
      ],
    );
  }
}

class RecentScoresCard extends StatelessWidget {
  final List<ParentScore> scores;

  const RecentScoresCard({super.key, required this.scores});

  @override
  Widget build(BuildContext context) {
    final recentScores = scores.take(4).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Column(
        children: recentScores.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No scores uploaded yet.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ),
              ]
            : recentScores.map((item) {
          final score = item.score;
          final maxScore = item.maxScore <= 0 ? 100 : item.maxScore;
          final dateText = item.createdAt != null
              ? '${item.createdAt!.day.toString().padLeft(2, '0')} '
                  '${_monthName(item.createdAt!.month)} ${item.createdAt!.year}'
              : 'Recent';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(dateText, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (item.grade == 'A+' ? const Color(0xFFDCFCE7) : const Color(0xFFDBEAFE)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.grade.isEmpty ? '-' : item.grade,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: (item.grade == 'A+' ? const Color(0xFF15803D) : const Color(0xFF1D4ED8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${score.toStringAsFixed(0)}/${maxScore.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score / maxScore,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF6366F1)),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

String _monthName(int month) {
  const names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return names[(month - 1).clamp(0, 11)];
}

class UpcomingEventsCard extends StatelessWidget {
  const UpcomingEventsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final events = [
      {'date': 'Jan 25', 'title': 'Annual Sports Day', 'time': '9:00 AM', 'type': 'Sports'},
      {'date': 'Jan 28', 'title': 'Parent-Teacher Meeting', 'time': '10:00 AM', 'type': 'Meeting'},
      {'date': 'Feb 5', 'title': 'Science Exhibition', 'time': '11:00 AM', 'type': 'Academic'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Column(
        children: events.map((event) {
          final dateParts = (event['date'] as String).split(' ');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(dateParts[0],
                          style: const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.w700, fontSize: 12)),
                      Text(dateParts[1],
                          style: const TextStyle(color: Color(0xFF1E1B4B), fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event['title']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(event['time']!, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          event['type']!,
                          style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class AnnouncementsCard extends StatelessWidget {
  const AnnouncementsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final announcements = [
      {'title': 'Winter Break Schedule', 'age': '2 days ago', 'tag': 'Important', 'color': Color(0xFFFEE2E2)},
      {'title': 'New Library Books Available', 'age': '5 days ago', 'tag': 'Notice', 'color': Color(0xFFFFF7ED)},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Column(
        children: announcements.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: item['color'] as Color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item['tag'] as String,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(item['age'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class AcademicScreen extends StatelessWidget {
  const AcademicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final subjects = [
      {'name': 'Mathematics', 'score': 95, 'grade': 'A+'},
      {'name': 'Physics', 'score': 88, 'grade': 'A'},
      {'name': 'Chemistry', 'score': 92, 'grade': 'A+'},
      {'name': 'Biology', 'score': 90, 'grade': 'A+'},
      {'name': 'English', 'score': 85, 'grade': 'A'},
      {'name': 'Hindi', 'score': 87, 'grade': 'A'},
    ];

    return Column(
      children: [
        const HeaderBar(subtitle: 'Academic'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Academic Performance',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: StatCard(title: 'GPA', value: '9.2')),
                          SizedBox(width: 10),
                          Expanded(child: StatCard(title: 'Avg %', value: '89.5')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Term Reports', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Term 1 - 2025-26', style: TextStyle(fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('Performance Report', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('GPA', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              Text('9.2', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4F46E5))),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...subjects.map((subject) {
                        final score = subject['score'] as int;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0E7FF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.description_outlined, size: 18, color: Color(0xFF4F46E5)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(subject['name'] as String,
                                            style: const TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        const Text('100 marks',
                                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                  Text('$score', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: subject['grade'] == 'A+'
                                          ? const Color(0xFFDCFCE7)
                                          : const Color(0xFFDBEAFE),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      subject['grade'] as String,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: subject['grade'] == 'A+'
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFF1D4ED8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: score / 100,
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFE5E7EB),
                                  valueColor: const AlwaysStoppedAnimation(Color(0xFF6366F1)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final upcoming = [
      {
        'date': 'Jan 25',
        'title': 'Annual Sports Day',
        'time': '9:00 AM - 5:00 PM',
        'location': 'School Sports Ground',
        'people': 'All Students',
        'type': 'Sports',
        'color': Color(0xFFF97316)
      },
      {
        'date': 'Jan 28',
        'title': 'Parent-Teacher Meeting',
        'time': '10:00 AM - 2:00 PM',
        'location': 'Main Auditorium',
        'people': 'Parents & Teachers',
        'type': 'Meeting',
        'color': Color(0xFF3B82F6)
      },
      {
        'date': 'Feb 5',
        'title': 'Science Exhibition',
        'time': '11:00 AM - 4:00 PM',
        'location': 'Science Lab',
        'people': 'Classes 8-12',
        'type': 'Academic',
        'color': Color(0xFF7C3AED)
      },
    ];

    final past = [
      {'title': 'Winter Break', 'date': '20 Dec 2025', 'type': 'Holiday'},
      {'title': 'Term 1 Exams', 'date': '5-15 Dec 2025', 'type': 'Academic'},
      {'title': 'Music Competition', 'date': '28 Nov 2025', 'type': 'Cultural'},
    ];

    return Column(
      children: [
        const HeaderBar(subtitle: 'Events'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.event_available, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Events Calendar',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text('Stay updated with school events',
                                style: TextStyle(color: Color(0xFFE5E7FF), fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Upcoming Events', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...upcoming.map((event) {
                  final dateParts = (event['date'] as String).split(' ');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: event['color'] as Color,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0E7FF),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(dateParts[0],
                                            style: const TextStyle(
                                                color: Color(0xFF4F46E5), fontWeight: FontWeight.w700, fontSize: 12)),
                                        Text(dateParts[1],
                                            style: const TextStyle(
                                                color: Color(0xFF1E1B4B), fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: (event['color'] as Color).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(event['type'] as String,
                                              style: TextStyle(
                                                  color: event['color'] as Color,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(event['title'] as String,
                                            style: const TextStyle(fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        Text(event['time'] as String,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                        Text(event['location'] as String,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                        Text(event['people'] as String,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Text('View Details',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 12),
                const Text('Past Events', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
                  ),
                  child: Column(
                    children: past.map((event) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.event, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(event['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(event['date'] as String,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDE9FE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(event['type'] as String,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pinned = [
      {
        'title': 'Winter Break Schedule',
        'date': '15 Jan 2026',
        'time': '10:30 AM',
        'tags': ['Important', 'Academic'],
        'content': 'School will remain closed from 20th December to 5th January.',
      },
      {
        'title': 'Parent-Teacher Meeting',
        'date': '14 Jan 2026',
        'time': '2:15 PM',
        'tags': ['Important', 'Meeting'],
        'content': 'PTM scheduled for 28th January from 10 AM to 2 PM.',
      },
    ];

    final announcements = [
      {
        'title': 'New Library Books',
        'date': '12 Jan 2026',
        'author': 'Library Dept',
        'tag': 'Library',
        'content': 'New collection of 500+ books available from 20th January.',
      },
      {
        'title': 'Updated School Timings',
        'date': '10 Jan 2026',
        'author': 'Administration',
        'tag': 'Important',
        'content': 'Winter timings: 8:30 AM to 2:30 PM effective from 15th January.',
      },
      {
        'title': 'Sports Day Registration',
        'date': '8 Jan 2026',
        'author': 'Sports Dept',
        'tag': 'Sports',
        'content': 'Register for Annual Sports Day through house captains by 18th January.',
      },
      {
        'title': 'Science Exhibition',
        'date': '7 Jan 2026',
        'author': 'Science Dept',
        'tag': 'Academic',
        'content': 'Submit project proposals by 20th January for Feb 5 exhibition.',
      },
    ];

    return Column(
      children: [
        const HeaderBar(subtitle: 'Announcements'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.notifications_active, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Announcements',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text('Latest school updates and notices',
                                style: TextStyle(color: Color(0xFFE5E7FF), fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: const [
                    Icon(Icons.push_pin, size: 18, color: Color(0xFF4F46E5)),
                    SizedBox(width: 6),
                    Text('Pinned', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                ...pinned.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE0E7FF)),
                      boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text('${item['date']} • ${item['time']}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: (item['tags'] as List<String>)
                              .map((tag) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: tag == 'Important' ? const Color(0xFFFEE2E2) : const Color(0xFFEDE9FE),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(tag,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: tag == 'Important' ? const Color(0xFFB91C1C) : const Color(0xFF7C3AED))),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                        Text(item['content'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text('Read More',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 8),
                const Text('All Announcements', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...announcements.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(item['tag'] as String,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${item['date']} • ${item['author']}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        const SizedBox(height: 8),
                        Text(item['content'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        const SizedBox(height: 10),
                        const Text('Read more',
                            style: TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileScreen extends StatelessWidget {
  final SessionUser? sessionUser;
  final ParentStudent? student;
  final List<ParentScore> scores;
  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.onLogout,
    required this.sessionUser,
    required this.student,
    required this.scores,
  });

  @override
  Widget build(BuildContext context) {
    final subjectMap = <String, List<double>>{};
    for (final score in scores) {
      if (score.subject.isEmpty) continue;
      subjectMap.putIfAbsent(score.subject, () => []);
      subjectMap[score.subject]!.add(score.maxScore > 0 ? (score.score / score.maxScore) * 100 : 0);
    }
    final subjects = subjectMap.entries
        .map((entry) {
          final values = entry.value;
          final avg = values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
          return {'name': entry.key, 'score': avg};
        })
        .toList();

    return Column(
      children: [
        const HeaderBar(subtitle: 'Student Profile'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.white,
                        child: Text('A', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(height: 12),
                      Text((student?.fullName.isNotEmpty ?? false)
                              ? student!.fullName
                              : (sessionUser?.name.isNotEmpty ?? false)
                                  ? sessionUser!.name
                                  : 'Parent User',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text((student != null && student!.classLabel.isNotEmpty)
                              ? '${student!.classLabel} • Roll ${student!.rollNumber}'
                              : (sessionUser?.phone.isNotEmpty ?? false)
                                  ? sessionUser!.phone
                                  : 'Class 10-A • JNV2024-1045',
                          style: const TextStyle(color: Color(0xFFE5E7FF), fontSize: 12)),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: StatCard(title: 'GPA', value: '9.2')),
                          SizedBox(width: 10),
                          Expanded(child: StatCard(title: 'Attend', value: '94.5%')),
                          SizedBox(width: 10),
                          Expanded(child: StatCard(title: 'Rank', value: '#3')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const InfoSectionTitle(title: 'Student Information', icon: Icons.person),
                const SizedBox(height: 12),
                InfoCard(
                  rows: [
                    const InfoRow(label: 'Date of Birth', value: 'On file', icon: Icons.cake),
                    const InfoRow(label: 'Admission Date', value: 'On file', icon: Icons.calendar_today),
                    InfoRow(
                      label: 'House',
                      value: (student?.house.isNotEmpty ?? false) ? student!.house : 'Not assigned',
                      icon: Icons.home,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const InfoSectionTitle(title: 'Parent Information', icon: Icons.family_restroom),
                const SizedBox(height: 12),
                InfoCard(
                  rows: [
                    InfoRow(
                      label: 'Parent Name',
                      value: (sessionUser?.name.isNotEmpty ?? false) ? sessionUser!.name : 'Pending',
                      icon: Icons.person_outline,
                    ),
                    InfoRow(
                      label: 'Contact',
                      value: (sessionUser?.phone.isNotEmpty ?? false) ? sessionUser!.phone : 'Pending',
                      icon: Icons.phone,
                    ),
                    const InfoRow(label: 'Email', value: 'Not set', icon: Icons.email),
                  ],
                ),
                const SizedBox(height: 16),
                const InfoSectionTitle(title: 'Current Subjects', icon: Icons.menu_book),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
                  ),
                  child: Column(
                    children: subjects.isEmpty
                        ? const [
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('No subject scores available yet.',
                                  style: TextStyle(color: Color(0xFF64748B))),
                            ),
                          ]
                        : subjects.map((item) {
                      final avgScore = item['score'] as double;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'] as String,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      const Text('Calculated average',
                                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('${avgScore.toStringAsFixed(1)}%',
                                      style: const TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: avgScore / 100,
                                minHeight: 6,
                                backgroundColor: const Color(0xFFE5E7EB),
                                valueColor: const AlwaysStoppedAnimation(Color(0xFF6366F1)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text(
                      'Logout',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class InfoSectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const InfoSectionTitle({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4F46E5), size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class InfoCard extends StatelessWidget {
  final List<InfoRow> rows;

  const InfoCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Column(
        children: rows
            .map((row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0E7FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(row.icon, size: 18, color: const Color(0xFF4F46E5)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            const SizedBox(height: 2),
                            Text(row.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class InfoRow {
  final String label;
  final String value;
  final IconData icon;

  const InfoRow({required this.label, required this.value, required this.icon});
}
