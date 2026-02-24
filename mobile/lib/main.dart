import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';

const Color kBrandNavy = Color(0xFF0B1F3B);
const Color kBrandNavyLight = Color(0xFF13396B);
const Color kBrandGold = Color(0xFFD4AF37);

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://jnv-web.onrender.com',
);

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
        colorScheme: ColorScheme.fromSeed(seedColor: kBrandNavy).copyWith(
          primary: kBrandNavy,
          secondary: kBrandGold,
        ),
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
  static const _authTokenKey = 'jnv_auth_token';

  bool _isAuthenticated = false;
  bool _isLoadingOverview = false;
  bool _needsChildLinking = false;
  bool _isPendingApproval = false;
  bool _requiresUpdate = false;
  bool _firebaseReady = false;
  bool _messagingInitialized = false;
  String _currentAppVersion = '0.0.0';
  String _forceUpdateMessage = 'Please update the app to continue.';
  String? _pendingNotificationType;
  String? _pendingEntityID;
  SessionUser? _sessionUser;
  ParentStudent? _linkedStudent;
  List<ParentScore> _linkedScores = const [];
  List<ParentAnnouncement> _announcements = const [];
  List<ParentEvent> _events = const [];
  ParentAppConfig _appConfig = const ParentAppConfig(
    featureFlags: {},
    dashboardWidgets: [],
    minSupportedVersion: '',
    forceUpdateMessage: '',
  );
  String _apiBase = kApiBaseUrl;
  String _authToken = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _isLoadingOverview = true);
    await _loadAppVersion();
    await _initializeFirebase();
    await _restoreSession();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentAppVersion = info.version;
    } catch (_) {
      _currentAppVersion = '0.0.0';
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
      await _setupMessaging();
    } catch (_) {
      _firebaseReady = false;
    }
  }

  Future<void> _setupMessaging() async {
    if (_messagingInitialized) return;
    _messagingInitialized = true;

    FirebaseMessaging.onMessage.listen((message) {
      _handleNotificationMessage(message, openedFromTap: false);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationMessage(message, openedFromTap: true);
    });
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationMessage(initialMessage, openedFromTap: true);
    }
  }

  Future<void> _restoreSession() async {
    setState(() => _isLoadingOverview = true);
    try {
      final sessionRaw = await _storage.read(key: _sessionKey);
      final savedAuthToken = await _storage.read(key: _authTokenKey);
      if (savedAuthToken != null && savedAuthToken.isNotEmpty) {
        _authToken = savedAuthToken;
      } else if (_firebaseReady && FirebaseAuth.instance.currentUser != null) {
        _authToken =
            await FirebaseAuth.instance.currentUser!.getIdToken() ?? '';
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

  Future<void> _persistSession(
      SessionUser user, String apiBase, String authToken) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(user.toJson()));
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
        _authToken =
            await FirebaseAuth.instance.currentUser!.getIdToken(true) ?? '';
      } else if (_authToken.isEmpty) {
        _authToken = 'dev:${user.phone}:parent';
      }
      final overview = await client.getParentOverview(_authToken);
      List<ParentAnnouncement> announcements = const [];
      List<ParentEvent> events = const [];
      ParentAppConfig config = const ParentAppConfig(
          featureFlags: {},
          dashboardWidgets: [],
          minSupportedVersion: '',
          forceUpdateMessage: '');
      if (overview.status == 'approved' && overview.student != null) {
        final results = await Future.wait([
          client.fetchAnnouncements(_authToken),
          client.fetchEvents(_authToken),
          client.fetchAppConfig(_authToken),
        ]);
        announcements = results[0] as List<ParentAnnouncement>;
        events = results[1] as List<ParentEvent>;
        config = results[2] as ParentAppConfig;
        if (_firebaseReady) {
          await _registerDeviceToken(client);
        }
      }
      if (!mounted) return;
      final shouldForceUpdate =
          _isVersionOutdated(_currentAppVersion, config.minSupportedVersion);
      setState(() {
        _linkedStudent = overview.student;
        _linkedScores = overview.scores;
        _announcements = announcements;
        _events = events;
        _appConfig = config;
        _requiresUpdate = shouldForceUpdate;
        _forceUpdateMessage = config.forceUpdateMessage.trim().isEmpty
            ? 'Please update the app to continue.'
            : config.forceUpdateMessage.trim();
        _needsChildLinking = overview.status == 'not_linked';
        _isPendingApproval = overview.status == 'pending';
        _isAuthenticated =
            overview.status == 'approved' && overview.student != null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _needsChildLinking = true;
        _isPendingApproval = false;
        _isAuthenticated = false;
        _announcements = const [];
        _events = const [];
        _appConfig = const ParentAppConfig(
            featureFlags: {},
            dashboardWidgets: [],
            minSupportedVersion: '',
            forceUpdateMessage: '');
        _requiresUpdate = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingOverview = false);
      }
    }
  }

  void _handleNotificationMessage(RemoteMessage message,
      {required bool openedFromTap}) {
    final type = (message.data['type'] ?? '').toString();
    final announcementID = (message.data['announcement_id'] ?? '').toString();
    final eventID = (message.data['event_id'] ?? '').toString();
    if (!mounted) return;
    if (openedFromTap) {
      setState(() {
        _pendingNotificationType = type;
        _pendingEntityID = announcementID.isNotEmpty ? announcementID : eventID;
      });
    }
    if (_sessionUser != null) {
      _refreshParentOverview();
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
            _isPendingApproval = true;
            _isAuthenticated = false;
          });
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

    if (_requiresUpdate) {
      return ForceUpdateScreen(
        currentVersion: _currentAppVersion,
        minVersion: _appConfig.minSupportedVersion,
        message: _forceUpdateMessage,
        onRetry: _refreshParentOverview,
      );
    }

    if (_isAuthenticated) {
      return ParentShell(
        sessionUser: _sessionUser,
        student: _linkedStudent,
        scores: _linkedScores,
        announcements: _announcements,
        events: _events,
        appConfig: _appConfig,
        initialNotificationType: _pendingNotificationType,
        initialNotificationEntityID: _pendingEntityID,
        onNotificationConsumed: () {
          setState(() {
            _pendingNotificationType = null;
            _pendingEntityID = null;
          });
        },
        onLogout: () async {
          await _clearSession();
          if (!mounted) return;
          setState(() {
            _isAuthenticated = false;
            _sessionUser = null;
            _linkedStudent = null;
            _linkedScores = const [];
            _announcements = const [];
            _events = const [];
            _appConfig = const ParentAppConfig(
                featureFlags: {},
                dashboardWidgets: [],
                minSupportedVersion: '',
                forceUpdateMessage: '');
            _requiresUpdate = false;
          });
        },
      );
    }
    return AuthScreen(
      firebaseEnabled: _firebaseReady,
      onAuthSuccess: (sessionUser, authToken) {
        setState(() {
          _authToken = authToken;
          _sessionUser = sessionUser;
          _needsChildLinking = false;
          _isAuthenticated = false;
          _isPendingApproval = false;
        });
        _persistSession(sessionUser, _apiBase, authToken);
        _refreshParentOverview();
      },
    );
  }

  Future<void> _registerDeviceToken(BackendClient client) async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await client.registerDeviceToken(_authToken, token);
    } catch (_) {
      // Ignore token registration failures in app runtime.
    }
  }

  bool _isVersionOutdated(String current, String minRequired) {
    if (minRequired.trim().isEmpty) return false;
    List<int> parse(String value) =>
        value.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final currentParts = parse(current);
    final minParts = parse(minRequired);
    final length = currentParts.length > minParts.length
        ? currentParts.length
        : minParts.length;
    for (var i = 0; i < length; i++) {
      final left = i < currentParts.length ? currentParts[i] : 0;
      final right = i < minParts.length ? minParts[i] : 0;
      if (left < right) return true;
      if (left > right) return false;
    }
    return false;
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

class ParentAnnouncement {
  final String id;
  final String title;
  final String content;
  final String category;
  final String priority;
  final bool published;
  final DateTime? createdAt;

  const ParentAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.priority,
    required this.published,
    required this.createdAt,
  });

  factory ParentAnnouncement.fromJson(Map<String, dynamic> json) {
    return ParentAnnouncement(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      priority: (json['priority'] ?? '').toString(),
      published: (json['published'] ?? false) == true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }
}

class ParentEvent {
  final String id;
  final String title;
  final String description;
  final String category;
  final String location;
  final String audience;
  final String startTime;
  final String endTime;
  final DateTime? eventDate;
  final bool published;

  const ParentEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.location,
    required this.audience,
    required this.startTime,
    required this.endTime,
    required this.eventDate,
    required this.published,
  });

  factory ParentEvent.fromJson(Map<String, dynamic> json) {
    return ParentEvent(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      audience: (json['audience'] ?? '').toString(),
      startTime: (json['start_time'] ?? '').toString(),
      endTime: (json['end_time'] ?? '').toString(),
      eventDate: DateTime.tryParse((json['event_date'] ?? '').toString()),
      published: (json['published'] ?? false) == true,
    );
  }
}

class DashboardMetric {
  final String key;
  final String label;
  final String value;
  final String hint;
  final String icon;

  const DashboardMetric({
    required this.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
  });

  factory DashboardMetric.fromJson(Map<String, dynamic> json) {
    return DashboardMetric(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      value: (json['value'] ?? '').toString(),
      hint: (json['hint'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
    );
  }
}

class ParentAppConfig {
  final Map<String, bool> featureFlags;
  final List<DashboardMetric> dashboardWidgets;
  final String minSupportedVersion;
  final String forceUpdateMessage;

  const ParentAppConfig({
    required this.featureFlags,
    required this.dashboardWidgets,
    required this.minSupportedVersion,
    required this.forceUpdateMessage,
  });

  bool isEnabled(String key, {bool fallback = true}) {
    return featureFlags.containsKey(key) ? featureFlags[key] == true : fallback;
  }

  factory ParentAppConfig.fromJson(Map<String, dynamic> json) {
    final rawFlags = json['feature_flags'];
    final rawWidgets = json['dashboard_widgets'];
    final flags = <String, bool>{};
    if (rawFlags is Map<String, dynamic>) {
      rawFlags.forEach((key, value) => flags[key] = value == true);
    }
    return ParentAppConfig(
      featureFlags: flags,
      dashboardWidgets: rawWidgets is List
          ? rawWidgets
              .whereType<Map<String, dynamic>>()
              .map(DashboardMetric.fromJson)
              .toList()
          : const [],
      minSupportedVersion: (json['min_supported_version'] ?? '').toString(),
      forceUpdateMessage: (json['force_update_message'] ?? '').toString(),
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
      throw Exception(
          'Login failed (${response.statusCode}): ${_extractError(response.body)}');
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
      throw Exception(
          'Signup request failed (${response.statusCode}): ${_extractError(response.body)}');
    }
  }

  Future<List<String>> fetchDistricts(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/reference/districts'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Districts fetch failed (${response.statusCode}): ${_extractError(response.body)}');
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
      throw Exception(
          'Overview fetch failed (${response.statusCode}): ${_extractError(response.body)}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final status = (body['status'] ?? '').toString();
    final studentJson = body['student'];
    final scoresJson = body['scores'];

    return ParentOverview(
      status: status,
      student: studentJson is Map<String, dynamic>
          ? ParentStudent.fromJson(studentJson)
          : null,
      scores: scoresJson is List
          ? scoresJson
              .whereType<Map<String, dynamic>>()
              .map(ParentScore.fromJson)
              .toList()
          : const [],
    );
  }

  Future<List<ParentAnnouncement>> fetchAnnouncements(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/announcements'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Announcements fetch failed (${response.statusCode}): ${_extractError(response.body)}');
    }
    final body = jsonDecode(response.body);
    if (body is! List) return const [];
    return body
        .whereType<Map<String, dynamic>>()
        .map(ParentAnnouncement.fromJson)
        .toList();
  }

  Future<List<ParentEvent>> fetchEvents(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/events'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Events fetch failed (${response.statusCode}): ${_extractError(response.body)}');
    }
    final body = jsonDecode(response.body);
    if (body is! List) return const [];
    return body
        .whereType<Map<String, dynamic>>()
        .map(ParentEvent.fromJson)
        .toList();
  }

  Future<ParentAppConfig> fetchAppConfig(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/app-config'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'App config fetch failed (${response.statusCode}): ${_extractError(response.body)}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      return const ParentAppConfig(
        featureFlags: {},
        dashboardWidgets: [],
        minSupportedVersion: '',
        forceUpdateMessage: '',
      );
    }
    return ParentAppConfig.fromJson(body);
  }

  Future<void> registerDeviceToken(String token, String deviceToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/devices/token'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'token': deviceToken,
        'platform': 'android',
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Device token registration failed (${response.statusCode}): ${_extractError(response.body)}');
    }
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
  final bool firebaseEnabled;
  final void Function(SessionUser user, String authToken) onAuthSuccess;

  const AuthScreen({
    super.key,
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
  final String _apiBase = kApiBaseUrl;
  String _verificationId = '';
  int? _resendToken;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

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
        final userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);
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
      widget.onAuthSuccess(sessionUser, authToken);
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
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isSignup
                          ? 'Create your parent account'
                          : 'Login with phone and OTP',
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        'Server: $_apiBase',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF475569)),
                      ),
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
                      decoration:
                          const InputDecoration(labelText: 'Phone Number'),
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
                          onPressed: (_loading || _resendSeconds > 0)
                              ? null
                              : _sendOtp,
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
                        onPressed: _loading
                            ? null
                            : (_otpSent ? _verifyOtp : _sendOtp),
                        child: Text(_loading
                            ? 'Please wait...'
                            : (_otpSent ? 'Verify OTP' : 'Send OTP')),
                      ),
                    ),
                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _status,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF475569)),
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
      await client.requestParentLinkByClassRoll(
          widget.authToken, district, classLabel, roll);
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
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
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
                        decoration:
                            const InputDecoration(labelText: 'District'),
                        items: _districts
                            .map((district) => DropdownMenuItem<String>(
                                  value: district,
                                  child: Text(district),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedDistrict = value),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _classController,
                      decoration: const InputDecoration(
                          labelText: 'Class (example: Class 10)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _rollController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Roll Number'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        child:
                            Text(_loading ? 'Submitting...' : 'Submit request'),
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
                      Text(_status,
                          style: const TextStyle(color: Color(0xFF475569))),
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
                const Icon(Icons.hourglass_top_rounded,
                    size: 48, color: Color(0xFF4F46E5)),
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

class ForceUpdateScreen extends StatelessWidget {
  final String currentVersion;
  final String minVersion;
  final String message;
  final VoidCallback onRetry;

  const ForceUpdateScreen({
    super.key,
    required this.currentVersion,
    required this.minVersion,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 14,
                  offset: Offset(0, 8))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.system_update_alt,
                  size: 46, color: Color(0xFF4F46E5)),
              const SizedBox(height: 12),
              const Text(
                'Update Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 10),
              Text(
                'Current: $currentVersion  •  Required: $minVersion',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
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
  final List<ParentAnnouncement> announcements;
  final List<ParentEvent> events;
  final ParentAppConfig appConfig;
  final String? initialNotificationType;
  final String? initialNotificationEntityID;
  final VoidCallback onNotificationConsumed;
  final VoidCallback onLogout;

  const ParentShell({
    super.key,
    required this.onLogout,
    required this.sessionUser,
    required this.student,
    required this.scores,
    required this.announcements,
    required this.events,
    required this.appConfig,
    required this.initialNotificationType,
    required this.initialNotificationEntityID,
    required this.onNotificationConsumed,
  });

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyNotificationRouting();
    });
  }

  @override
  void didUpdateWidget(covariant ParentShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialNotificationType != oldWidget.initialNotificationType ||
        widget.initialNotificationEntityID != oldWidget.initialNotificationEntityID) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyNotificationRouting();
      });
    }
  }

  int _tabIndex(String tab) {
    final showAcademic = widget.appConfig.isEnabled('show_academic_tab');
    final showEvents = widget.appConfig.isEnabled('show_events', fallback: true);
    final showNews =
        widget.appConfig.isEnabled('show_announcements', fallback: true);
    var cursor = 0; // home
    if (tab == 'home') return cursor;
    if (showAcademic) {
      cursor++;
      if (tab == 'academic') return cursor;
    }
    if (showEvents) {
      cursor++;
      if (tab == 'events') return cursor;
    }
    if (showNews) {
      cursor++;
      if (tab == 'news') return cursor;
    }
    return 0;
  }

  void _applyNotificationRouting() {
    final type = widget.initialNotificationType;
    final entityID = widget.initialNotificationEntityID;
    if (type == null || type.isEmpty) return;

    if (type == 'announcement') {
      setState(() => _index = _tabIndex('news'));
      if (entityID != null && entityID.isNotEmpty) {
        final match = widget.announcements.where((a) => a.id == entityID).toList();
        if (match.isNotEmpty) {
          final item = match.first;
          _showInfoDialog(
            context: context,
            title: item.title,
            subtitle:
                '${item.createdAt != null ? '${item.createdAt!.day} ${_monthName(item.createdAt!.month)} ${item.createdAt!.year}' : 'Recent'}  |  ${item.category.isEmpty ? 'General' : item.category}',
            content: item.content,
          );
        }
      }
      widget.onNotificationConsumed();
      return;
    }
    if (type == 'event') {
      setState(() => _index = _tabIndex('events'));
      widget.onNotificationConsumed();
      return;
    }
    if (type == 'score_upload') {
      setState(() => _index = _tabIndex('academic'));
      widget.onNotificationConsumed();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showAcademic = widget.appConfig.isEnabled('show_academic_tab');
    final screens = <Widget>[
      DashboardScreen(
        sessionUser: widget.sessionUser,
        student: widget.student,
        scores: widget.scores,
        events: widget.events,
        announcements: widget.announcements,
        appConfig: widget.appConfig,
        onViewAllScores: () => setState(() => _index = _tabIndex('academic')),
        onViewAllEvents: () => setState(() => _index = _tabIndex('events')),
        onViewAllAnnouncements: () => setState(() => _index = _tabIndex('news')),
      ),
      if (showAcademic) const AcademicScreen(),
      if (widget.appConfig.isEnabled('show_events', fallback: true))
        EventsScreen(events: widget.events),
      if (widget.appConfig.isEnabled('show_announcements', fallback: true))
        NewsScreen(announcements: widget.announcements),
      ProfileScreen(
        onLogout: widget.onLogout,
        sessionUser: widget.sessionUser,
        student: widget.student,
        scores: widget.scores,
      ),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
          icon: Icon(Icons.home_outlined), label: 'Home'),
      if (showAcademic)
        const NavigationDestination(
            icon: Icon(Icons.school_outlined), label: 'Academic'),
      if (widget.appConfig.isEnabled('show_events', fallback: true))
        const NavigationDestination(
            icon: Icon(Icons.event_outlined), label: 'Events'),
      if (widget.appConfig.isEnabled('show_announcements', fallback: true))
        const NavigationDestination(
            icon: Icon(Icons.notifications_outlined), label: 'News'),
      const NavigationDestination(
          icon: Icon(Icons.person_outline), label: 'Profile'),
    ];
    final selectedIndex = _index.clamp(0, screens.length - 1);

    return Scaffold(
      body: screens[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: destinations,
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
          colors: [kBrandNavy, kBrandNavyLight],
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
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/jnv-logo.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'JNV Parent Portal',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
                    style:
                        const TextStyle(color: Color(0xFFF4E6B2), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white24,
            child: Icon(Icons.auto_awesome, color: Color(0xFFF4E6B2)),
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
  final List<ParentEvent> events;
  final List<ParentAnnouncement> announcements;
  final ParentAppConfig appConfig;
  final VoidCallback onViewAllScores;
  final VoidCallback onViewAllEvents;
  final VoidCallback onViewAllAnnouncements;

  const DashboardScreen({
    super.key,
    required this.sessionUser,
    required this.student,
    required this.scores,
    required this.events,
    required this.announcements,
    required this.appConfig,
    required this.onViewAllScores,
    required this.onViewAllEvents,
    required this.onViewAllAnnouncements,
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
                StudentSummaryCard(
                  sessionUser: sessionUser,
                  student: student,
                  dashboardWidgets: appConfig.dashboardWidgets,
                ),
                const SizedBox(height: 16),
                SectionHeader(
                  icon: Icons.menu_book_rounded,
                  iconColor: Color(0xFF16A34A),
                  title: 'Recent Scores',
                  subtitle: 'Last 4 tests',
                  onViewAll: onViewAllScores,
                ),
                const SizedBox(height: 12),
                RecentScoresCard(scores: scores),
                const SizedBox(height: 20),
                if (appConfig.isEnabled('show_events', fallback: true)) ...[
                  SectionHeader(
                    icon: Icons.event_available_rounded,
                    iconColor: Color(0xFF7C3AED),
                    title: 'Upcoming Events',
                    subtitle: 'Next 3 events',
                    onViewAll: onViewAllEvents,
                  ),
                  const SizedBox(height: 12),
                  UpcomingEventsCard(events: events),
                  const SizedBox(height: 20),
                ],
                if (appConfig.isEnabled('show_announcements',
                    fallback: true)) ...[
                  SectionHeader(
                    icon: Icons.notifications_active_rounded,
                    iconColor: Color(0xFFF97316),
                    title: 'Announcements',
                    subtitle: 'Recent updates',
                    onViewAll: onViewAllAnnouncements,
                  ),
                  const SizedBox(height: 12),
                  AnnouncementsCard(announcements: announcements),
                ],
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
  final List<DashboardMetric> dashboardWidgets;

  const StudentSummaryCard(
      {super.key,
      required this.sessionUser,
      required this.student,
      required this.dashboardWidgets});

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
          BoxShadow(
              color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8)),
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
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
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
            children: (dashboardWidgets.isEmpty
                    ? const [
                        DashboardMetric(
                            key: 'gpa',
                            label: 'GPA',
                            value: '9.2',
                            hint: 'This term',
                            icon: 'school'),
                        DashboardMetric(
                            key: 'attendance',
                            label: 'Attend',
                            value: '94.5%',
                            hint: 'Monthly avg',
                            icon: 'check_circle'),
                        DashboardMetric(
                            key: 'rank',
                            label: 'Rank',
                            value: '#3',
                            hint: 'Class standing',
                            icon: 'emoji_events'),
                      ]
                    : dashboardWidgets.take(3).toList())
                .asMap()
                .entries
                .map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: idx < 2 ? 10 : 0),
                  child: StatCard(title: item.label, value: item.value),
                ),
              );
            }).toList(),
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
          Text(title,
              style: const TextStyle(color: Color(0xFFE5E7FF), fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
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
  final VoidCallback? onViewAll;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onViewAll,
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
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ],
        ),
        GestureDetector(
          onTap: onViewAll,
          child: Text(
            'View All',
            style: TextStyle(
              color: onViewAll != null
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
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
        boxShadow: const [
          BoxShadow(
              color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))
        ],
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
                                Text(item.subject,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(dateText,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF64748B))),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (item.grade == 'A+'
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFDBEAFE)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              item.grade.isEmpty ? '-' : item.grade,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: (item.grade == 'A+'
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFF1D4ED8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                              '${score.toStringAsFixed(0)}/${maxScore.toStringAsFixed(0)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: score / maxScore,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor:
                              const AlwaysStoppedAnimation(Color(0xFF6366F1)),
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
  final List<ParentEvent> events;

  const UpcomingEventsCard({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final displayEvents = events.isEmpty
        ? const [
            ParentEvent(
              id: 'local-1',
              title: 'Annual Sports Day',
              description: '',
              category: 'Sports',
              location: '',
              audience: '',
              startTime: '9:00 AM',
              endTime: '',
              eventDate: null,
              published: true,
            ),
            ParentEvent(
              id: 'local-2',
              title: 'Parent-Teacher Meeting',
              description: '',
              category: 'Meeting',
              location: '',
              audience: '',
              startTime: '10:00 AM',
              endTime: '',
              eventDate: null,
              published: true,
            ),
            ParentEvent(
              id: 'local-3',
              title: 'Science Exhibition',
              description: '',
              category: 'Academic',
              location: '',
              audience: '',
              startTime: '11:00 AM',
              endTime: '',
              eventDate: null,
              published: true,
            ),
          ]
        : events.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))
        ],
      ),
      child: Column(
        children: displayEvents.map((event) {
          final date = event.eventDate;
          final dateParts = date == null
              ? ['--', '--']
              : [_monthName(date.month), date.day.toString()];
          final timeLabel = event.endTime.isNotEmpty
              ? '${event.startTime} - ${event.endTime}'
              : event.startTime;
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
                          style: const TextStyle(
                              color: Color(0xFF4F46E5),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      Text(dateParts[1],
                          style: const TextStyle(
                              color: Color(0xFF1E1B4B),
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(timeLabel,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF64748B))),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          event.category.isEmpty ? 'General' : event.category,
                          style: const TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
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
  final List<ParentAnnouncement> announcements;

  const AnnouncementsCard({super.key, required this.announcements});

  @override
  Widget build(BuildContext context) {
    final displayAnnouncements = announcements.isEmpty
        ? const [
            ParentAnnouncement(
              id: 'local-1',
              title: 'Winter Break Schedule',
              content: '',
              category: 'Important',
              priority: 'high',
              published: true,
              createdAt: null,
            ),
            ParentAnnouncement(
              id: 'local-2',
              title: 'New Library Books Available',
              content: '',
              category: 'Notice',
              priority: 'normal',
              published: true,
              createdAt: null,
            ),
          ]
        : announcements.take(2).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))
        ],
      ),
      child: Column(
        children: displayAnnouncements.map((item) {
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: item.priority.toLowerCase() == 'high'
                          ? const Color(0xFFFEE2E2)
                          : const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.category.isEmpty ? 'Notice' : item.category,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                            item.createdAt != null
                                ? '${_monthName(item.createdAt!.month)} ${item.createdAt!.day}, ${item.createdAt!.year}'
                                : 'Recently',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF64748B))),
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
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: StatCard(title: 'GPA', value: '9.2')),
                          SizedBox(width: 10),
                          Expanded(
                              child: StatCard(title: 'Avg %', value: '89.5')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Term Reports',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 16,
                          offset: Offset(0, 8))
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Term 1 - 2025-26',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('Performance Report',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF64748B))),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('GPA',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF64748B))),
                              Text('9.2',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF4F46E5))),
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
                                    child: const Icon(
                                        Icons.description_outlined,
                                        size: 18,
                                        color: Color(0xFF4F46E5)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(subject['name'] as String,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        const Text('100 marks',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                  Text('$score',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
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
                                  valueColor: const AlwaysStoppedAnimation(
                                      Color(0xFF6366F1)),
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

void _showInfoDialog({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String content,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          Text(content),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class EventsScreen extends StatelessWidget {
  final List<ParentEvent> events;

  const EventsScreen({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final upcoming = events.isEmpty
        ? [
            {
              'date': 'Jan 25',
              'title': 'Annual Sports Day',
              'time': '9:00 AM - 5:00 PM',
              'location': 'School Sports Ground',
              'people': 'All Students',
              'type': 'Sports',
              'color': const Color(0xFFF97316)
            },
            {
              'date': 'Jan 28',
              'title': 'Parent-Teacher Meeting',
              'time': '10:00 AM - 2:00 PM',
              'location': 'Main Auditorium',
              'people': 'Parents & Teachers',
              'type': 'Meeting',
              'color': const Color(0xFF3B82F6)
            },
            {
              'date': 'Feb 5',
              'title': 'Science Exhibition',
              'time': '11:00 AM - 4:00 PM',
              'location': 'Science Lab',
              'people': 'Classes 8-12',
              'type': 'Academic',
              'color': const Color(0xFF7C3AED)
            },
          ]
        : events.map((event) {
            final date = event.eventDate;
            final category = event.category.toLowerCase();
            final color = category.contains('sport')
                ? const Color(0xFFF97316)
                : category.contains('meeting')
                    ? const Color(0xFF3B82F6)
                    : const Color(0xFF7C3AED);
            final time = event.endTime.isNotEmpty
                ? '${event.startTime} - ${event.endTime}'
                : event.startTime;
            final dateLabel = date == null
                ? '-- --'
                : '${_monthName(date.month)} ${date.day}';
            return {
              'date': dateLabel,
              'title': event.title,
              'time': time,
              'location': event.location,
              'people': event.audience,
              'type': event.category.isEmpty ? 'General' : event.category,
              'color': color,
            };
          }).toList();

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
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text('Stay updated with school events',
                                style: TextStyle(
                                    color: Color(0xFFE5E7FF), fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Upcoming Events',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...upcoming.map((event) {
                  final dateParts = (event['date'] as String).split(' ');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 16,
                            offset: Offset(0, 8))
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: event['color'] as Color,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20)),
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(dateParts[0],
                                            style: const TextStyle(
                                                color: Color(0xFF4F46E5),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12)),
                                        Text(dateParts[1],
                                            style: const TextStyle(
                                                color: Color(0xFF1E1B4B),
                                                fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: (event['color'] as Color)
                                                .withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(event['type'] as String,
                                              style: TextStyle(
                                                  color:
                                                      event['color'] as Color,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(event['title'] as String,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        Text(event['time'] as String,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B))),
                                        Text(event['location'] as String,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B))),
                                        Text(event['people'] as String,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonal(
                                  onPressed: () {
                                    _showInfoDialog(
                                      context: context,
                                      title: event['title'] as String,
                                      subtitle:
                                          '${event['date']}  |  ${event['time']}',
                                      content:
                                          '${event['location']}\nAudience: ${event['people']}\nType: ${event['type']}',
                                    );
                                  },
                                  child: const Text('View Details'),
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
                const Text('Past Events',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 16,
                          offset: Offset(0, 8))
                    ],
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
                              child: const Icon(Icons.event,
                                  color: Color(0xFF64748B)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(event['title'] as String,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(event['date'] as String,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDE9FE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(event['type'] as String,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF7C3AED))),
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
  final List<ParentAnnouncement> announcements;

  const NewsScreen({super.key, required this.announcements});

  String _formatDate(DateTime? value) {
    if (value == null) return 'Recently';
    final months = [
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
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }

  Color _tagColor(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('urgent') || normalized.contains('high')) {
      return const Color(0xFFB91C1C);
    }
    if (normalized.contains('academic')) return const Color(0xFF1D4ED8);
    if (normalized.contains('event')) return const Color(0xFF7C3AED);
    return const Color(0xFF475569);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...announcements]..sort((a, b) {
        final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
    final pinned = sorted.take(2).toList();

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
                  child: const Row(
                    children: [
                      Icon(Icons.notifications_active, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Announcements',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text('Latest school updates and notices',
                                style: TextStyle(
                                    color: Color(0xFFE5E7FF), fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (sorted.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Text(
                      'No announcements yet. Ask staff/admin to publish one from the portal.',
                      style: TextStyle(color: Color(0xFF475569)),
                    ),
                  ),
                if (pinned.isNotEmpty) ...[
                  Row(
                    children: const [
                      Icon(Icons.push_pin, size: 18, color: Color(0xFF4F46E5)),
                      SizedBox(width: 6),
                      Text('Pinned',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...pinned.map((item) {
                    final category =
                        item.category.isEmpty ? 'General' : item.category;
                    final priority =
                        item.priority.isEmpty ? 'Normal' : item.priority;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE0E7FF)),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 16,
                              offset: Offset(0, 8)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(
                            '${_formatDate(item.createdAt)}  •  $category',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDE9FE),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  priority,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _tagColor(priority),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF475569)),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () {
                                _showInfoDialog(
                                  context: context,
                                  title: item.title,
                                  subtitle:
                                      '${_formatDate(item.createdAt)}  |  $category',
                                  content: item.content,
                                );
                              },
                              child: const Text('Read More'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                if (sorted.length > 2) ...[
                  const SizedBox(height: 8),
                  const Text('All Announcements',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  ...sorted.skip(2).map((item) {
                    final category =
                        item.category.isEmpty ? 'General' : item.category;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 16,
                              offset: Offset(0, 8)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(item.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatDate(item.createdAt),
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF475569)),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              _showInfoDialog(
                                context: context,
                                title: item.title,
                                subtitle:
                                    '${_formatDate(item.createdAt)}  |  $category',
                                content: item.content,
                              );
                            },
                            child: const Text('Read more'),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
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
      subjectMap[score.subject]!
          .add(score.maxScore > 0 ? (score.score / score.maxScore) * 100 : 0);
    }
    final subjects = subjectMap.entries.map((entry) {
      final values = entry.value;
      final avg =
          values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
      return {'name': entry.key, 'score': avg};
    }).toList();

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
                        child: Text('A',
                            style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(height: 12),
                      Text(
                          (student?.fullName.isNotEmpty ?? false)
                              ? student!.fullName
                              : (sessionUser?.name.isNotEmpty ?? false)
                                  ? sessionUser!.name
                                  : 'Parent User',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text(
                          (student != null && student!.classLabel.isNotEmpty)
                              ? '${student!.classLabel} • Roll ${student!.rollNumber}'
                              : (sessionUser?.phone.isNotEmpty ?? false)
                                  ? sessionUser!.phone
                                  : 'Class 10-A • JNV2024-1045',
                          style: const TextStyle(
                              color: Color(0xFFE5E7FF), fontSize: 12)),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: StatCard(title: 'GPA', value: '9.2')),
                          SizedBox(width: 10),
                          Expanded(
                              child: StatCard(title: 'Attend', value: '94.5%')),
                          SizedBox(width: 10),
                          Expanded(child: StatCard(title: 'Rank', value: '#3')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const InfoSectionTitle(
                    title: 'Student Information', icon: Icons.person),
                const SizedBox(height: 12),
                InfoCard(
                  rows: [
                    const InfoRow(
                        label: 'Date of Birth',
                        value: 'On file',
                        icon: Icons.cake),
                    const InfoRow(
                        label: 'Admission Date',
                        value: 'On file',
                        icon: Icons.calendar_today),
                    InfoRow(
                      label: 'House',
                      value: (student?.house.isNotEmpty ?? false)
                          ? student!.house
                          : 'Not assigned',
                      icon: Icons.home,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const InfoSectionTitle(
                    title: 'Parent Information', icon: Icons.family_restroom),
                const SizedBox(height: 12),
                InfoCard(
                  rows: [
                    InfoRow(
                      label: 'Parent Name',
                      value: (sessionUser?.name.isNotEmpty ?? false)
                          ? sessionUser!.name
                          : 'Pending',
                      icon: Icons.person_outline,
                    ),
                    InfoRow(
                      label: 'Contact',
                      value: (sessionUser?.phone.isNotEmpty ?? false)
                          ? sessionUser!.phone
                          : 'Pending',
                      icon: Icons.phone,
                    ),
                    const InfoRow(
                        label: 'Email', value: 'Not set', icon: Icons.email),
                  ],
                ),
                const SizedBox(height: 16),
                const InfoSectionTitle(
                    title: 'Current Subjects', icon: Icons.menu_book),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 16,
                          offset: Offset(0, 8))
                    ],
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(item['name'] as String,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            const SizedBox(height: 4),
                                            const Text('Calculated average',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF64748B))),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCFCE7),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                            '${avgScore.toStringAsFixed(1)}%',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF15803D))),
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
                                      valueColor: const AlwaysStoppedAnimation(
                                          Color(0xFF6366F1)),
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
        boxShadow: const [
          BoxShadow(
              color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 8))
        ],
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
                        child: Icon(row.icon,
                            size: 18, color: const Color(0xFF4F46E5)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.label,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF64748B))),
                            const SizedBox(height: 2),
                            Text(row.value,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
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
