import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DataUsageMonitorApp());
}

class DataUsageMonitorApp extends StatelessWidget {
  const DataUsageMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مراقب وقاطع البيانات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [Locale('ar', 'SA')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          color: Colors.white,
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: DataUsageDashboardScreen(),
      ),
    );
  }
}

/// نموذج بيانات استهلاك التطبيق الواحد
class AppUsageRecord {
  final int uid;
  final String packageName;
  final String appName;
  final bool isSystemApp;
  final int wifiRxBytes; // التنزيل عبر الواي فاي
  final int wifiTxBytes; // الرفع عبر الواي فاي
  final int mobileRxBytes; // التنزيل عبر بيانات الهاتف
  final int mobileTxBytes; // الرفع عبر بيانات الهاتف
  final Uint8List? iconBytes;

  AppUsageRecord({
    required this.uid,
    required this.packageName,
    required this.appName,
    required this.isSystemApp,
    required this.wifiRxBytes,
    required this.wifiTxBytes,
    required this.mobileRxBytes,
    required this.mobileTxBytes,
    this.iconBytes,
  });

  int get totalWifiBytes => wifiRxBytes + wifiTxBytes;
  int get totalMobileBytes => mobileRxBytes + mobileTxBytes;
  int get totalRxBytes => wifiRxBytes + mobileRxBytes;
  int get totalTxBytes => wifiTxBytes + mobileTxBytes;
  int get totalBytes => totalWifiBytes + totalMobileBytes;

  int bytesForFilter(NetworkTypeFilter filter) {
    switch (filter) {
      case NetworkTypeFilter.all:
        return totalBytes;
      case NetworkTypeFilter.mobile:
        return totalMobileBytes;
      case NetworkTypeFilter.wifi:
        return totalWifiBytes;
    }
  }

  int rxBytesForFilter(NetworkTypeFilter filter) {
    switch (filter) {
      case NetworkTypeFilter.all:
        return totalRxBytes;
      case NetworkTypeFilter.mobile:
        return mobileRxBytes;
      case NetworkTypeFilter.wifi:
        return wifiRxBytes;
    }
  }

  int txBytesForFilter(NetworkTypeFilter filter) {
    switch (filter) {
      case NetworkTypeFilter.all:
        return totalTxBytes;
      case NetworkTypeFilter.mobile:
        return mobileTxBytes;
      case NetworkTypeFilter.wifi:
        return wifiTxBytes;
    }
  }

  factory AppUsageRecord.fromMap(Map<dynamic, dynamic> map) {
    Uint8List? decodedIcon;
    final String? b64 = map['iconBase64'] as String?;
    if (b64 != null && b64.isNotEmpty) {
      try {
        decodedIcon = base64Decode(b64);
      } catch (_) {}
    }
    return AppUsageRecord(
      uid: (map['uid'] as num?)?.toInt() ?? 0,
      packageName: (map['packageName'] as String?) ?? 'unknown',
      appName: (map['appName'] as String?) ?? 'تطبيق غير معروف',
      isSystemApp: (map['isSystemApp'] as bool?) ?? false,
      wifiRxBytes: (map['wifiRxBytes'] as num?)?.toInt() ?? 0,
      wifiTxBytes: (map['wifiTxBytes'] as num?)?.toInt() ?? 0,
      mobileRxBytes: (map['mobileRxBytes'] as num?)?.toInt() ?? 0,
      mobileTxBytes: (map['mobileTxBytes'] as num?)?.toInt() ?? 0,
      iconBytes: decodedIcon,
    );
  }
}

/// نموذج سجل استهلاك يومي محفوظ للتاريخ والترحيل
class DailyHistoryLog {
  final String dateKey; // YYYY-MM-DD
  final int mobileBytes;
  final int wifiBytes;
  final String topAppName;
  final int topAppBytes;
  final double rolledOverMB; // الرصيد المرحّل لليوم التالي بالميجابايت

  DailyHistoryLog({
    required this.dateKey,
    required this.mobileBytes,
    required this.wifiBytes,
    required this.topAppName,
    required this.topAppBytes,
    this.rolledOverMB = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'mobileBytes': mobileBytes,
        'wifiBytes': wifiBytes,
        'topAppName': topAppName,
        'topAppBytes': topAppBytes,
        'rolledOverMB': rolledOverMB,
      };

  factory DailyHistoryLog.fromJson(Map<String, dynamic> json) {
    return DailyHistoryLog(
      dateKey: json['dateKey'] as String? ?? '',
      mobileBytes: (json['mobileBytes'] as num?)?.toInt() ?? 0,
      wifiBytes: (json['wifiBytes'] as num?)?.toInt() ?? 0,
      topAppName: json['topAppName'] as String? ?? '-',
      topAppBytes: (json['topAppBytes'] as num?)?.toInt() ?? 0,
      rolledOverMB: (json['rolledOverMB'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// نموذج تنبيه تجاوز أو اقتراب من السقف
class UsageAlertItem {
  final String id;
  final String title;
  final String description;
  final double ratio;
  final bool isExceeded;
  final bool isBlocked;
  final String? packageName;

  UsageAlertItem({
    required this.id,
    required this.title,
    required this.description,
    required this.ratio,
    required this.isExceeded,
    this.isBlocked = false,
    this.packageName,
  });
}

enum NetworkTypeFilter { all, mobile, wifi }

enum TimePeriodFilter { today, week, month }

enum AppSortOrder { highestTotal, highestDownload, capRatio, alphabetical }

class DataUsageDashboardScreen extends StatefulWidget {
  const DataUsageDashboardScreen({super.key});

  @override
  State<DataUsageDashboardScreen> createState() =>
      _DataUsageDashboardScreenState();
}

class _DataUsageDashboardScreenState extends State<DataUsageDashboardScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _channel =
      MethodChannel('com.example.data_usage_monitor/network_stats');

  int _currentBottomTab =
      0; // 0: التطبيقات, 1: القطع والسقف, 2: الترحيل والسجل

  bool _hasPermission = false;
  bool _isLoading = true;
  bool _isSimulationMode = false;
  bool _showSystemApps = false;
  String _searchQuery = '';

  NetworkTypeFilter _networkFilter = NetworkTypeFilter.all;
  TimePeriodFilter _periodFilter = TimePeriodFilter.today;
  AppSortOrder _sortOrder = AppSortOrder.highestTotal;

  // قوائم الاستهلاك الفعلية
  List<AppUsageRecord> _currentPeriodApps = [];
  List<AppUsageRecord> _todayApps = [];
  List<AppUsageRecord> _monthApps = [];

  // إعدادات الأسقف (بالميجابايت MB)
  double _dailyMobileCapMB = 500.0;
  double _monthlyMobileCapMB = 10240.0;
  double _dailyWifiCapMB = 5120.0;
  double _monthlyWifiCapMB = 153600.0;
  double _alertThresholdPercent = 80.0;

  // ميزة الترحيل التلقائي للرصيد المتبقي من السقف اليومي لليوم التالي
  bool _enableDailyRollover = true;
  double _accumulatedRolloverMB = 0.0;
  String _lastRolloverDateKey = '';

  // ميزة القطع التلقائي للإنترنت عن التطبيقات المتجاوزة للحد (عبر FirewallVpnService)
  bool _autoBlockExceededApps = true;
  bool _isVpnFirewallActive = false;
  Set<String> _manuallyBlockedApps = {};
  Set<String> _autoBlockedApps = {};

  // السقف اليومي المخصص لكل تطبيق (packageName -> الحد اليومي بالميجابايت)
  Map<String, double> _perAppDailyCapMB = {};
  bool _applyAppCapToAllNetworks = true;

  // سجل الأيام المحفوظة
  List<DailyHistoryLog> _historyLogs = [];

  // التنبيهات النشطة
  List<UsageAlertItem> _activeAlerts = [];
  final Set<String> _notifiedAlertIds = {};

  Timer? _autoRefreshTimer;

  Set<String> get _allBlockedPackages =>
      {..._manuallyBlockedApps, ..._autoBlockedApps};

  double get _effectiveDailyMobileCapMB =>
      _dailyMobileCapMB + (_enableDailyRollover ? _accumulatedRolloverMB : 0.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedSettingsAndFetch();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshDataUsage(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDataUsage(silent: true);
    }
  }

  Future<void> _sendSystemNotification(String title, String body) async {
    if (_isSimulationMode) return;
    try {
      await _channel.invokeMethod('showSystemNotification', {
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  Future<void> _loadSavedSettingsAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dailyMobileCapMB = prefs.getDouble('dailyMobileCapMB') ?? 500.0;
      _monthlyMobileCapMB = prefs.getDouble('monthlyMobileCapMB') ?? 10240.0;
      _dailyWifiCapMB = prefs.getDouble('dailyWifiCapMB') ?? 5120.0;
      _monthlyWifiCapMB = prefs.getDouble('monthlyWifiCapMB') ?? 153600.0;
      _alertThresholdPercent = prefs.getDouble('alertThresholdPercent') ?? 80.0;
      _applyAppCapToAllNetworks =
          prefs.getBool('applyAppCapToAllNetworks') ?? true;
      _enableDailyRollover = prefs.getBool('enableDailyRollover') ?? true;
      _accumulatedRolloverMB = prefs.getDouble('accumulatedRolloverMB') ?? 0.0;
      _lastRolloverDateKey = prefs.getString('lastRolloverDateKey') ?? '';
      _autoBlockExceededApps = prefs.getBool('autoBlockExceededApps') ?? true;

      final List<String>? manualList =
          prefs.getStringList('manuallyBlockedApps');
      if (manualList != null) {
        _manuallyBlockedApps = manualList.toSet();
      }

      final String? appCapsJson = prefs.getString('perAppDailyCapMB');
      if (appCapsJson != null && appCapsJson.isNotEmpty) {
        final decoded = jsonDecode(appCapsJson) as Map<String, dynamic>;
        _perAppDailyCapMB = decoded.map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        );
      }

      final String? logsJson = prefs.getString('dailyHistoryLogs');
      if (logsJson != null && logsJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(logsJson) as List<dynamic>;
        _historyLogs = list
            .map((e) => DailyHistoryLog.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    });

    await _refreshDataUsage();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('dailyMobileCapMB', _dailyMobileCapMB);
    await prefs.setDouble('monthlyMobileCapMB', _monthlyMobileCapMB);
    await prefs.setDouble('dailyWifiCapMB', _dailyWifiCapMB);
    await prefs.setDouble('monthlyWifiCapMB', _monthlyWifiCapMB);
    await prefs.setDouble('alertThresholdPercent', _alertThresholdPercent);
    await prefs.setBool('applyAppCapToAllNetworks', _applyAppCapToAllNetworks);
    await prefs.setBool('enableDailyRollover', _enableDailyRollover);
    await prefs.setDouble('accumulatedRolloverMB', _accumulatedRolloverMB);
    await prefs.setString('lastRolloverDateKey', _lastRolloverDateKey);
    await prefs.setBool('autoBlockExceededApps', _autoBlockExceededApps);
    await prefs.setStringList(
        'manuallyBlockedApps', _manuallyBlockedApps.toList());
    await prefs.setString('perAppDailyCapMB', jsonEncode(_perAppDailyCapMB));
  }

  /// مزامنة قائمة التطبيقات المحظورة مع خدمة جدار الحماية (FirewallVpnService)
  Future<void> _syncFirewallBlockedApps() async {
    final packagesToBlock = _allBlockedPackages.toList();
    if (_isSimulationMode) {
      setState(() {
        _isVpnFirewallActive = packagesToBlock.isNotEmpty;
      });
      return;
    }
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'updateBlockedApps',
        {'blockedPackages': packagesToBlock},
      );
      if (res != null && mounted) {
        setState(() {
          _isVpnFirewallActive = (res['vpnActive'] as bool?) ?? false;
        });
      }
    } catch (_) {}
  }

  DateTime _getStartOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _getStartOfWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(const Duration(days: 6));
  }

  DateTime _getStartOfMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  Future<void> _refreshDataUsage({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    if (_isSimulationMode) {
      _loadSimulatedData();
      return;
    }

    try {
      final bool granted =
          await _channel.invokeMethod<bool>('checkUsagePermission') ?? false;
      if (!granted) {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
        return;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final todayStartMs = _getStartOfToday().millisecondsSinceEpoch;
      final monthStartMs = _getStartOfMonth().millisecondsSinceEpoch;
      final weekStartMs = _getStartOfWeek().millisecondsSinceEpoch;

      final List<dynamic> todayRaw = await _channel.invokeMethod(
            'getAppDataUsage',
            {
              'startTime': todayStartMs,
              'endTime': nowMs,
              'includeIcons': true,
            },
          ) ??
          [];

      final List<dynamic> monthRaw = await _channel.invokeMethod(
            'getAppDataUsage',
            {
              'startTime': monthStartMs,
              'endTime': nowMs,
              'includeIcons': false,
            },
          ) ??
          [];

      final todayParsed = todayRaw
          .map((e) => AppUsageRecord.fromMap(e as Map<dynamic, dynamic>))
          .toList();

      final Map<String, Uint8List?> iconMap = {
        for (final app in todayParsed)
          if (app.iconBytes != null) app.packageName: app.iconBytes
      };

      final monthParsed = monthRaw.map((e) {
        final map = Map<dynamic, dynamic>.from(e as Map<dynamic, dynamic>);
        final record = AppUsageRecord.fromMap(map);
        return AppUsageRecord(
          uid: record.uid,
          packageName: record.packageName,
          appName: record.appName,
          isSystemApp: record.isSystemApp,
          wifiRxBytes: record.wifiRxBytes,
          wifiTxBytes: record.wifiTxBytes,
          mobileRxBytes: record.mobileRxBytes,
          mobileTxBytes: record.mobileTxBytes,
          iconBytes: record.iconBytes ?? iconMap[record.packageName],
        );
      }).toList();

      List<AppUsageRecord> selectedPeriodApps;
      if (_periodFilter == TimePeriodFilter.today) {
        selectedPeriodApps = todayParsed;
      } else if (_periodFilter == TimePeriodFilter.month) {
        selectedPeriodApps = monthParsed;
      } else {
        final List<dynamic> weekRaw = await _channel.invokeMethod(
              'getAppDataUsage',
              {
                'startTime': weekStartMs,
                'endTime': nowMs,
                'includeIcons': false,
              },
            ) ??
            [];
        selectedPeriodApps = weekRaw.map((e) {
          final map = Map<dynamic, dynamic>.from(e as Map<dynamic, dynamic>);
          final record = AppUsageRecord.fromMap(map);
          return AppUsageRecord(
            uid: record.uid,
            packageName: record.packageName,
            appName: record.appName,
            isSystemApp: record.isSystemApp,
            wifiRxBytes: record.wifiRxBytes,
            wifiTxBytes: record.wifiTxBytes,
            mobileRxBytes: record.mobileRxBytes,
            mobileTxBytes: record.mobileTxBytes,
            iconBytes: record.iconBytes ?? iconMap[record.packageName],
          );
        }).toList();
      }

      setState(() {
        _hasPermission = true;
        _todayApps = todayParsed;
        _monthApps = monthParsed;
        _currentPeriodApps = selectedPeriodApps;
        _isLoading = false;
      });

      await _evaluateAlertsBlockingAndRollover();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _loadSimulatedData() {
    final demoToday = <AppUsageRecord>[
      AppUsageRecord(
        uid: 10101,
        packageName: 'com.google.android.youtube',
        appName: 'يوتيوب (YouTube)',
        isSystemApp: false,
        wifiRxBytes: 840 * 1024 * 1024,
        wifiTxBytes: 28 * 1024 * 1024,
        mobileRxBytes: 215 * 1024 * 1024,
        mobileTxBytes: 12 * 1024 * 1024,
      ),
      AppUsageRecord(
        uid: 10102,
        packageName: 'com.zhiliaoapp.musically',
        appName: 'تيك توك (TikTok)',
        isSystemApp: false,
        wifiRxBytes: 510 * 1024 * 1024,
        wifiTxBytes: 42 * 1024 * 1024,
        mobileRxBytes: 185 * 1024 * 1024,
        mobileTxBytes: 19 * 1024 * 1024,
      ),
      AppUsageRecord(
        uid: 10103,
        packageName: 'com.whatsapp',
        appName: 'واتساب (WhatsApp)',
        isSystemApp: false,
        wifiRxBytes: 145 * 1024 * 1024,
        wifiTxBytes: 68 * 1024 * 1024,
        mobileRxBytes: 54 * 1024 * 1024,
        mobileTxBytes: 22 * 1024 * 1024,
      ),
      AppUsageRecord(
        uid: 10104,
        packageName: 'com.instagram.android',
        appName: 'إنستغرام (Instagram)',
        isSystemApp: false,
        wifiRxBytes: 390 * 1024 * 1024,
        wifiTxBytes: 31 * 1024 * 1024,
        mobileRxBytes: 92 * 1024 * 1024,
        mobileTxBytes: 9 * 1024 * 1024,
      ),
      AppUsageRecord(
        uid: 10105,
        packageName: 'org.telegram.messenger',
        appName: 'تيليجرام (Telegram)',
        isSystemApp: false,
        wifiRxBytes: 275 * 1024 * 1024,
        wifiTxBytes: 24 * 1024 * 1024,
        mobileRxBytes: 48 * 1024 * 1024,
        mobileTxBytes: 6 * 1024 * 1024,
      ),
      AppUsageRecord(
        uid: 10106,
        packageName: 'com.android.chrome',
        appName: 'متصفح كروم (Chrome)',
        isSystemApp: false,
        wifiRxBytes: 190 * 1024 * 1024,
        wifiTxBytes: 15 * 1024 * 1024,
        mobileRxBytes: 38 * 1024 * 1024,
        mobileTxBytes: 5 * 1024 * 1024,
      ),
    ];

    final int multiplier = _periodFilter == TimePeriodFilter.today
        ? 1
        : (_periodFilter == TimePeriodFilter.week ? 6 : 18);

    final scaledApps = demoToday
        .map(
          (app) => AppUsageRecord(
            uid: app.uid,
            packageName: app.packageName,
            appName: app.appName,
            isSystemApp: app.isSystemApp,
            wifiRxBytes: app.wifiRxBytes * multiplier,
            wifiTxBytes: app.wifiTxBytes * multiplier,
            mobileRxBytes: app.mobileRxBytes * multiplier,
            mobileTxBytes: app.mobileTxBytes * multiplier,
          ),
        )
        .toList();

    final monthSimulated = demoToday
        .map(
          (app) => AppUsageRecord(
            uid: app.uid,
            packageName: app.packageName,
            appName: app.appName,
            isSystemApp: app.isSystemApp,
            wifiRxBytes: app.wifiRxBytes * 18,
            wifiTxBytes: app.wifiTxBytes * 18,
            mobileRxBytes: app.mobileRxBytes * 18,
            mobileTxBytes: app.mobileTxBytes * 18,
          ),
        )
        .toList();

    if (_perAppDailyCapMB.isEmpty) {
      _perAppDailyCapMB['com.google.android.youtube'] = 250.0;
      _perAppDailyCapMB['com.zhiliaoapp.musically'] = 200.0;
    }

    setState(() {
      _todayApps = demoToday;
      _monthApps = monthSimulated;
      _currentPeriodApps = scaledApps;
      _isLoading = false;
    });

    _evaluateAlertsBlockingAndRollover();
  }

  /// فحص الأسقف، تفعيل القطع التلقائي عن التطبيقات المتجاوزة، وترحيل البيانات
  Future<void> _evaluateAlertsBlockingAndRollover() async {
    final alerts = <UsageAlertItem>[];
    final thresholdRatio = _alertThresholdPercent / 100.0;
    final newAutoBlocked = <String>{};

    final int todayMobileBytes =
        _todayApps.fold(0, (sum, app) => sum + app.totalMobileBytes);
    final int todayWifiBytes =
        _todayApps.fold(0, (sum, app) => sum + app.totalWifiBytes);
    final int monthMobileBytes =
        _monthApps.fold(0, (sum, app) => sum + app.totalMobileBytes);

    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // ترحيل الرصيد المتبقي من اليوم السابق تلقائياً إذا بدأ يوم جديد
    if (_enableDailyRollover &&
        _lastRolloverDateKey.isNotEmpty &&
        _lastRolloverDateKey != todayKey &&
        _historyLogs.isNotEmpty) {
      final prevLog = _historyLogs.firstWhere(
        (l) => l.dateKey == _lastRolloverDateKey,
        orElse: () => DailyHistoryLog(
          dateKey: '',
          mobileBytes: 0,
          wifiBytes: 0,
          topAppName: '',
          topAppBytes: 0,
        ),
      );
      if (prevLog.dateKey.isNotEmpty) {
        final double usedPrevMB = prevLog.mobileBytes / (1024 * 1024);
        final double leftoverMB =
            (_dailyMobileCapMB - usedPrevMB).clamp(0.0, _dailyMobileCapMB);
        _accumulatedRolloverMB += leftoverMB;
      }
      _lastRolloverDateKey = todayKey;
      await _saveSettings();
    } else if (_lastRolloverDateKey.isEmpty) {
      _lastRolloverDateKey = todayKey;
      await _saveSettings();
    }

    final effectiveDailyCap = _effectiveDailyMobileCapMB;

    // 1. فحص سقف بيانات الهاتف اليومي (شاملاً الرصيد المرحّل)
    if (effectiveDailyCap > 0) {
      final capBytes = effectiveDailyCap * 1024 * 1024;
      final ratio = todayMobileBytes / capBytes;
      if (ratio >= thresholdRatio) {
        final exceeded = ratio >= 1.0;
        alerts.add(
          UsageAlertItem(
            id: 'global_daily_mobile',
            title: exceeded
                ? 'تجاوز السقف اليومي لبيانات الهاتف!'
                : 'اقتراب من السقف اليومي لبيانات الهاتف',
            description:
                'استهلكت ${_formatBytes(todayMobileBytes)} من أصل ${_formatMB(effectiveDailyCap)} (${(ratio * 100).toStringAsFixed(0)}%) اليوم.',
            ratio: ratio,
            isExceeded: exceeded,
          ),
        );
      }
    }

    // 2. فحص سقف بيانات الهاتف الشهري
    if (_monthlyMobileCapMB > 0) {
      final capBytes = _monthlyMobileCapMB * 1024 * 1024;
      final ratio = monthMobileBytes / capBytes;
      if (ratio >= thresholdRatio) {
        final exceeded = ratio >= 1.0;
        alerts.add(
          UsageAlertItem(
            id: 'global_monthly_mobile',
            title: exceeded
                ? 'تجاوز السقف الشهري لبيانات الهاتف!'
                : 'اقتراب من السقف الشهري لبيانات الهاتف',
            description:
                'استهلكت ${_formatBytes(monthMobileBytes)} من أصل ${_formatMB(_monthlyMobileCapMB)} (${(ratio * 100).toStringAsFixed(0)}%) هذا الشهر.',
            ratio: ratio,
            isExceeded: exceeded,
          ),
        );
      }
    }

    // 3. فحص السقف اليومي المخصص لكل تطبيق + القطع التلقائي
    for (final app in _todayApps) {
      final double? appCapMB = _perAppDailyCapMB[app.packageName];
      if (appCapMB != null && appCapMB > 0) {
        final int usedBytes = _applyAppCapToAllNetworks
            ? app.totalBytes
            : app.totalMobileBytes;
        final double capBytes = appCapMB * 1024 * 1024;
        final double ratio = usedBytes / capBytes;

        if (ratio >= thresholdRatio) {
          final exceeded = ratio >= 1.0;
          final shouldBlock = exceeded && _autoBlockExceededApps;
          if (shouldBlock) {
            newAutoBlocked.add(app.packageName);
          }
          alerts.add(
            UsageAlertItem(
              id: 'app_daily_${app.packageName}',
              title: shouldBlock
                  ? 'تم قطع الإنترنت تلقائياً عن ${app.appName}'
                  : (exceeded
                      ? 'تطبيق ${app.appName} تجاوز حده اليومي!'
                      : 'تطبيق ${app.appName} يقترب من حده اليومي'),
              description:
                  'استهلك ${_formatBytes(usedBytes)} من الحد اليومي (${_formatMB(appCapMB)} - ${(ratio * 100).toStringAsFixed(0)}%).',
              ratio: ratio,
              isExceeded: exceeded,
              isBlocked:
                  shouldBlock || _manuallyBlockedApps.contains(app.packageName),
              packageName: app.packageName,
            ),
          );
        }
      }
    }

    _autoBlockedApps = newAutoBlocked;
    await _syncFirewallBlockedApps();

    for (final alert in alerts) {
      final notifyKey =
          '${alert.id}_${alert.isExceeded ? "ex" : "warn"}_${alert.isBlocked ? "blk" : "open"}';
      if (!_notifiedAlertIds.contains(notifyKey)) {
        _notifiedAlertIds.add(notifyKey);
        _sendSystemNotification(alert.title, alert.description);
      }
    }

    String topAppName = 'لا يوجد';
    int topAppBytes = 0;
    for (final app in _todayApps) {
      if (!app.isSystemApp && app.totalBytes > topAppBytes) {
        topAppBytes = app.totalBytes;
        topAppName = app.appName;
      }
    }

    final double todayUsedMB = todayMobileBytes / (1024 * 1024);
    final double todayRemainingMB =
        (effectiveDailyCap - todayUsedMB).clamp(0.0, effectiveDailyCap);

    final todayLog = DailyHistoryLog(
      dateKey: todayKey,
      mobileBytes: todayMobileBytes,
      wifiBytes: todayWifiBytes,
      topAppName: topAppName,
      topAppBytes: topAppBytes,
      rolledOverMB: todayRemainingMB,
    );

    final updatedLogs = List<DailyHistoryLog>.from(_historyLogs);
    final existingIndex =
        updatedLogs.indexWhere((element) => element.dateKey == todayKey);
    if (existingIndex >= 0) {
      updatedLogs[existingIndex] = todayLog;
    } else {
      updatedLogs.insert(0, todayLog);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'dailyHistoryLogs',
      jsonEncode(updatedLogs.take(60).map((e) => e.toJson()).toList()),
    );

    if (mounted) {
      setState(() {
        _activeAlerts = alerts;
        _historyLogs = updatedLogs;
      });
    }
  }

  /// ترحيل يدوي للرصيد المتبقي اليوم إلى رصيد الغد
  Future<void> _manualRolloverRemainingToday() async {
    final int todayMobileBytes =
        _todayApps.fold(0, (sum, app) => sum + app.totalMobileBytes);
    final double usedMB = todayMobileBytes / (1024 * 1024);
    final double leftoverMB =
        (_dailyMobileCapMB - usedMB).clamp(0.0, _dailyMobileCapMB);

    if (leftoverMB <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رصيد متبقٍ من السقف اليومي الأساسي لترحيله.'),
        ),
      );
      return;
    }

    setState(() {
      _accumulatedRolloverMB += leftoverMB;
    });
    await _saveSettings();
    await _evaluateAlertsBlockingAndRollover();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F766E),
        content: Text(
          'تم ترحيل ${_formatMB(leftoverMB)} بنجاح! إجمالي الرصيد المرحّل المضاف: ${_formatMB(_accumulatedRolloverMB)}',
        ),
      ),
    );
  }

  /// ترحيل وتصدير التقرير الكامل (CSV / Excel) إلى مجلد التنزيلات في الهاتف
  Future<void> _exportUsageReportToCsv() async {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = 'DataUsage_Report_$stamp.csv';

    final buffer = StringBuffer();
    buffer.writeln(
        'اسم التطبيق,الحزمة (Package),تنزيل الهاتف (MB),رفع الهاتف (MB),إجمالي الهاتف (MB),تنزيل الواي فاي (MB),رفع الواي فاي (MB),إجمالي الواي فاي (MB),الإجمالي الكلي (MB),الحد اليومي المخصص (MB),حالة الاتصال');

    for (final app in _currentPeriodApps) {
      final cap = _perAppDailyCapMB[app.packageName] ?? 0.0;
      final isBlocked = _allBlockedPackages.contains(app.packageName);
      String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(2);

      final cleanName = app.appName.replaceAll(',', ' ');
      buffer.writeln(
          '$cleanName,${app.packageName},${mb(app.mobileRxBytes)},${mb(app.mobileTxBytes)},${mb(app.totalMobileBytes)},${mb(app.wifiRxBytes)},${mb(app.wifiTxBytes)},${mb(app.totalWifiBytes)},${mb(app.totalBytes)},${cap > 0 ? cap.toStringAsFixed(0) : "غير محدد"},${isBlocked ? "مقطوع (محظور)" : "مسموح"}');
    }

    buffer.writeln('');
    buffer.writeln(
        'التاريخ,استهلاك الهاتف اليومي (MB),استهلاك الواي فاي اليومي (MB),الأكثر استهلاكاً,الرصيد المتاح للترحيل (MB)');
    for (final log in _historyLogs) {
      String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(2);
      buffer.writeln(
          '${log.dateKey},${mb(log.mobileBytes)},${mb(log.wifiBytes)},${log.topAppName.replaceAll(',', ' ')},${log.rolledOverMB.toStringAsFixed(1)}');
    }

    final csvText = buffer.toString();

    if (_isSimulationMode) {
      await Clipboard.setData(ClipboardData(text: csvText));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF0F766E),
          content: Text(
              'تم نسخ جدول الترحيل (CSV/Excel) إلى الحافظة بنجاح (وضع المحاكاة).'),
        ),
      );
      return;
    }

    try {
      final savedPath = await _channel.invokeMethod<String>(
        'exportReportToDownloads',
        {
          'fileName': fileName,
          'csvContent': csvText,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0F766E),
          content: Text('تم ترحيل وحفظ ملف Excel/CSV في: $savedPath'),
        ),
      );
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: csvText));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ تقرير الترحيل (CSV) إلى الحافظة.'),
        ),
      );
    }
  }

  List<AppUsageRecord> get _filteredAndSortedApps {
    final list = _currentPeriodApps.where((app) {
      if (!_showSystemApps && app.isSystemApp) return false;
      if (app.bytesForFilter(_networkFilter) <= 0) return false;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        return app.appName.toLowerCase().contains(q) ||
            app.packageName.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    list.sort((a, b) {
      switch (_sortOrder) {
        case AppSortOrder.highestTotal:
          return b
              .bytesForFilter(_networkFilter)
              .compareTo(a.bytesForFilter(_networkFilter));
        case AppSortOrder.highestDownload:
          return b
              .rxBytesForFilter(_networkFilter)
              .compareTo(a.rxBytesForFilter(_networkFilter));
        case AppSortOrder.capRatio:
          final capA = _perAppDailyCapMB[a.packageName] ?? 0;
          final capB = _perAppDailyCapMB[b.packageName] ?? 0;
          final ratioA = capA > 0
              ? (a.bytesForFilter(_networkFilter) / (capA * 1024 * 1024))
              : -1.0;
          final ratioB = capB > 0
              ? (b.bytesForFilter(_networkFilter) / (capB * 1024 * 1024))
              : -1.0;
          if (ratioA != ratioB) return ratioB.compareTo(ratioA);
          return b
              .bytesForFilter(_networkFilter)
              .compareTo(a.bytesForFilter(_networkFilter));
        case AppSortOrder.alphabetical:
          return a.appName.compareTo(b.appName);
      }
    });

    return list;
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 ك.ب';
    const double kb = 1024;
    const double mb = kb * 1024;
    const double gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} جيجابايت';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} ميجابايت';
    } else {
      return '${(bytes / kb).toStringAsFixed(0)} كيلوبايت';
    }
  }

  static String _formatMB(double mb) {
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} جيجابايت';
    }
    return '${mb.toStringAsFixed(0)} ميجابايت';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        title: const Text(
          'مراقب وقاطع استهلاك البيانات',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          if (_allBlockedPackages.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_rounded, size: 15),
                  const SizedBox(width: 4),
                  Text(
                    'مقطوع: ${_allBlockedPackages.length}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          IconButton(
            tooltip: 'ترحيل وتصدير إلى Excel/CSV',
            onPressed: _exportUsageReportToCsv,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'تحديث البيانات الآن',
            onPressed: () => _refreshDataUsage(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'خيارات إضافية',
            onSelected: (value) {
              if (value == 'toggle_system') {
                setState(() => _showSystemApps = !_showSystemApps);
              } else if (value == 'toggle_sim') {
                setState(() {
                  _isSimulationMode = !_isSimulationMode;
                });
                _refreshDataUsage();
              } else if (value == 'open_permission') {
                _channel.invokeMethod('openUsageAccessSettings');
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'toggle_system',
                checked: _showSystemApps,
                child: const Text('إظهار تطبيقات النظام'),
              ),
              CheckedPopupMenuItem(
                value: 'toggle_sim',
                checked: _isSimulationMode,
                child: const Text('وضع المحاكاة التجريبي'),
              ),
              const PopupMenuItem(
                value: 'open_permission',
                child: Text('إعدادات صلاحية الاستخدام في الهاتف'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (!_hasPermission && !_isSimulationMode)
              ? _buildPermissionRequiredView()
              : IndexedStack(
                  index: _currentBottomTab,
                  children: [
                    _buildAppsUsageTab(),
                    _buildCapsAndFirewallTab(),
                    _buildRolloverAndHistoryTab(),
                  ],
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentBottomTab,
        onDestinationSelected: (idx) => setState(() => _currentBottomTab = idx),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.apps_rounded),
            label: 'استهلاك التطبيقات',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible:
                  _activeAlerts.isNotEmpty || _allBlockedPackages.isNotEmpty,
              label: Text(
                  '${_activeAlerts.length + _manuallyBlockedApps.length}'),
              child: const Icon(Icons.security_rounded),
            ),
            label: 'القطع والسقف',
          ),
          const NavigationDestination(
            icon: Icon(Icons.sync_alt_rounded),
            label: 'الترحيل والسجل',
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRequiredView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security_update_good_rounded,
                    size: 56,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'مطلوب صلاحية الوصول لبيانات الاستخدام',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'لقراءة استهلاك كل تطبيق فعلياً من الهاتف وقطع الإنترنت تلقائياً عن التطبيقات التي تتجاوز حدها اليومي، يحتاج التطبيق إلى صلاحية "الوصول إلى بيانات الاستخدام" (Usage Access) من إعدادات أندرويد.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF475569),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      _channel.invokeMethod('openUsageAccessSettings');
                    },
                    icon: const Icon(Icons.settings_suggest_rounded),
                    label: const Text('فتح الإعدادات ومنح الصلاحية الآن'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF0F766E),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _isSimulationMode = true);
                      _refreshDataUsage();
                    },
                    icon: const Icon(Icons.preview_rounded),
                    label: const Text('معاينة ببيانات تجريبية (وضع المحاكاة)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// التبويب الأول: قائمة التطبيقات + زر القطع المباشر + السقف اليومي لكل تطبيق
  Widget _buildAppsUsageTab() {
    final int periodMobileRx =
        _currentPeriodApps.fold(0, (s, a) => s + a.mobileRxBytes);
    final int periodMobileTx =
        _currentPeriodApps.fold(0, (s, a) => s + a.mobileTxBytes);
    final int periodWifiRx =
        _currentPeriodApps.fold(0, (s, a) => s + a.wifiRxBytes);
    final int periodWifiTx =
        _currentPeriodApps.fold(0, (s, a) => s + a.wifiTxBytes);

    final int periodMobileTotal = periodMobileRx + periodMobileTx;
    final int periodWifiTotal = periodWifiRx + periodWifiTx;
    final int periodGrandTotal = periodMobileTotal + periodWifiTotal;

    final apps = _filteredAndSortedApps;

    return RefreshIndicator(
      onRefresh: () => _refreshDataUsage(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_activeAlerts.isNotEmpty) ...[
            _buildTopAlertBanner(),
            const SizedBox(height: 12),
          ],

          _buildPeriodSelectorCard(),
          const SizedBox(height: 12),

          _buildSummaryOverviewCard(
            mobileRx: periodMobileRx,
            mobileTx: periodMobileTx,
            wifiRx: periodWifiRx,
            wifiTx: periodWifiTx,
            grandTotal: periodGrandTotal,
          ),
          const SizedBox(height: 12),

          _buildNetworkTypeChips(),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'ابحث عن تطبيق بالاسم...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<AppSortOrder>(
                tooltip: 'ترتيب التطبيقات',
                onSelected: (order) => setState(() => _sortOrder = order),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: AppSortOrder.highestTotal,
                    child: Text('الأعلى استهلاكاً (الإجمالي)'),
                  ),
                  PopupMenuItem(
                    value: AppSortOrder.highestDownload,
                    child: Text('الأعلى تحميلاً (Download)'),
                  ),
                  PopupMenuItem(
                    value: AppSortOrder.capRatio,
                    child: Text('الأقرب لتجاوز الحد اليومي'),
                  ),
                  PopupMenuItem(
                    value: AppSortOrder.alphabetical,
                    child: Text('ترتيب أبجدي'),
                  ),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.sort_rounded, size: 20),
                      SizedBox(width: 4),
                      Text('ترتيب', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'التطبيقات المسجلة (${apps.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Text(
                  'اضغط لتحديد سقف اليوم أو قطع الإنترنت',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          if (apps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'لا توجد تطبيقات مسجلة تطابق الفلتر الحالي.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            ...apps.map((app) => _buildAppUsageCard(app, periodGrandTotal)),
        ],
      ),
    );
  }

  Widget _buildTopAlertBanner() {
    final topAlert = _activeAlerts.first;
    final bgColor = topAlert.isExceeded
        ? const Color(0xFFFEF2F2)
        : const Color(0xFFFFFBEB);
    final borderColor = topAlert.isExceeded
        ? const Color(0xFFFCA5A5)
        : const Color(0xFFFDE68A);
    final iconColor = topAlert.isExceeded
        ? const Color(0xFFDC2626)
        : const Color(0xFFD97706);

    return InkWell(
      onTap: () => setState(() => _currentBottomTab = 1),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(
              topAlert.isBlocked
                  ? Icons.block_rounded
                  : (topAlert.isExceeded
                      ? Icons.warning_amber_rounded
                      : Icons.notifications_active_rounded),
              color: iconColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topAlert.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    topAlert.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
            if (_activeAlerts.length > 1)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '+${_activeAlerts.length - 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: iconColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelectorCard() {
    return SegmentedButton<TimePeriodFilter>(
      segments: const [
        ButtonSegment(
          value: TimePeriodFilter.today,
          icon: Icon(Icons.today_rounded, size: 18),
          label: Text('اليوم (يومي)'),
        ),
        ButtonSegment(
          value: TimePeriodFilter.week,
          icon: Icon(Icons.date_range_rounded, size: 18),
          label: Text('آخر 7 أيام'),
        ),
        ButtonSegment(
          value: TimePeriodFilter.month,
          icon: Icon(Icons.calendar_month_rounded, size: 18),
          label: Text('هذا الشهر'),
        ),
      ],
      selected: {_periodFilter},
      onSelectionChanged: (newSelection) {
        setState(() {
          _periodFilter = newSelection.first;
        });
        _refreshDataUsage();
      },
    );
  }

  Widget _buildSummaryOverviewCard({
    required int mobileRx,
    required int mobileTx,
    required int wifiRx,
    required int wifiTx,
    required int grandTotal,
  }) {
    final int mobileTotal = mobileRx + mobileTx;
    final int wifiTotal = wifiRx + wifiTx;

    final String periodLabel = _periodFilter == TimePeriodFilter.today
        ? 'استهلاك اليوم'
        : (_periodFilter == TimePeriodFilter.week
            ? 'استهلاك آخر 7 أيام'
            : 'استهلاك هذا الشهر');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'إجمالي $periodLabel',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _formatBytes(grandTotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.cell_tower_rounded,
                              size: 18,
                              color: Color(0xFF15803D),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'بيانات الهاتف',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatBytes(mobileTotal),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF14532D),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '⬇ تنزيل: ${_formatBytes(mobileRx)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF166534),
                          ),
                        ),
                        Text(
                          '⬆ رفع: ${_formatBytes(mobileTx)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF166534),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.wifi_rounded,
                              size: 18,
                              color: Color(0xFF1D4ED8),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'الواي فاي (Wi-Fi)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatBytes(wifiTotal),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '⬇ تنزيل: ${_formatBytes(wifiRx)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                        Text(
                          '⬆ رفع: ${_formatBytes(wifiTx)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkTypeChips() {
    return Row(
      children: [
        Expanded(
          child: ChoiceChip(
            label: const Center(child: Text('الكل')),
            selected: _networkFilter == NetworkTypeFilter.all,
            onSelected: (_) =>
                setState(() => _networkFilter = NetworkTypeFilter.all),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            label: const Center(child: Text('بيانات الهاتف')),
            selected: _networkFilter == NetworkTypeFilter.mobile,
            onSelected: (_) =>
                setState(() => _networkFilter = NetworkTypeFilter.mobile),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            label: const Center(child: Text('الواي فاي')),
            selected: _networkFilter == NetworkTypeFilter.wifi,
            onSelected: (_) =>
                setState(() => _networkFilter = NetworkTypeFilter.wifi),
          ),
        ),
      ],
    );
  }

  /// بطاقة التطبيق الواحد مع حالة القطع وشريط الحد اليومي
  Widget _buildAppUsageCard(AppUsageRecord app, int periodGrandTotal) {
    final int displayedTotal = app.bytesForFilter(_networkFilter);
    final int displayedRx = app.rxBytesForFilter(_networkFilter);
    final int displayedTx = app.txBytesForFilter(_networkFilter);

    final AppUsageRecord? todayRecord = _todayApps
        .cast<AppUsageRecord?>()
        .firstWhere((e) => e?.packageName == app.packageName,
            orElse: () => null);

    final int todayAppBytes = todayRecord != null
        ? (_applyAppCapToAllNetworks
            ? todayRecord.totalBytes
            : todayRecord.totalMobileBytes)
        : 0;

    final double? customDailyCapMB = _perAppDailyCapMB[app.packageName];
    final double? capRatio = (customDailyCapMB != null && customDailyCapMB > 0)
        ? (todayAppBytes / (customDailyCapMB * 1024 * 1024))
        : null;

    final double thresholdRatio = _alertThresholdPercent / 100.0;
    final bool isExceeded = capRatio != null && capRatio >= 1.0;
    final bool isApproaching =
        capRatio != null && capRatio >= thresholdRatio && capRatio < 1.0;
    final bool isBlocked = _allBlockedPackages.contains(app.packageName);

    Color statusColor = const Color(0xFF0F766E);
    if (isBlocked || isExceeded) {
      statusColor = const Color(0xFFDC2626);
    } else if (isApproaching) {
      statusColor = const Color(0xFFD97706);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showAppCapDetailsSheet(app),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: app.iconBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                app.iconBytes!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(
                              Icons.android_rounded,
                              color: Color(0xFF0F766E),
                              size: 26,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  app.appName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isBlocked)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626)
                                        .withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.block_rounded,
                                          size: 12, color: Color(0xFFDC2626)),
                                      SizedBox(width: 3),
                                      Text(
                                        'الإنترنت مقطوع',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (isExceeded || isApproaching)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isExceeded
                                        ? 'تجاوز الحد اليومي'
                                        : 'اقترب من الحد',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '⬇ تحميل: ${_formatBytes(displayedRx)}   •   ⬆ رفع: ${_formatBytes(displayedTx)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatBytes(displayedTotal),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: isBlocked
                              ? 'إعادة تشغيل الإنترنت للتطبيق'
                              : 'قطع الإنترنت عن هذا التطبيق الآن',
                          onPressed: () async {
                            setState(() {
                              if (_manuallyBlockedApps
                                  .contains(app.packageName)) {
                                _manuallyBlockedApps.remove(app.packageName);
                                _autoBlockedApps.remove(app.packageName);
                              } else {
                                _manuallyBlockedApps.add(app.packageName);
                              }
                            });
                            await _saveSettings();
                            await _syncFirewallBlockedApps();
                          },
                          icon: Icon(
                            isBlocked
                                ? Icons.wifi_off_rounded
                                : Icons.wifi_tethering_rounded,
                            size: 20,
                            color: isBlocked
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF0F766E),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (customDailyCapMB != null && customDailyCapMB > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'الاستهلاك اليومي: ${_formatBytes(todayAppBytes)} من ${_formatMB(customDailyCapMB)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                      Text(
                        '${((capRatio ?? 0) * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (capRatio ?? 0).clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// نافذة تفاصيل التطبيق وتحديد كم يستخدم من الإنترنت باليوم + زر القطع الفوري
  void _showAppCapDetailsSheet(AppUsageRecord app) {
    final AppUsageRecord? todayRecord = _todayApps
        .cast<AppUsageRecord?>()
        .firstWhere((e) => e?.packageName == app.packageName,
            orElse: () => null);
    final AppUsageRecord? monthRecord = _monthApps
        .cast<AppUsageRecord?>()
        .firstWhere((e) => e?.packageName == app.packageName,
            orElse: () => null);

    final double currentCap = _perAppDailyCapMB[app.packageName] ?? 0.0;
    final TextEditingController controller = TextEditingController(
      text: currentCap > 0 ? currentCap.toStringAsFixed(0) : '',
    );
    final bool isCurrentlyBlocked =
        _allBlockedPackages.contains(app.packageName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              right: 20,
              left: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.data_usage_rounded,
                      color: Color(0xFF0F766E),
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.appName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            app.packageName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        setState(() {
                          if (isCurrentlyBlocked) {
                            _manuallyBlockedApps.remove(app.packageName);
                            _autoBlockedApps.remove(app.packageName);
                          } else {
                            _manuallyBlockedApps.add(app.packageName);
                          }
                        });
                        await _saveSettings();
                        await _syncFirewallBlockedApps();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: Icon(
                        isCurrentlyBlocked
                            ? Icons.lock_open_rounded
                            : Icons.block_rounded,
                        size: 18,
                        color: isCurrentlyBlocked
                            ? const Color(0xFF15803D)
                            : const Color(0xFFDC2626),
                      ),
                      label: Text(
                        isCurrentlyBlocked ? 'إعادة الإنترنت' : 'قطع الإنترنت',
                        style: TextStyle(
                          color: isCurrentlyBlocked
                              ? const Color(0xFF15803D)
                              : const Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatBox(
                        label: 'استهلاك اليوم (هاتف)',
                        value: _formatBytes(todayRecord?.totalMobileBytes ?? 0),
                        sub:
                            '⬇ ${_formatBytes(todayRecord?.mobileRxBytes ?? 0)}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatBox(
                        label: 'استهلاك اليوم (واي فاي)',
                        value: _formatBytes(todayRecord?.totalWifiBytes ?? 0),
                        sub: '⬇ ${_formatBytes(todayRecord?.wifiRxBytes ?? 0)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatBox(
                        label: 'استهلاك الشهر (هاتف)',
                        value: _formatBytes(monthRecord?.totalMobileBytes ?? 0),
                        sub:
                            '⬇ ${_formatBytes(monthRecord?.mobileRxBytes ?? 0)}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatBox(
                        label: 'استهلاك الشهر (واي فاي)',
                        value: _formatBytes(monthRecord?.totalWifiBytes ?? 0),
                        sub: '⬇ ${_formatBytes(monthRecord?.wifiRxBytes ?? 0)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'تحديد الحد اليومي المسموح لهذا التطبيق (سيتم تنبيهك وقطع الإنترنت عنه تلقائياً عند التجاوز):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'مثال: 150 (اتركه فارغاً لإلغاء الحد)',
                    suffixText: 'ميجابايت / يوم',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [50, 100, 200, 500, 1024].map((preset) {
                    return ActionChip(
                      label: Text('$preset م.ب'),
                      onPressed: () {
                        controller.text = preset.toString();
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          final val = double.tryParse(controller.text.trim());
                          setState(() {
                            if (val != null && val > 0) {
                              _perAppDailyCapMB[app.packageName] = val;
                            } else {
                              _perAppDailyCapMB.remove(app.packageName);
                            }
                          });
                          _saveSettings();
                          _evaluateAlertsBlockingAndRollover();
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('حفظ الحد اليومي للتطبيق'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (_perAppDailyCapMB.containsKey(app.packageName)) ...[
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'حذف الحد المخصص',
                        onPressed: () {
                          setState(() {
                            _perAppDailyCapMB.remove(app.packageName);
                          });
                          _saveSettings();
                          _evaluateAlertsBlockingAndRollover();
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatBox({
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Text(
            sub,
            style: const TextStyle(fontSize: 11, color: Color(0xFF0F766E)),
          ),
        ],
      ),
    );
  }

  /// التبويب الثاني: جدار الحماية (قطع الإنترنت) + إدارة السقف اليومي والشهري
  Widget _buildCapsAndFirewallTab() {
    final int todayMobileBytes =
        _todayApps.fold(0, (s, a) => s + a.totalMobileBytes);
    final int monthMobileBytes =
        _monthApps.fold(0, (s, a) => s + a.totalMobileBytes);
    final int todayWifiBytes =
        _todayApps.fold(0, (s, a) => s + a.totalWifiBytes);
    final int monthWifiBytes =
        _monthApps.fold(0, (s, a) => s + a.totalWifiBytes);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // بطاقة التحكم في جدار الحماية وقطع الإنترنت (Firewall VPN)
        Card(
          color: _allBlockedPackages.isNotEmpty
              ? const Color(0xFFFEF2F2)
              : const Color(0xFFF0FDF4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _allBlockedPackages.isNotEmpty
                          ? Icons.gpp_bad_rounded
                          : Icons.verified_user_rounded,
                      color: _allBlockedPackages.isNotEmpty
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF15803D),
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _allBlockedPackages.isNotEmpty
                                ? 'جدار قطع الإنترنت نشط (${_allBlockedPackages.length} تطبيقات مقطوعة)'
                                : 'جدار الحماية جاهز (لا توجد تطبيقات مقطوعة حالياً)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const Text(
                            'يستخدم خدمة VPN محلية لعزل التطبيقات المتجاوزة فقط دون إبطاء باقي الهاتف.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'القطع التلقائي للإنترنت عند تجاوز الحد اليومي للتطبيق',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'عند وصول أي تطبيق إلى 100% من سقفه اليومي المخصص يتم قطع الإنترنت عنه فوراً',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _autoBlockExceededApps,
                  onChanged: (val) async {
                    setState(() => _autoBlockExceededApps = val);
                    await _saveSettings();
                    await _evaluateAlertsBlockingAndRollover();
                  },
                ),
                if (_allBlockedPackages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        setState(() {
                          _manuallyBlockedApps.clear();
                          _autoBlockedApps.clear();
                          _autoBlockExceededApps = false;
                        });
                        await _saveSettings();
                        await _syncFirewallBlockedApps();
                      },
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('فك الحظر عن جميع التطبيقات الآن'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'التنبيهات النشطة حالياً',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (_activeAlerts.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF15803D),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'جميع التطبيقات واستهلاك الشبكة ضمن الحدود الآمنة المحددة.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF334155)),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._activeAlerts.map((alert) {
            final color = alert.isExceeded
                ? const Color(0xFFDC2626)
                : const Color(0xFFD97706);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.12),
                    child: Icon(
                      alert.isBlocked
                          ? Icons.block_rounded
                          : (alert.isExceeded
                              ? Icons.error_outline_rounded
                              : Icons.warning_amber_rounded),
                      color: color,
                    ),
                  ),
                  title: Text(
                    alert.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                  subtitle: Text(
                    alert.description,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: 20),
        const Text(
          'إعدادات السقف اليومي والشهري للإنترنت',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),

        _buildCapConfigCard(
          title: 'سقف بيانات الهاتف (Mobile Data)',
          icon: Icons.cell_tower_rounded,
          color: const Color(0xFF15803D),
          todayUsedBytes: todayMobileBytes,
          dailyCapMB: _effectiveDailyMobileCapMB,
          monthUsedBytes: monthMobileBytes,
          monthlyCapMB: _monthlyMobileCapMB,
          onEditCaps: () => _showEditGlobalCapsDialog(isMobile: true),
        ),
        const SizedBox(height: 12),

        _buildCapConfigCard(
          title: 'سقف شبكة الواي فاي (Wi-Fi)',
          icon: Icons.wifi_rounded,
          color: const Color(0xFF1D4ED8),
          todayUsedBytes: todayWifiBytes,
          dailyCapMB: _dailyWifiCapMB,
          monthUsedBytes: monthWifiBytes,
          monthlyCapMB: _monthlyWifiCapMB,
          onEditCaps: () => _showEditGlobalCapsDialog(isMobile: false),
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'نسبة التنبيه المبكر قبل تجاوز السقف',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${_alertThresholdPercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _alertThresholdPercent,
                  min: 50,
                  max: 95,
                  divisions: 9,
                  label: '${_alertThresholdPercent.toStringAsFixed(0)}%',
                  onChanged: (val) {
                    setState(() => _alertThresholdPercent = val);
                  },
                  onChangeEnd: (_) {
                    _saveSettings();
                    _evaluateAlertsBlockingAndRollover();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'حساب الحد اليومي للتطبيقات على (الهاتف + الواي فاي معاً)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  value: _applyAppCapToAllNetworks,
                  onChanged: (val) {
                    setState(() => _applyAppCapToAllNetworks = val);
                    _saveSettings();
                    _evaluateAlertsBlockingAndRollover();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCapConfigCard({
    required String title,
    required IconData icon,
    required Color color,
    required int todayUsedBytes,
    required double dailyCapMB,
    required int monthUsedBytes,
    required double monthlyCapMB,
    required VoidCallback onEditCaps,
  }) {
    final double dailyRatio = dailyCapMB > 0
        ? (todayUsedBytes / (dailyCapMB * 1024 * 1024)).clamp(0.0, 1.0)
        : 0.0;
    final double monthlyRatio = monthlyCapMB > 0
        ? (monthUsedBytes / (monthlyCapMB * 1024 * 1024)).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: onEditCaps,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('تعديل السقف'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الاستهلاك اليومي: ${_formatBytes(todayUsedBytes)}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'السقف اليومي المتاح: ${_formatMB(dailyCapMB)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: dailyRatio,
                minHeight: 8,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الاستهلاك الشهري: ${_formatBytes(monthUsedBytes)}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'السقف الشهري: ${_formatMB(monthlyCapMB)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: monthlyRatio,
                minHeight: 8,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditGlobalCapsDialog({required bool isMobile}) {
    final dailyCtrl = TextEditingController(
      text: (isMobile ? _dailyMobileCapMB : _dailyWifiCapMB).toStringAsFixed(0),
    );
    final monthlyCtrl = TextEditingController(
      text: (isMobile ? _monthlyMobileCapMB : _monthlyWifiCapMB)
          .toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              isMobile
                  ? 'تحديد سقف بيانات الهاتف'
                  : 'تحديد سقف الواي فاي (Wi-Fi)',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dailyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'السقف اليومي الأساسي (بالميجابايت MB)',
                    suffixText: 'MB',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: monthlyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'السقف الشهري (بالميجابايت MB)',
                    helperText: 'مثال: 10240 يعادل 10 جيجابايت',
                    suffixText: 'MB',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final d = double.tryParse(dailyCtrl.text.trim());
                  final m = double.tryParse(monthlyCtrl.text.trim());
                  setState(() {
                    if (isMobile) {
                      if (d != null && d >= 0) _dailyMobileCapMB = d;
                      if (m != null && m >= 0) _monthlyMobileCapMB = m;
                    } else {
                      if (d != null && d >= 0) _dailyWifiCapMB = d;
                      if (m != null && m >= 0) _monthlyWifiCapMB = m;
                    }
                  });
                  _saveSettings();
                  _evaluateAlertsBlockingAndRollover();
                  Navigator.pop(ctx);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// التبويب الثالث: نظام الترحيل (ترحيل الرصيد المتبقي + ترحيل التقارير Excel/CSV) + السجل اليومي
  Widget _buildRolloverAndHistoryTab() {
    final int todayMobileBytes =
        _todayApps.fold(0, (s, a) => s + a.totalMobileBytes);
    final double usedTodayMB = todayMobileBytes / (1024 * 1024);
    final double remainingTodayMB =
        (_effectiveDailyMobileCapMB - usedTodayMB).clamp(0.0, 999999.0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // بطاقة ترحيل الرصيد المتبقي وتصدير البيانات
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.sync_alt_rounded,
                      color: Color(0xFF0F766E),
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'نظام ترحيل الرصيد وترحيل التقارير',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatBox(
                        label: 'الرصيد الأساسي اليومي',
                        value: _formatMB(_dailyMobileCapMB),
                        sub: 'بيانات الهاتف',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatBox(
                        label: 'الرصيد المرحّل المضاف',
                        value: _formatMB(_accumulatedRolloverMB),
                        sub:
                            'الإجمالي: ${_formatMB(_effectiveDailyMobileCapMB)}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatBox(
                        label: 'المتبقي لترحيله غداً',
                        value: _formatMB(remainingTodayMB),
                        sub: 'قابل للترحيل',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'ترحيل الميجابايت المتبقية تلقائياً إلى اليوم التالي',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'يتم إضافة ما تبقى من سقفك اليومي إلى رصيد اليوم التالي تلقائياً',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _enableDailyRollover,
                  onChanged: (val) async {
                    setState(() => _enableDailyRollover = val);
                    await _saveSettings();
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _manualRolloverRemainingToday,
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('ترحيل المتبقي الآن'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exportUsageReportToCsv,
                        icon: const Icon(Icons.table_view_rounded, size: 18),
                        label: const Text('ترحيل لملف Excel/CSV'),
                      ),
                    ),
                  ],
                ),
                if (_accumulatedRolloverMB > 0) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () async {
                        setState(() => _accumulatedRolloverMB = 0.0);
                        await _saveSettings();
                      },
                      child: const Text(
                        'تصفير الرصيد المرحّل المتراكم',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'سجل الاستهلاك اليومي للتطبيقات',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text(
          'يسجل التطبيق تلقائياً إجمالي استهلاك كل يوم والتطبيق الأكثر استهلاكاً والرصيد المرحّل.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        if (_historyLogs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('لا توجد سجلات محفوظة بعد.')),
          )
        else
          ..._historyLogs.map((log) {
            final int total = log.mobileBytes + log.wifiBytes;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 18,
                                color: Color(0xFF0F766E),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                log.dateKey,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'الإجمالي: ${_formatBytes(total)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'بيانات الهاتف: ${_formatBytes(log.mobileBytes)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF15803D),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'الواي فاي: ${_formatBytes(log.wifiBytes)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1D4ED8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.local_fire_department_rounded,
                                    size: 16,
                                    color: Color(0xFFEA580C),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'الأكثر استهلاكاً: ${log.topAppName} (${_formatBytes(log.topAppBytes)})',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'مرحّل: ${_formatMB(log.rolledOverMB)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF0F766E),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}