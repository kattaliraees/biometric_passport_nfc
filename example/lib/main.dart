import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:biometric_passport_nfc/biometric_passport_nfc.dart';

import 'mrz/mrz_parser.dart';
import 'mrz/mrz_scanner_screen.dart';

void main() {
  runApp(const BiometricPassportNfcExampleApp());
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class BiometricPassportNfcExampleApp extends StatelessWidget {
  const BiometricPassportNfcExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Biometric Passport NFC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006C50), // Dignified green
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const PassportScanScreen(),
    );
  }
}

class PassportScanScreen extends StatefulWidget {
  const PassportScanScreen({super.key});

  @override
  State<PassportScanScreen> createState() => _PassportScanScreenState();
}

class _PassportScanScreenState extends State<PassportScanScreen> {
  final BiometricPassportNfc _reader = BiometricPassportNfc();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _docNumberController;
  late final TextEditingController _dobController;
  late final TextEditingController _expiryController;

  bool _isScanning = false;
  String? _statusMessage;
  String? _errorMessage;
  PassportData? _passportData;
  StreamSubscription? _statusSubscription;

  // Live indicators
  bool _nfcConnected = false;
  String _authStatus = 'Pending';
  bool _dg1Success = false;
  bool _dg2Success = false;
  int? _readProgress;
  bool _connectionLost = false;

  @override
  void initState() {
    super.initState();
    _docNumberController = TextEditingController();
    _dobController = TextEditingController();
    _expiryController = TextEditingController();
    _listenToStatusEvents();
  }

  void _listenToStatusEvents() {
    _statusSubscription = _reader.events.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _statusMessage = event.message;
          if (event.progress != null) {
            _readProgress = event.progress;
          }
          _connectionLost = event.step == PassportScanStep.connectionLost;

          switch (event.step) {
            case PassportScanStep.connectionLost:
              _nfcConnected = false;
            case PassportScanStep.tagDiscovered || PassportScanStep.tagConnected:
              _nfcConnected = true;
            case PassportScanStep.paceSuccess:
              _authStatus = 'PACE Success';
            case PassportScanStep.bacSuccess:
              _authStatus = 'BAC Success';
            case PassportScanStep.dg1Success:
              _dg1Success = true;
            case PassportScanStep.dg2Success:
              _dg2Success = true;
            default:
              break;
          }
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _errorMessage = err.toString();
        });
      },
    );
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _docNumberController.dispose();
    _dobController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  String? _validateDocNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Document number is required';
    }
    final clean = value.trim();
    if (clean.length < 5 || clean.length > 12) {
      return 'Length must be 5 to 12 characters';
    }
    if (!RegExp(r'^[A-Za-z0-9<]+$').hasMatch(clean)) {
      return 'Only alphanumeric and "<" allowed';
    }
    return null;
  }

  String? _validateDate(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    final clean = value.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(clean)) {
      return 'Must be 6 digits (YYMMDD)';
    }
    final month = int.tryParse(clean.substring(2, 4)) ?? 0;
    if (month < 1 || month > 12) {
      return 'Month must be 01–12';
    }
    final day = int.tryParse(clean.substring(4, 6)) ?? 0;
    if (day < 1 || day > 31) {
      return 'Day must be 01–31';
    }
    return null;
  }

  void _resetToDefaults() {
    setState(() {
      _docNumberController.clear();
      _dobController.clear();
      _expiryController.clear();
      _passportData = null;
      _errorMessage = null;
      _statusMessage = null;
      _nfcConnected = false;
      _authStatus = 'Pending';
      _dg1Success = false;
      _dg2Success = false;
      _readProgress = null;
      _connectionLost = false;
    });
  }

  Future<void> _scanMrz() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push<MrzResult>(
      MaterialPageRoute(builder: (_) => const MrzScannerScreen()),
    );
    if (result == null || !mounted) return;

    setState(() {
      _docNumberController.text = result.documentNumber;
      _dobController.text = result.dateOfBirth;
      _expiryController.text = result.dateOfExpiry;
    });
    _formKey.currentState?.validate();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Details filled from MRZ. Please verify before scanning.')),
    );
  }

  Future<void> _startScan() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final docNumber = _docNumberController.text.trim().toUpperCase();
    final dob = _dobController.text.trim();
    final expiry = _expiryController.text.trim();

    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _passportData = null;
      _statusMessage = 'Hold your phone against the passport NFC chip...';
      _nfcConnected = false;
      _authStatus = 'Pending';
      _dg1Success = false;
      _dg2Success = false;
      _readProgress = null;
      _connectionLost = false;
    });

    try {
      final data = await _reader.readPassport(
        documentNumber: docNumber,
        dateOfBirth: dob,
        dateOfExpiry: expiry,
      );
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _passportData = data;
        _nfcConnected = true;
        _dg1Success = data.dg1Read;
        _dg2Success = data.dg2Read;
        if (data.paceSucceeded) {
          _authStatus = 'PACE Success';
        } else if (data.bacSucceeded) {
          _authStatus = 'BAC Success';
        }
        _statusMessage = 'Passport successfully read!';
      });
    } on PassportReadException catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _errorMessage = e.isCancelled ? null : e.message;
        _statusMessage = null;
      });
    }
  }

  Future<void> _cancelScan() async {
    await _reader.cancel();
    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _statusMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biometric Passport NFC'),
        centerTitle: true,
        elevation: 1,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCredentialsCard(theme),
              const SizedBox(height: 20),

              // Single scan action or active progress
              if (_isScanning)
                _buildScanningState(theme)
              else
                _buildScanButton(theme),

              const SizedBox(height: 20),

              // Status badges
              _buildStatusMatrix(theme),

              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                _buildErrorCard(theme),
              ],

              if (_passportData != null) ...[
                const SizedBox(height: 24),
                _buildPassportResultCard(theme, _passportData!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCredentialsCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge_outlined, color: theme.colorScheme.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Passport Credentials',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const Key('scanMrzButton'),
                    onPressed: _isScanning ? null : _scanMrz,
                    icon: const Icon(Icons.document_scanner_outlined, size: 14),
                    label: const Text('Scan', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('resetButton'),
                    onPressed: _isScanning ? null : _resetToDefaults,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Reset', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Enter details from the MRZ / passport bio page to derive the NFC access key.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('docNumberField'),
                controller: _docNumberController,
                enabled: !_isScanning,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9<]')),
                  UpperCaseTextFormatter(),
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: InputDecoration(
                  labelText: 'Document Number',
                  hintText: 'e.g. L898902C3',
                  prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  isDense: true,
                ),
                validator: _validateDocNumber,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('dobField'),
                      controller: _dobController,
                      enabled: !_isScanning,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        labelText: 'DOB (YYMMDD)',
                        hintText: 'YYMMDD',
                        prefixIcon: const Icon(Icons.cake_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        isDense: true,
                      ),
                      validator: (val) => _validateDate(val, 'Date of birth'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('expiryField'),
                      controller: _expiryController,
                      enabled: !_isScanning,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Expiry (YYMMDD)',
                        hintText: 'YYMMDD',
                        prefixIcon: const Icon(Icons.event_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        isDense: true,
                      ),
                      validator: (val) => _validateDate(val, 'Expiry date'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanButton(ThemeData theme) {
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        key: const Key('scanButton'),
        onPressed: _startScan,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
        icon: const Icon(Icons.nfc, size: 28),
        label: Text(
          _passportData == null ? 'Scan Passport' : 'Scan Again',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildScanningState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          if (_connectionLost)
            Icon(Icons.signal_wifi_bad, size: 36, color: theme.colorScheme.error)
          else
            const SizedBox(
              height: 36,
              width: 36,
              child: CircularProgressIndicator(strokeWidth: 3.5),
            ),
          const SizedBox(height: 16),
          Text(
            _statusMessage ?? 'Preparing NFC reader...',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: _connectionLost ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
          ),
          if (_readProgress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _readProgress! / 100,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text('Photo $_readProgress%', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _cancelScan,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cancel Scan'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMatrix(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Protocol Status',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatusChip(
                  'NFC Chip',
                  _nfcConnected ? 'Connected' : 'Disconnected',
                  _nfcConnected,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusChip(
                  'PACE / BAC',
                  _authStatus,
                  _authStatus.contains('Success'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatusChip(
                  'DG1 (Identity)',
                  _dg1Success ? 'Success' : 'Pending',
                  _dg1Success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusChip(
                  'DG2 (Photo)',
                  _dg2Success ? 'Success' : 'Pending',
                  _dg2Success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String title, String value, bool isSuccess) {
    final color = isSuccess ? Colors.green.shade700 : Colors.grey.shade600;
    final bg = isSuccess ? Colors.green.shade50 : Colors.grey.shade100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan Error',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassportResultCard(ThemeData theme, PassportData data) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Biometric photo
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 90,
                    height: 120,
                    color: Colors.grey.shade200,
                    child: data.faceImage != null
                        ? Image.memory(
                            data.faceImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Center(
                              child: Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.person, size: 48, color: Colors.grey),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                // Core info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.fullName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Passport No: ${data.documentNumber}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Nationality: ${data.nationality}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'DOB: ${data.dateOfBirth} (${data.sex})',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Expiry: ${data.dateOfExpiry}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (data.rawMrz != null && data.rawMrz!.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                'RAW MRZ (DG1)',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  data.rawMrz!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
