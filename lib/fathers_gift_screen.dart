import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_host_card_emulation/nfc_host_card_emulation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:app_settings/app_settings.dart';

import 'theme_colors.dart';
import 'login_screen.dart';
import 'services/api_service.dart';

// Distinct NFC states for fine-grained UI feedback
enum _NfcDisplayState {
  loading,          // still checking
  active,           // NFC on and HCE running
  disabled,         // hardware exists but NFC is OFF in settings
  notSupported,     // device has no NFC chip
  hceError,         // NFC on but HCE init failed
  iosNotSupported,  // iPhone — HCE not available on iOS
}

class FathersGiftScreen extends StatefulWidget {
  const FathersGiftScreen({super.key});

  @override
  State<FathersGiftScreen> createState() => _FathersGiftScreenState();
}

class _FathersGiftScreenState extends State<FathersGiftScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ApiService _apiService = ApiService();

  String studentName = 'Loading...';
  String walletNfc = '...';
  String nfcStatus = 'Initializing...';
  bool _showSuccessIcon = false;
  List<dynamic> _transactions = [];
  bool _balanceVisible = false;
  bool _isLoading = true;

  double actualBalance = 0.00;
  bool _isActive = true;
  String userBalance = '0.00';

  _NfcDisplayState _nfcState = _NfcDisplayState.loading;
  bool get _nfcAvailable => _nfcState == _NfcDisplayState.active;

  // Card Flip State and Animation Controllers
  bool _isCardFlipped = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController);

    _loadUserData();
    _fetchData();
    _initNfcHce();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NfcHce.removeApduResponse(0);
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-verify NFC state whenever user returns to the app
      _initNfcHce();
    }
  }

  void _flipCard() {
    setState(() {
      _isCardFlipped = !_isCardFlipped;
    });

    if (_isCardFlipped) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  Future<void> _fetchData() async {
    try {
      if (mounted) setState(() { _isLoading = true; });
      
      // Fetch Balance and Transactions concurrently
      final balanceFuture = _apiService.getBalance();
      final transactionsFuture = _apiService.getTransactions();

      final results = await Future.wait([balanceFuture, transactionsFuture]);
      final balanceData = results[0];
      final transactionsData = results[1];

      if (mounted) {
        setState(() {
          actualBalance = (balanceData['balance'] as num?)?.toDouble() ?? 0.0;
          userBalance = _balanceVisible ? actualBalance.toStringAsFixed(2) : '******';
          
          if (balanceData['is_active'] != null) {
            _isActive = balanceData['is_active'];
          }
          if (balanceData['student_name'] != null) {
            studentName = balanceData['student_name'].toString().toUpperCase();
          }

          // Ensure it's a list
          if (transactionsData['transactions'] is List) {
            _transactions = transactionsData['transactions'];
          } else {
            _transactions = [];
          }

          // Sort if needed based on the new `date` field
          try {
            _transactions.sort((a, b) => b['date'].compareTo(a['date']));
          } catch (_) {
            // Keep original order if field is missing
          }
        });
      }
    } catch (e) {
      print('Error fetching data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data. Error: ${e.toString().split(':').last.trim()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      studentName = prefs.getString('userName')?.toUpperCase() ?? 'Student Name';
      walletNfc = prefs.getString('walletNfc') ?? '000000';
    });
    _updateNfcData(walletNfc);
  }

  Future<void> _initNfcHce() async {
    // iOS does NOT support Host Card Emulation — only Apple Pay can emulate cards
    if (Platform.isIOS) {
      if (mounted) setState(() {
        nfcStatus = 'NFC tap-to-pay is not available on iPhone';
        _nfcState = _NfcDisplayState.iosNotSupported;
      });
      return;
    }

    try {
      // Use our own native MethodChannel for a FRESH NFC adapter check
      // (the plugin's check caches the adapter and returns stale values on some OEMs)
      const nfcChannel = MethodChannel('nfc_check');
      final String state = await nfcChannel.invokeMethod('getNfcState');

      switch (state) {
        case 'enabled':
          try {
            await NfcHce.init(
              aid: Uint8List.fromList([0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]),
              permanentApduResponses: true,
              listenOnlyConfiguredPorts: false,
            );
            if (mounted) setState(() {
              nfcStatus = '';
              _nfcState = _NfcDisplayState.active;
            });
            NfcHce.stream.listen((command) {
              _showSuccessFeedback();
            });
          } catch (e) {
            if (mounted) setState(() {
              nfcStatus = 'HCE init error: $e';
              _nfcState = _NfcDisplayState.hceError;
            });
          }
          break;

        case 'disabled':
          if (mounted) setState(() {
            nfcStatus = 'NFC is turned off';
            _nfcState = _NfcDisplayState.disabled;
          });
          break;

        default: // 'notSupported' or anything unexpected
          if (mounted) setState(() {
            nfcStatus = 'NFC not supported';
            _nfcState = _NfcDisplayState.notSupported;
          });
          break;
      }
    } catch (e) {
      if (mounted) setState(() {
        nfcStatus = 'NFC check failed: $e';
        _nfcState = _NfcDisplayState.notSupported;
      });
    }
  }

  void _showSuccessFeedback() {
    if (mounted) {
      setState(() {
        nfcStatus = 'Paid Successfully!';
        _showSuccessIcon = true;
      });

      // Auto-refresh data after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        _fetchData();
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            nfcStatus = 'Ready to Tap';
            _showSuccessIcon = false;
          });
        }
      });
    }
  }

  Future<void> _updateNfcData(String data) async {
    String message = "User:$data";
    List<int> response = message.codeUnits;
    await NfcHce.addApduResponse(0, response);
  }

  void _toggleBalanceVisibility() {
    setState(() {
      _balanceVisible = !_balanceVisible;
      userBalance = _balanceVisible ? actualBalance.toStringAsFixed(2) : '******';
    });
  }

  void _logout() async {
    await _apiService.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_logged_in');
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("SALCF Gift", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primaryBlue,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
            tooltip: 'Logout',
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _flipCard,
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      final angle = _animation.value * 3.14159;
                      final isFront = angle < 3.14159 / 2;
                      return Transform(
                        transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle),
                        alignment: Alignment.center,
                        child: isFront
                            ? _buildVirtualCard(isFront: true)
                            : Transform(transform: Matrix4.identity()..rotateY(3.14159), alignment: Alignment.center, child: _buildVirtualCard(isFront: false)),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                _buildNfcStatusWidget(),

                _isLoading ? const CircularProgressIndicator() : _buildBalanceCard(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Recent Transactions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ),
          _transactions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 50, bottom: 50),
                  child: _buildEmptyState(),
                )
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _transactions.length,
            itemBuilder: (context, index) {
              return InkWell(
                onTap: () => _showTransactionDetails(_transactions[index]),
                borderRadius: BorderRadius.circular(15),
                child: _buildTransactionItem(_transactions[index]),
              );
            },
          ),
        ],
      ),
    ),
  );
}

  Widget _buildNfcStatusWidget() {
    switch (_nfcState) {
      case _NfcDisplayState.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text("Checking NFC...", style: TextStyle(color: Colors.grey)),
            ],
          ),
        );

      case _NfcDisplayState.active:
        return Column(
          children: [
            if (nfcStatus.isNotEmpty)
              Text(
                nfcStatus,
                style: TextStyle(
                  color: nfcStatus == "Paid Successfully!" ? Colors.green : AppColors.primaryBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 10),
            const Icon(Icons.contactless, size: 48, color: AppColors.primaryBlue),
            const SizedBox(height: 8),
            const Text("Hold near reader to pay",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
          ],
        );

      case _NfcDisplayState.disabled:
        // NFC hardware exists but is turned OFF in device settings
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              const Icon(Icons.nfc, size: 42, color: Colors.orange),
              const SizedBox(height: 10),
              const Text(
                "NFC is turned off on your device.\nPlease enable it to use tap-to-pay.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.nfc),
                icon: const Icon(Icons.settings),
                label: const Text("Open NFC Settings"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );

      case _NfcDisplayState.hceError:
        // NFC is on, but HCE (Host Card Emulation) failed to initialise
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              Icon(Icons.warning_amber_rounded, size: 42, color: Colors.red),
              SizedBox(height: 8),
              Text(
                "NFC is on but card emulation failed to start.\nPlease use the provided physical card.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.5),
              ),
              SizedBox(height: 10),
            ],
          ),
        );

      case _NfcDisplayState.notSupported:
        // No NFC hardware on this device
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              Icon(Icons.nfc, size: 42, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                "This device does not support NFC.\nPlease use the provided physical card.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.5),
              ),
              SizedBox(height: 10),
            ],
          ),
        );

      case _NfcDisplayState.iosNotSupported:
      default:
        // iPhone — Apple does not allow third-party HCE
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              Icon(Icons.phone_iphone, size: 42, color: AppColors.primaryBlue),
              SizedBox(height: 8),
              Text(
                "NFC tap-to-pay is not available on iPhone.\nPlease use the physical card assigned to you for payments.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.5),
              ),
              SizedBox(height: 10),
            ],
          ),
        );
    }
  }

  void _showTransactionDetails(Map<String, dynamic> transaction) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Transaction Details",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),
              
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Reference", style: TextStyle(color: Colors.grey)),
                    Text(transaction['reference'] ?? "N/A", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Status", style: TextStyle(color: Colors.grey)),
                    Text((transaction['state']?.toString().toUpperCase() ?? "UNKNOWN"), 
                         style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Wallet", style: TextStyle(color: Colors.grey)),
                    Text(transaction['wallet'] ?? "N/A", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              const Divider(thickness: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Amount", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                      "AED ${(transaction['amount'] ?? 0).toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                ),
              ),
              const SizedBox(height: 15),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    String formattedDate = "N/A";
    if (transaction['date'] != null) {
      try {
        DateTime date = DateTime.parse(transaction['date']);
        formattedDate = "${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long, color: AppColors.primaryBlue, size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(transaction['reference'] ?? "Transaction", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(formattedDate, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("- AED ${(transaction['amount'] ?? 0).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 16)),
              const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text("No transactions yet", style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Available Balance", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color:AppColors.primaryBlue)),
                  SizedBox(height: 5),
                ],
              ),
              Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(userBalance, key: ValueKey<String>(userBalance), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                  ),
                  const SizedBox(width: 15),
                  IconButton(
                    icon: Icon(_balanceVisible ? Icons.visibility_off : Icons.visibility, color: AppColors.primaryBlue, size: 28),
                    onPressed: _toggleBalanceVisibility,
                    tooltip: _balanceVisible ? 'Hide Balance' : 'Show Balance',
                  ),
                ],
              ),
            ],
          ),
          Divider(color: Colors.grey[300]),
        ],
      ),
    );
  }

  Widget _buildVirtualCard({required bool isFront}) {
    final String headerLine1 = studentName.toUpperCase();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
      ),
      child: AspectRatio(
        aspectRatio: 1.586,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  "assets/images/14.jpg",
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Text(
                    headerLine1,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    Icons.contactless,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
