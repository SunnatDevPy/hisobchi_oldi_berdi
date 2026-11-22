import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HisobchiApp());
}

class HisobchiApp extends StatefulWidget {
  final HisobchiApiClient? apiOverride;

  const HisobchiApp({super.key, this.apiOverride});

  @override
  State<HisobchiApp> createState() => _HisobchiAppState();
}

class _HisobchiAppState extends State<HisobchiApp> {
  late final HisobchiApiClient _api;
  ThemeMode _themeMode = ThemeMode.system;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? HisobchiApiClient();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.apiOverride == null) {
      await _api.loadSavedSession();
    }
    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hisobchi',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: _themeMode,
      home: _initializing
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _api.isAuthenticated
              ? MainWorkspaceScreen(
                  api: _api,
                  onToggleTheme: _toggleTheme,
                  onLoggedOut: () => setState(() {}),
                )
              : LoginScreen(
                  api: _api,
                  onLoggedIn: () => setState(() {}),
                ),
    );
  }
}

// ============================================================================
// LOGIN SCREEN
// ============================================================================

class LoginScreen extends StatefulWidget {
  final HisobchiApiClient api;
  final VoidCallback onLoggedIn;

  const LoginScreen({
    super.key,
    required this.api,
    required this.onLoggedIn,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _urlCtrl;
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _deviceCtrl =
      TextEditingController(text: 'Android APK');
  bool _loading = false;
  bool _testingUrl = false;
  String? _error;
  String? _urlOkMessage;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.api.baseUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _codeCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingUrl = true;
      _error = null;
      _urlOkMessage = null;
    });
    try {
      final ok = await widget.api.checkHealth(_urlCtrl.text);
      if (mounted) {
        setState(() {
          _urlOkMessage = ok
              ? 'Server bilan aloqa muvaffaqiyatli!'
              : 'Server javob bermadi';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Serverga ulanib bo\'lmadi: $e');
      }
    } finally {
      if (mounted) setState(() => _testingUrl = false);
    }
  }

  Future<void> _submitLogin() async {
    final code = _codeCtrl.text.replaceAll(RegExp(r'\D+'), '');
    if (code.length != 8) {
      setState(() =>
          _error = 'Telegram botdan (/apk) olingan 8 xonali kodni kiriting.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.login(
        serverUrl: _urlCtrl.text,
        code: code,
        deviceName: _deviceCtrl.text,
      );
      if (mounted) widget.onLoggedIn();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand Hero
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTokens.navyDark, AppTokens.navyPrimary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance_wallet_rounded,
                                color: Colors.white, size: 32),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Hisobchi Mobil',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Telegram bot va Nakladnoy guruhi bilan bevosita sinxron ishlovchi rasmiy kassa ilovasi.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Instructions Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Qanday ulanadi?',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _stepRow('1',
                              'Telegramda @hisobchi_my_bot ga kiring va /apk buyrug\'ini yuboring.'),
                          const SizedBox(height: 6),
                          _stepRow('2',
                              'Bot bergan 8 xonali bir martalik kodni quyiga kiriting.'),
                          const SizedBox(height: 6),
                          _stepRow('3',
                              'Nakladnoy qaysi guruhga tushishini botning o\'zida (/apk yoki Sozlamalar) boshqarasiz.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Form Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Server manzili (Domen / HTTPS)',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _urlCtrl,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    hintText: 'https://hisobchi.domen.uz',
                                    prefixIcon: Icon(Icons.dns_rounded),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed:
                                    _testingUrl ? null : _testConnection,
                                child: _testingUrl
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('Tekshirish'),
                              ),
                            ],
                          ),
                          if (_urlOkMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '✅ $_urlOkMessage',
                              style: const TextStyle(
                                color: AppTokens.cashGreen,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          const Text(
                            '8 xonali kirish kodi (/apk)',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _codeCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              fontFeatures: AppTokens.tabularNums,
                            ),
                            decoration: const InputDecoration(
                              hintText: '1234-5678',
                              prefixIcon: Icon(Icons.vpn_key_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Qurilma nomi',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _deviceCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Masalan: Kassir Samsung',
                              prefixIcon: Icon(Icons.phone_android_rounded),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTokens.dangerRedBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppTokens.dangerRed
                                        .withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: AppTokens.dangerRed,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _loading ? null : _submitLogin,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.login_rounded),
                            label: Text(
                                _loading ? 'Ulanmoqda...' : 'Ilovaga kirish'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepRow(String numStr, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTokens.navyPrimary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            numStr,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTokens.navyPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// MAIN 4-TAB WORKSPACE
// ============================================================================

class MainWorkspaceScreen extends StatefulWidget {
  final HisobchiApiClient api;
  final VoidCallback onToggleTheme;
  final VoidCallback onLoggedOut;

  const MainWorkspaceScreen({
    super.key,
    required this.api,
    required this.onToggleTheme,
    required this.onLoggedOut,
  });

  @override
  State<MainWorkspaceScreen> createState() => _MainWorkspaceScreenState();
}

class _MainWorkspaceScreenState extends State<MainWorkspaceScreen> {
  int _tabIndex = 0;
  StatusSummary? _summary;
  List<NakladnoyItem> _allDebts = [];
  bool _loading = true;
  String? _error;
  String _filterMode = 'all'; // all | cash | card | transfer | debt
  String _searchQuery = '';
  bool _showCashHistory = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getStatus(),
        widget.api.getUnpaidDebts(),
      ]);
      if (mounted) {
        setState(() {
          _summary = results[0] as StatusSummary;
          _allDebts = results[1] as List<NakladnoyItem>;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await widget.api.clearSession();
        if (mounted) widget.onLoggedOut();
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Aloqa xatosi: $e';
          _loading = false;
        });
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTokens.dangerRed : AppTokens.navyDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openCashDialog(String sourceType) async {
    final titles = {
      'main': '➕ Pul oldim (Asosiy kirim)',
      'kassa_debt': '🏦 Kassadan qarz oldim',
      'kassa_repay': '↩️ Kassaga qaytardim',
    };
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titles[sourceType] ?? 'Kassa amali',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amtCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFeatures: AppTokens.tabularNums,
              ),
              decoration: const InputDecoration(
                labelText: "Summa (so'm)",
                hintText: 'Masalan: 5 000 000',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Izoh (ixtiyoriy)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Saqlash'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final val = parseUzsInput(amtCtrl.text);
      if (val == null || val <= 0) {
        _showSnack('Summani to\'g\'ri kiriting', isError: true);
        return;
      }
      try {
        await widget.api.addCash(
          amount: val,
          sourceType: sourceType,
          note: noteCtrl.text,
        );
        _showSnack('✅ Kassa amali saqlandi!');
        await _refreshAll();
      } catch (e) {
        _showSnack(e.toString(), isError: true);
      }
    }
  }

  Future<void> _openAddNakladnoySheet() async {
    final grpInfo = _summary?.groupInfo ??
        const GroupInfo(bound: false, title: '', apkPostToGroup: true);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => AddNakladnoySheet(
        api: widget.api,
        groupInfo: grpInfo,
      ),
    );
    if (saved == true) {
      await _refreshAll();
    }
  }

  Future<void> _openNakladnoyDetail(NakladnoyItem item) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => NakladnoyDetailSheet(
        api: widget.api,
        item: item,
      ),
    );
    if (changed == true) {
      await _refreshAll();
    }
  }

  Future<void> _openPayDebtDialog(NakladnoyItem item) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Qarzni to'lash (${item.displayNum})",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '${item.supplierName} — ${formatUzs(item.amount, withCurrency: true)}',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.cashGreen),
                onPressed: () => Navigator.pop(ctx, 'cash'),
                icon: const Icon(Icons.money_rounded),
                label: const Text("💵 Naqd to'landi (kassadan ayriladi)"),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppTokens.cardBlue),
                onPressed: () => Navigator.pop(ctx, 'card'),
                icon: const Icon(Icons.credit_card_rounded),
                label: const Text("💳 Karta orqali (naqddan ayrilmaydi)"),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.transferPurple),
                onPressed: () => Navigator.pop(ctx, 'transfer'),
                icon: const Icon(Icons.account_balance_rounded),
                label: const Text("🏦 Perechesleniya / O'tkazma"),
              ),
            ],
          ),
        ),
      ),
    );

    if (method != null) {
      try {
        await widget.api.payDebt(paymentId: item.id, paymentMethod: method);
        _showSnack("✅ Qarz to'landi va guruh xabari yangilandi!");
        await _refreshAll();
      } catch (e) {
        _showSnack(e.toString(), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final debtCount = _summary?.allUnpaidDebtCount ?? _allDebts.length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTokens.navyPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  size: 20, color: AppTokens.navyPrimary),
            ),
            const SizedBox(width: 10),
            const Text('Hisobchi'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Yangilash',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Mavzu (Kun/Tun)',
            onPressed: widget.onToggleTheme,
            icon: const Icon(Icons.brightness_6_rounded),
          ),
        ],
      ),
      floatingActionButton: _tabIndex <= 1 && widget.api.canWrite
          ? FloatingActionButton.extended(
              onPressed: _openAddNakladnoySheet,
              icon: const Icon(Icons.add_photo_alternate_rounded),
              label: const Text(
                'Nakladnoy',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Asosiy',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: debtCount > 0,
              label: Text('$debtCount'),
              child: const Icon(Icons.push_pin_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: debtCount > 0,
              label: Text('$debtCount'),
              child: const Icon(Icons.push_pin_rounded),
            ),
            label: 'Qarzlar',
          ),
          const NavigationDestination(
            icon: Icon(Icons.table_view_outlined),
            selectedIcon: Icon(Icons.table_view_rounded),
            label: 'Excel',
          ),
          const NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag_rounded),
            label: 'Yopish',
          ),
        ],
      ),
      body: _loading && _summary == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _summary == null
              ? _buildErrorState()
              : IndexedStack(
                  index: _tabIndex,
                  children: [
                    _buildDashboardTab(),
                    _buildDebtsTab(),
                    _buildReportsTab(),
                    _buildCloseDayTab(),
                  ],
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 52, color: AppTokens.dangerRed),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Xatolik',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refreshAll,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Qayta urinish'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 1: DASHBOARD & TODAY'S FEED
  // --------------------------------------------------------------------------

  Widget _buildDashboardTab() {
    final s = _summary!;
    final filtered = s.nakladnoys.where((n) {
      if (_filterMode == 'cash' && (n.isDebt || n.paymentMethod != 'cash')) {
        return false;
      }
      if (_filterMode == 'card' && (n.isDebt || n.paymentMethod != 'card')) {
        return false;
      }
      if (_filterMode == 'transfer' &&
          (n.isDebt || n.paymentMethod != 'transfer')) {
        return false;
      }
      if (_filterMode == 'debt' && !n.isDebt) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return n.supplierName.toLowerCase().contains(q) ||
            n.displayNum.toLowerCase().contains(q) ||
            n.amount.toStringAsFixed(0).contains(q);
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          HeroBalanceCard(
            summary: s,
            onAddCash:
                widget.api.canWrite ? () => _openCashDialog('main') : null,
            onKassaDebt: widget.api.canWrite
                ? () => _openCashDialog('kassa_debt')
                : null,
            onKassaRepay: widget.api.canWrite
                ? () => _openCashDialog('kassa_repay')
                : null,
          ),
          const SizedBox(height: 14),

          // Collapsible Cash Transactions Section
          if (s.cashTransactions.isNotEmpty)
            Card(
              child: Column(
                children: [
                  ListTile(
                    onTap: () =>
                        setState(() => _showCashHistory = !_showCashHistory),
                    leading: const Icon(Icons.paid_outlined,
                        color: AppTokens.cashGreen),
                    title: Text(
                      'Kassa kirim-chiqimlari (${s.cashTransactions.length} ta)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    subtitle: Text(
                      "Kechadan qoldiq: ${formatUzs(s.openingBalance, withCurrency: true)}",
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Icon(_showCashHistory
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded),
                  ),
                  if (_showCashHistory)
                    ...s.cashTransactions.map((tx) {
                      final labels = {
                        'main': '➕ Olingan pul',
                        'kassa_debt': '🏦 Kassadan qarz',
                        'kassa_repay': '↩️ Kassaga qaytarildi',
                      };
                      final isOut = tx.sourceType == 'kassa_repay';
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${labels[tx.sourceType] ?? tx.sourceType} • ${tx.timeHm}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: tx.note.isNotEmpty ? Text(tx.note) : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${isOut ? "-" : "+"}${formatUzs(tx.amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                fontFeatures: AppTokens.tabularNums,
                                color: isOut
                                    ? AppTokens.dangerRed
                                    : AppTokens.cashGreen,
                              ),
                            ),
                            if (widget.api.canWrite)
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                onPressed: () async {
                                  await widget.api.deleteCash(tx.id);
                                  _showSnack("Kassa amali o'chirildi");
                                  await _refreshAll();
                                },
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),

          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Bugungi nakladnoylar (${s.nakladnoys.length} ta)',
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (s.totalKassaDebtOutstanding > 0)
                Text(
                  'Kassa qarz: ${formatUzs(s.totalKassaDebtOutstanding)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.debtAmber,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('all', 'Barchasi (${s.nakladnoys.length})'),
                const SizedBox(width: 6),
                _filterChip('cash', '💵 Naqd'),
                const SizedBox(width: 6),
                _filterChip('card', '💳 Karta'),
                const SizedBox(width: 6),
                _filterChip('transfer', "🏦 O'tkazma"),
                const SizedBox(width: 6),
                _filterChip('debt', '📌 Qarzga'),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Search Box
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            decoration: const InputDecoration(
              hintText: 'Postavshik yoki #raqam bo\'yicha qidirish...',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),

          if (filtered.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 44, color: Theme.of(context).hintColor),
                    const SizedBox(height: 10),
                    const Text(
                      'Hozircha nakladnoylar yo\'q',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Pastdagi '+ Nakladnoy' tugmasini bosib qo'shing.",
                      style: TextStyle(
                          fontSize: 13, color: Theme.of(context).hintColor),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filtered.reversed.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NakladnoyListCard(
                  item: item,
                  onTap: () => _openNakladnoyDetail(item),
                  onQuickPay: item.isDebt && widget.api.canWrite
                      ? () => _openPayDebtDialog(item)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _filterMode == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filterMode = key),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: UNPAID DEBTS
  // --------------------------------------------------------------------------

  Widget _buildDebtsTab() {
    final totalDebt =
        _allDebts.fold<double>(0, (acc, item) => acc + item.amount);
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTokens.debtAmber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: AppTokens.debtAmber.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                const Icon(Icons.push_pin_rounded,
                    color: AppTokens.debtAmber, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "To'lanmagan nakladnoy qarzlari (${_allDebts.length} ta)",
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatUzs(totalDebt, withCurrency: true),
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: AppTokens.debtAmber,
                          fontFeatures: AppTokens.tabularNums,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_allDebts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.verified_rounded,
                        size: 46, color: AppTokens.cashGreen),
                    SizedBox(height: 10),
                    Text(
                      "To'lanmagan nakladnoy qarzlari yo'q!",
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._allDebts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NakladnoyListCard(
                  item: item,
                  onTap: () => _openNakladnoyDetail(item),
                  onQuickPay: widget.api.canWrite
                      ? () => _openPayDebtDialog(item)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 3: EXCEL EXPORTS
  // --------------------------------------------------------------------------

  Future<void> _downloadAndShareExcel({
    required String endpoint,
    required String filename,
    Map<String, String>? query,
  }) async {
    _showSnack('📥 Excel tayyorlanmoqda...');
    try {
      final bytes =
          await widget.api.downloadExcelBytes(endpoint, query: query);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Hisobchi Excel hisobot: $filename',
      );
    } catch (e) {
      _showSnack('Excel yuklashda xatolik: $e', isError: true);
    }
  }

  Widget _buildReportsTab() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final weekAgo = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 6)));
    final monthStart =
        DateFormat('yyyy-MM-01').format(DateTime.now());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Excel hisobotlar va Sverka',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Barcha hisobotlar Telegram botdagi kabi Xulosa, Nakladnoylar, Karta/Perechesleniya va Qarzlar varaqlarini o\'z ichiga oladi.',
          style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 16),
        _reportTile(
          icon: Icons.today_rounded,
          color: AppTokens.cashGreen,
          title: 'Bugungi kunlik hisobot (.xlsx)',
          subtitle: 'Joriy ochiq sessiya: ${_summary?.reportDate ?? today}',
          onTap: () => _downloadAndShareExcel(
            endpoint: '/export/session',
            filename: 'Hisobot_${_summary?.reportDate ?? today}.xlsx',
          ),
        ),
        const SizedBox(height: 10),
        _reportTile(
          icon: Icons.date_range_rounded,
          color: AppTokens.cardBlue,
          title: 'Oxirgi 7 kunlik hisobot (.xlsx)',
          subtitle: '$weekAgo — $today',
          onTap: () => _downloadAndShareExcel(
            endpoint: '/export/range',
            query: {'date_from': weekAgo, 'date_to': today},
            filename: 'Hisobot_7kun_${weekAgo}_$today.xlsx',
          ),
        ),
        const SizedBox(height: 10),
        _reportTile(
          icon: Icons.calendar_month_rounded,
          color: AppTokens.transferPurple,
          title: 'Joriy oy hisoboti (.xlsx)',
          subtitle: '$monthStart — $today',
          onTap: () => _downloadAndShareExcel(
            endpoint: '/export/range',
            query: {'date_from': monthStart, 'date_to': today},
            filename: 'Hisobot_Oy_${monthStart}_$today.xlsx',
          ),
        ),
        const SizedBox(height: 10),
        _reportTile(
          icon: Icons.edit_calendar_rounded,
          color: AppTokens.navyPrimary,
          title: 'Ixtiyoriy sana oralig\'i (.xlsx)',
          subtitle: 'Boshlanish va tugash sanasini tanlash',
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2024, 1, 1),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (picked != null) {
              final d1 = DateFormat('yyyy-MM-dd').format(picked.start);
              final d2 = DateFormat('yyyy-MM-dd').format(picked.end);
              await _downloadAndShareExcel(
                endpoint: '/export/range',
                query: {'date_from': d1, 'date_to': d2},
                filename: 'Hisobot_${d1}_$d2.xlsx',
              );
            }
          },
        ),
        const SizedBox(height: 10),
        _reportTile(
          icon: Icons.apartment_rounded,
          color: AppTokens.debtAmber,
          title: 'Postavshiklar Sverkasi (.xlsx)',
          subtitle: 'Barcha postavshiklar bo\'yicha oylik va umumiy sverka',
          onTap: () => _downloadAndShareExcel(
            endpoint: '/export/sverka',
            filename: 'Sverka_$today.xlsx',
          ),
        ),
      ],
    );
  }

  Widget _reportTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5)),
        trailing: const Icon(Icons.ios_share_rounded),
        onTap: onTap,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 4: DAY CLOSE & ACCOUNT/GROUP SETTINGS
  // --------------------------------------------------------------------------

  Widget _buildCloseDayTab() {
    final s = _summary!;
    return _CloseDaySubView(
      summary: s,
      api: widget.api,
      onClosed: _refreshAll,
      onLoggedOut: widget.onLoggedOut,
      showSnack: _showSnack,
    );
  }
}

class _CloseDaySubView extends StatefulWidget {
  final StatusSummary summary;
  final HisobchiApiClient api;
  final Future<void> Function() onClosed;
  final VoidCallback onLoggedOut;
  final void Function(String, {bool isError}) showSnack;

  const _CloseDaySubView({
    required this.summary,
    required this.api,
    required this.onClosed,
    required this.onLoggedOut,
    required this.showSnack,
  });

  @override
  State<_CloseDaySubView> createState() => _CloseDaySubViewState();
}

class _CloseDaySubViewState extends State<_CloseDaySubView> {
  final TextEditingController _countedCtrl = TextEditingController();
  bool _closing = false;

  @override
  void dispose() {
    _countedCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitCloseDay() async {
    final counted = parseUzsInput(_countedCtrl.text);
    if (counted == null || counted < 0) {
      widget.showSnack("Qo'lda sanalgan haqiqiy pulni kiriting", isError: true);
      return;
    }
    setState(() => _closing = true);
    try {
      final res = await widget.api.closeDay(counted);
      _countedCtrl.clear();
      widget.showSnack(
        "🏁 Kun yakunlandi! Keyingi kunga qoldiq: ${formatUzs(res['next_opening_balance'] as num?, withCurrency: true)}",
      );
      await widget.onClosed();
    } catch (e) {
      widget.showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expected = widget.summary.expectedCash;
    final counted = parseUzsInput(_countedCtrl.text);
    final diff = counted != null ? counted - expected : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.flag_rounded, color: AppTokens.navyPrimary),
                    SizedBox(width: 8),
                    Text(
                      'Kunni yakunlash (Smena yopish)',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTokens.navyPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Qo'lda bo'lishi kerak:",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        formatUzs(expected, withCurrency: true),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          fontFeatures: AppTokens.tabularNums,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _countedCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    fontFeatures: AppTokens.tabularNums,
                  ),
                  decoration: InputDecoration(
                    labelText: "Qo'lda sanalgan haqiqiy pul (so'm)",
                    hintText: formatUzs(expected),
                    prefixIcon: const Icon(Icons.calculate_outlined),
                    suffixIcon: TextButton(
                      onPressed: () {
                        _countedCtrl.text = expected.round().toString();
                        setState(() {});
                      },
                      child: const Text('Teng'),
                    ),
                  ),
                ),
                if (diff != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: diff == 0
                          ? AppTokens.cashGreenBg
                          : (diff > 0
                              ? AppTokens.cardBlueBg
                              : AppTokens.dangerRedBg),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      diff == 0
                          ? "✅ Farq: 0 so'm (Kassa 100% to'g'ri!)"
                          : (diff > 0
                              ? "➕ Ortiqcha: +${formatUzs(diff, withCurrency: true)}"
                              : "⚠️ Kamomad: ${formatUzs(diff, withCurrency: true)}"),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: diff == 0
                            ? AppTokens.cashGreen
                            : (diff > 0
                                ? AppTokens.cardBlue
                                : AppTokens.dangerRed),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      widget.api.canWrite && !_closing ? _submitCloseDay : null,
                  icon: const Icon(Icons.lock_clock_rounded),
                  label: Text(_closing
                      ? 'Yopilmoqda...'
                      : '🏁 Kunni yakunlash va yangi kun ochish'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Telegram Group Connection Info Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.telegram, color: AppTokens.cardBlue, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Telegram guruh va Bot sozlamalari',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow(
                  'Nakladnoy guruhi:',
                  widget.summary.groupInfo.bound
                      ? '✅ ${widget.summary.groupInfo.title}'
                      : '⚠️ Bog\'lanmagan',
                ),
                const SizedBox(height: 6),
                _infoRow(
                  'APK dan guruhga yuborish:',
                  widget.summary.groupInfo.apkPostToGroup
                      ? '✅ Yoqilgan'
                      : '🔕 O\'chirilgan (/apk)',
                ),
                const SizedBox(height: 6),
                _infoRow('Server:', widget.api.baseUrl),
                const SizedBox(height: 6),
                _infoRow('Rol:', widget.api.role.toUpperCase()),
                const Divider(height: 24),
                Text(
                  "💡 Nakladnoylar yuboriladigan guruhni o'zgartirish uchun Telegram botda (@hisobchi_my_bot) /apk yoki ⚙️ Sozlamalar -> 🔗 Guruhlarni sozlash bo'limiga kiring.",
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Theme.of(context).hintColor),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTokens.dangerRed,
                    ),
                    onPressed: () async {
                      await widget.api.logout();
                      widget.onLoggedOut();
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Hisobdan chiqish'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String val) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13.5, color: Colors.grey)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            val,
            textAlign: TextAlign.end,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// ADD NAKLADNOY SHEET (Supplier Picker + Quick Amounts + 4 Payment Modes + Photo)
// ============================================================================

class AddNakladnoySheet extends StatefulWidget {
  final HisobchiApiClient api;
  final GroupInfo groupInfo;

  const AddNakladnoySheet({
    super.key,
    required this.api,
    required this.groupInfo,
  });

  @override
  State<AddNakladnoySheet> createState() => _AddNakladnoySheetState();
}

class _AddNakladnoySheetState extends State<AddNakladnoySheet> {
  final TextEditingController _supCtrl = TextEditingController();
  final TextEditingController _amtCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  List<String> _allSuppliers = [];
  List<double> _recentAmounts = [];
  String _paymentMode = 'cash'; // cash | card | transfer | debt
  bool _sendToGroup = true;
  File? _photoFile;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sendToGroup =
        widget.groupInfo.bound && widget.groupInfo.apkPostToGroup;
    _loadSuppliers();
  }

  @override
  void dispose() {
    _supCtrl.dispose();
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final list = await widget.api.getSuppliers();
      if (mounted) setState(() => _allSuppliers = list);
    } catch (_) {}
  }

  Future<void> _selectSupplier(String name) async {
    _supCtrl.text = name;
    setState(() {});
    try {
      final amts = await widget.api.getSupplierAmounts(name);
      if (mounted) setState(() => _recentAmounts = amts);
    } catch (_) {}
  }

  void _adjustAmount(double delta) {
    final cur = parseUzsInput(_amtCtrl.text) ?? 0;
    final next = (cur + delta).clamp(0, 999999999999).toDouble();
    _amtCtrl.text = next > 0 ? next.round().toString() : '';
    setState(() {});
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (xfile != null && mounted) {
        setState(() => _photoFile = File(xfile.path));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Rasm tanlashda xatolik: $e');
      }
    }
  }

  Future<void> _submit() async {
    final sup = _supCtrl.text.trim();
    final amt = parseUzsInput(_amtCtrl.text);
    if (sup.isEmpty) {
      setState(() => _error = 'Postavshik nomini tanlang yoki yozing');
      return;
    }
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Summani kiriting');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.api.createNakladnoy(
        supplierName: sup,
        amount: amt,
        paymentMode: _paymentMode,
        note: _noteCtrl.text,
        sendToGroup: _sendToGroup,
        photoFile: _photoFile,
      );
      if (mounted) {
        final grpMsg = res['group_message']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Nakladnoy saqlandi! ($grpMsg)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _supCtrl.text.trim().toLowerCase();
    final matchingSuppliers = _allSuppliers
        .where((s) => q.isEmpty || s.toLowerCase().contains(q))
        .take(18)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '➕ Yangi Nakladnoy qo\'shish',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),

            // 1. Supplier field + inline supplier chips
            TextField(
              controller: _supCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '🏢 Postavshik nomi',
                hintText: 'Tanlang yoki yangi nom yozing...',
                prefixIcon: const Icon(Icons.storefront_rounded),
                suffixIcon: _supCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _supCtrl.clear();
                          setState(() => _recentAmounts = []);
                        },
                      )
                    : null,
              ),
            ),
            if (matchingSuppliers.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: matchingSuppliers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final name = matchingSuppliers[i];
                    final isSel =
                        name.toLowerCase() == _supCtrl.text.trim().toLowerCase();
                    return ActionChip(
                      backgroundColor: isSel
                          ? AppTokens.navyPrimary.withValues(alpha: 0.16)
                          : null,
                      label: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              isSel ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      onPressed: () => _selectSupplier(name),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),

            // 2. Amount field + recent amounts + quick +/- chips
            TextField(
              controller: _amtCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFeatures: AppTokens.tabularNums,
              ),
              decoration: InputDecoration(
                labelText: "💰 Summa (so'm)",
                hintText: 'Masalan: 1 554 000',
                prefixIcon: const Icon(Icons.payments_outlined),
                helperText: parseUzsInput(_amtCtrl.text) != null
                    ? formatUzs(parseUzsInput(_amtCtrl.text),
                        withCurrency: true)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._recentAmounts.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.history_rounded, size: 15),
                        label: Text(formatUzs(a)),
                        onPressed: () {
                          _amtCtrl.text = a.round().toString();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  ActionChip(
                    label: const Text('-10 000'),
                    onPressed: () => _adjustAmount(-10000),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('+10 000'),
                    onPressed: () => _adjustAmount(10000),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('+100 000'),
                    onPressed: () => _adjustAmount(100000),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 3. Payment mode selector (Naqd | Karta | O'tkazma | Qarzga)
            const Text(
              "To'lov usuli",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            PaymentModeSelector(
              selectedMode: _paymentMode,
              onChanged: (m) => setState(() => _paymentMode = m),
            ),
            const SizedBox(height: 14),

            // 4. Camera / Gallery Photo Attachment
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: const Text('Kamera'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Galereya'),
                  ),
                ),
              ],
            ),
            if (_photoFile != null) ...[
              const SizedBox(height: 10),
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _photoFile!,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton.filled(
                      onPressed: () => setState(() => _photoFile = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            // 5. Note & Group Send Switch
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Izoh (ixtiyoriy)',
                prefixIcon: Icon(Icons.notes_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '📤 Telegram guruhga yuborish',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Text(
                widget.groupInfo.bound
                    ? 'Guruh: ${widget.groupInfo.title}'
                    : 'Hozircha guruh bog\'lanmagan (faqat bazaga tushadi)',
                style: const TextStyle(fontSize: 12),
              ),
              value: _sendToGroup,
              onChanged: widget.groupInfo.bound
                  ? (v) => setState(() => _sendToGroup = v)
                  : null,
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                '⚠️ $_error',
                style: const TextStyle(
                  color: AppTokens.dangerRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(
                  _submitting ? 'Yuborilmoqda...' : 'Tasdiqlash va saqlash'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// NAKLADNOY DETAIL & EDIT SHEET (Direct Amount + Quick +/- + Inline Suppliers)
// ============================================================================

class NakladnoyDetailSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final NakladnoyItem item;

  const NakladnoyDetailSheet({
    super.key,
    required this.api,
    required this.item,
  });

  @override
  State<NakladnoyDetailSheet> createState() => _NakladnoyDetailSheetState();
}

class _NakladnoyDetailSheetState extends State<NakladnoyDetailSheet> {
  late NakladnoyItem _cur;
  late TextEditingController _supCtrl;
  late TextEditingController _amtCtrl;
  List<String> _suppliers = [];
  bool _showSupplierPicker = false;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _cur = widget.item;
    _supCtrl = TextEditingController(text: _cur.supplierName);
    _amtCtrl = TextEditingController(text: _cur.amount.round().toString());
    _loadSuppliers();
  }

  @override
  void dispose() {
    _supCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final s = await widget.api.getSuppliers();
      if (mounted) setState(() => _suppliers = s);
    } catch (_) {}
  }

  Future<void> _applyUpdate({
    String? supplier,
    double? amount,
    bool roundAmount = false,
  }) async {
    setState(() => _busy = true);
    try {
      final updated = await widget.api.updateNakladnoy(
        paymentId: _cur.id,
        supplierName: supplier,
        amount: amount,
        roundAmount: roundAmount,
      );
      if (mounted) {
        setState(() {
          _cur = updated;
          _supCtrl.text = updated.supplierName;
          _amtCtrl.text = updated.amount.round().toString();
          _changed = true;
          _showSupplierPicker = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchMethod(String mode) async {
    setState(() => _busy = true);
    try {
      NakladnoyItem updated;
      if (mode == 'debt') {
        updated = await widget.api.markAsDebt(_cur.id);
      } else if (_cur.isDebt) {
        updated = await widget.api
            .payDebt(paymentId: _cur.id, paymentMethod: mode);
      } else {
        updated = await widget.api
            .setPaymentMethod(paymentId: _cur.id, paymentMethod: mode);
      }
      if (mounted) {
        setState(() {
          _cur = updated;
          _changed = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMode = _cur.isDebt ? 'debt' : _cur.paymentMethod;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Nakladnoy ${_cur.displayNum}',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _changed),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Photo Preview if available
              if (_cur.hasPhoto) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    widget.api.photoUrlFor(_cur.id),
                    height: 190,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Supplier section with inline supplier chips picker
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _supCtrl,
                      decoration: const InputDecoration(
                        labelText: '🏢 Postavshik',
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          _applyUpdate(supplier: v.trim());
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(
                        () => _showSupplierPicker = !_showSupplierPicker),
                    icon: const Icon(Icons.list_rounded, size: 18),
                    label: const Text('Ro\'yxat'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_supCtrl.text.trim().isNotEmpty) {
                              _applyUpdate(supplier: _supCtrl.text.trim());
                            }
                          },
                    child: const Text('Saqlash'),
                  ),
                ],
              ),
              if (_showSupplierPicker && _suppliers.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 170),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _suppliers
                          .map(
                            (s) => ActionChip(
                              label: Text(s,
                                  style: const TextStyle(fontSize: 12.5)),
                              onPressed: () => _applyUpdate(supplier: s),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Direct amount editing + quick +/- buttons + Yaxlitlash (matching bot UX!)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amtCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        fontFeatures: AppTokens.tabularNums,
                      ),
                      decoration: const InputDecoration(
                        labelText: "💰 Summa (so'm) — qo'lda yozing",
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        final parsed = parseUzsInput(v);
                        if (parsed != null && parsed > 0) {
                          _applyUpdate(amount: parsed);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            final parsed = parseUzsInput(_amtCtrl.text);
                            if (parsed != null && parsed > 0) {
                              _applyUpdate(amount: parsed);
                            }
                          },
                    child: const Text('Yangilash'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('−10 000'),
                    onPressed: _busy
                        ? null
                        : () => _applyUpdate(
                            amount: (_cur.amount - 10000).clamp(1000, 1e12)),
                  ),
                  ActionChip(
                    label: const Text('−1 000'),
                    onPressed: _busy
                        ? null
                        : () => _applyUpdate(
                            amount: (_cur.amount - 1000).clamp(1000, 1e12)),
                  ),
                  ActionChip(
                    label: const Text('+1 000'),
                    onPressed:
                        _busy ? null : () => _applyUpdate(amount: _cur.amount + 1000),
                  ),
                  ActionChip(
                    label: const Text('+10 000'),
                    onPressed: _busy
                        ? null
                        : () => _applyUpdate(amount: _cur.amount + 10000),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.auto_fix_high_rounded, size: 15),
                    label: const Text('🔄 Yaxlitlash'),
                    onPressed:
                        _busy ? null : () => _applyUpdate(roundAmount: true),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Payment method & Debt switch
              const Text(
                "To'lov turi va holati:",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const SizedBox(height: 8),
              PaymentModeSelector(
                selectedMode: activeMode,
                onChanged: (m) {
                  if (!_busy && m != activeMode) {
                    _switchMethod(m);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Group sync / delete actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              try {
                                final msg = await widget.api
                                    .sendNakladnoyToGroup(_cur.id);
                                _changed = true;
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('📤 $msg')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: Text(_cur.inGroup
                          ? 'Guruhda yangilash'
                          : 'Guruhga yuborish'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.dangerRed),
                    onPressed: _busy
                        ? null
                        : () async {
                            await widget.api.deleteNakladnoy(_cur.id);
                            if (context.mounted) {
                              Navigator.pop(context, true);
                            }
                          },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text("O'chirish"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
