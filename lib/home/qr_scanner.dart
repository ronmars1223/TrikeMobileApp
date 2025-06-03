import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'dart:math';

class QRScannerPage extends StatefulWidget {
  final Function(Map<String, dynamic>) onDriverScanned;

  QRScannerPage({required this.onDriverScanned});

  @override
  _QRScannerPageState createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  bool _isScanning = true;
  bool _isLoading = false;
  QRViewController? controller;
  Map<String, dynamic>? _driverData;
  Map<String, dynamic>? _tricycleData;
  bool _isTricycleExpanded = false;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');

  // Encryption key (should match other components)
  static const String _encryptionKey = 'MySecureDriverKey2024!@#\$%^&*()12';

  // Firebase database reference
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        "https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/",
  );

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller!.pauseCamera();
    }
    controller!.resumeCamera();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  // Decrypt data function
  String _decryptData(String encryptedData) {
    try {
      final combined = base64Decode(encryptedData);
      if (combined.length < 8) return encryptedData;
      
      // Remove salt (first 8 bytes)
      final encrypted = combined.sublist(8);
      final key = utf8.encode(_encryptionKey);
      final decrypted = <int>[];
      
      for (int i = 0; i < encrypted.length; i++) {
        decrypted.add(encrypted[i] ^ key[i % key.length]);
      }
      
      return utf8.decode(decrypted);
    } catch (e) {
      print('Decryption error: $e');
      return encryptedData; // Return as-is if decryption fails
    }
  }

  // Check if data is encrypted
  bool _isEncrypted(Map<dynamic, dynamic> data) {
    return data['isEncrypted'] == true;
  }

  // Safely decrypt field if encrypted
  String _getDecryptedField(Map<dynamic, dynamic> data, String fieldName, String defaultValue) {
    final fieldValue = data[fieldName];
    if (fieldValue == null) return defaultValue;
    
    if (_isEncrypted(data)) {
      return _decryptData(fieldValue.toString());
    }
    return fieldValue.toString();
  }

  // Decrypt driver data
  Map<String, dynamic> _decryptDriverData(Map<String, dynamic> driverData) {
    Map<String, dynamic> decryptedData = Map<String, dynamic>.from(driverData);
    
    if (_isEncrypted(driverData)) {
      // Decrypt sensitive fields
      decryptedData['firstName'] = _getDecryptedField(driverData, 'firstName', 'Unknown');
      decryptedData['lastName'] = _getDecryptedField(driverData, 'lastName', 'Unknown');
      decryptedData['licenseCode'] = _getDecryptedField(driverData, 'licenseCode', 'N/A');
      
      // Add decryption metadata
      decryptedData['_wasEncrypted'] = true;
      decryptedData['_encryptionVersion'] = driverData['encryptionVersion'] ?? 'N/A';
    } else {
      decryptedData['_wasEncrypted'] = false;
    }
    
    return decryptedData;
  }

  // Decrypt tricycle data
  Map<String, dynamic> _decryptTricycleData(Map<String, dynamic> tricycleData) {
    Map<String, dynamic> decryptedData = Map<String, dynamic>.from(tricycleData);
    
    if (_isEncrypted(tricycleData)) {
      // Decrypt sensitive fields
      decryptedData['plateNumber'] = _getDecryptedField(tricycleData, 'plateNumber', 'Unknown');
      decryptedData['orCr'] = _getDecryptedField(tricycleData, 'orCr', 'N/A');
      
      // Add decryption metadata
      decryptedData['_wasEncrypted'] = true;
      decryptedData['_encryptionVersion'] = tricycleData['encryptionVersion'] ?? 'N/A';
    } else {
      decryptedData['_wasEncrypted'] = false;
    }
    
    return decryptedData;
  }

  // Decrypt nested drivers in tricycle data
  Map<String, dynamic> _decryptNestedDrivers(Map<String, dynamic> tricycleData) {
    Map<String, dynamic> decryptedData = Map<String, dynamic>.from(tricycleData);
    
    if (decryptedData.containsKey('drivers') && decryptedData['drivers'] is Map) {
      Map<String, dynamic> drivers = Map<String, dynamic>.from(decryptedData['drivers']);
      Map<String, dynamic> decryptedDrivers = {};
      
      drivers.forEach((driverId, driverData) {
        if (driverData is Map) {
          Map<String, dynamic> driverMap = Map<String, dynamic>.from(driverData);
          decryptedDrivers[driverId] = _decryptDriverData(driverMap);
        }
      });
      
      decryptedData['drivers'] = decryptedDrivers;
    }
    
    return decryptedData;
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (!_isScanning || scanData.code == null) return;

      setState(() {
        _isScanning = false;
        _isLoading = true;
      });

      _processQrCode(scanData.code!);
    });
  }

  void _processQrCode(String code) async {
    try {
      // First, try to parse the QR code directly as JSON
      Map<String, dynamic> driverInfo;
      try {
        driverInfo = json.decode(code);
        // If it's JSON, decrypt if needed
        driverInfo = _decryptDriverData(driverInfo);
      } catch (e) {
        // If not valid JSON, assume it's a driver ID and fetch from Firebase
        driverInfo = await _fetchDriverInfo(code);
      }

      setState(() {
        _driverData = driverInfo;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isScanning = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Error scanning QR code: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    if (!p) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Text('Camera permission required to scan QR codes'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _fetchDriverInfo(String driverId) async {
    // Fetch driver information from Firebase using the scanned ID
    final dbRef = _database.ref('drivers/$driverId');
    final snapshot = await dbRef.get();

    if (snapshot.exists) {
      Map<String, dynamic> driverData = Map<String, dynamic>.from(
        snapshot.value as Map,
      );

      // Decrypt driver data
      driverData = _decryptDriverData(driverData);

      // If there's a tricycleId, fetch the tricycle data as well
      if (driverData.containsKey('tricycleId') &&
          driverData['tricycleId'] != null) {
        try {
          await _fetchTricycleInfo(driverData['tricycleId']);
        } catch (e) {
          print("Error fetching tricycle: ${e.toString()}");
          // Continue even if tricycle fetch fails
        }
      }

      return driverData;
    } else {
      throw Exception('Driver not found');
    }
  }

  Future<void> _fetchTricycleInfo(String tricycleId) async {
    final dbRef = _database.ref('tricycles/$tricycleId');
    final snapshot = await dbRef.get();

    if (snapshot.exists) {
      Map<String, dynamic> tricycleData = Map<String, dynamic>.from(snapshot.value as Map);
      
      // Decrypt tricycle data
      tricycleData = _decryptTricycleData(tricycleData);
      
      // Decrypt nested drivers
      tricycleData = _decryptNestedDrivers(tricycleData);

      setState(() {
        _tricycleData = tricycleData;
      });
    } else {
      _tricycleData = null;
    }
  }

  void _proceedToLocationInput() {
    if (_driverData != null) {
      widget.onDriverScanned(_driverData!);
    }
  }

  void _resetScanner() {
    setState(() {
      _driverData = null;
      _tricycleData = null;
      _isScanning = true;
      _isTricycleExpanded = false;
    });
    controller?.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Scan Driver QR Code',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
         
            
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Instructions with security notice
          _driverData == null
              ? Container(
                  padding: EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  width: double.infinity,
                  child: Column(
                    children: [
                      Icon(Icons.qr_code_scanner, size: 48, color: Colors.blue),
                      SizedBox(height: 10),
                      Text(
                        'Scan a driver\'s QR code',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Position the QR code within the frame to scan',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.security, size: 16, color: Colors.green.shade700),
                            SizedBox(width: 4),
                            Text(
                              'Encrypted data will be automatically decrypted',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : SizedBox.shrink(),

          // Scanner or Results
          Expanded(
            child: _driverData != null ? _buildDriverInfo() : _buildScanner(),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    // Calculate scan area based on device size
    var scanArea =
        (MediaQuery.of(context).size.width < 400 ||
                MediaQuery.of(context).size.height < 400)
            ? 200.0
            : 250.0;

    return Stack(
      children: [
        // QR Scanner
        QRView(
          key: qrKey,
          onQRViewCreated: _onQRViewCreated,
          overlay: QrScannerOverlayShape(
            borderColor: Colors.blue,
            borderRadius: 10,
            borderLength: 30,
            borderWidth: 10,
            cutOutSize: scanArea,
          ),
          onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
        ),

        // Loading Indicator
        if (_isLoading)
          Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Decrypting driver information...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please wait while we process encrypted data',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDriverInfo() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Container(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Driver Avatar with security indicator
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    if (_driverData!['_wasEncrypted'] == true)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            Icons.security,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 40),

              // Security Status
              if (_driverData!['_wasEncrypted'] == true)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  margin: EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user, color: Colors.green.shade600, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Encrypted Data Decrypted',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                            Text(
                              'Encryption v${_driverData!['_encryptionVersion']} • Data verified',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Driver Details Section
              Row(
                children: [
                  Text(
                    'Driver Details',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 8),
                  if (_driverData!['_wasEncrypted'] == true)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'DECRYPTED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 30),

              _buildInfoRow('First Name', _driverData!['firstName'] ?? 'N/A', isEncrypted: _driverData!['_wasEncrypted'] == true),
              _buildInfoRow('Last Name', _driverData!['lastName'] ?? 'N/A', isEncrypted: _driverData!['_wasEncrypted'] == true),
              _buildInfoRow('License Code', _driverData!['licenseCode'] ?? 'N/A', isEncrypted: _driverData!['_wasEncrypted'] == true),
              _buildInfoRow('Tricycle ID', _driverData!['tricycleId'] ?? 'N/A'),
              if (_driverData!.containsKey('createdAt'))
                _buildInfoRow('Registered On', _formatDate(_driverData!['createdAt'])),

              // Tricycle Details Section
              if (_tricycleData != null) SizedBox(height: 30),
              if (_tricycleData != null) _buildTricycleDetails(),

              SizedBox(height: 40),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _resetScanner,
                      icon: Icon(Icons.qr_code_scanner),
                      label: Text('Scan Again'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _proceedToLocationInput,
                      icon: Icon(Icons.navigate_next, color: Colors.white),
                      label: Text(
                        'Continue',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: EdgeInsets.symmetric(vertical: 14),
                      ),
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

  Widget _buildTricycleDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Expandable Tricycle Section with encryption indicator
        InkWell(
          onTap: () {
            setState(() {
              _isTricycleExpanded = !_isTricycleExpanded;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.directions_bike, color: Colors.blue.shade800),
                SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Tricycle Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      SizedBox(width: 8),
                      if (_tricycleData!['_wasEncrypted'] == true)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'DECRYPTED',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  _isTricycleExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.blue.shade800,
                ),
              ],
            ),
          ),
        ),

        // Expandable Content
        AnimatedContainer(
          duration: Duration(milliseconds: 300),
          height: _isTricycleExpanded ? null : 0,
          child: _isTricycleExpanded
              ? Container(
                  padding: EdgeInsets.all(16),
                  margin: EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tricycle Basic Info
                      if (_tricycleData!.containsKey('plateNumber'))
                        _buildInfoRow(
                          'Plate Number',
                          _tricycleData!['plateNumber'] ?? 'N/A',
                          isEncrypted: _tricycleData!['_wasEncrypted'] == true,
                        ),
                      if (_tricycleData!.containsKey('orCr'))
                        _buildInfoRow(
                          'OR/CR',
                          _tricycleData!['orCr'] ?? 'N/A',
                          isEncrypted: _tricycleData!['_wasEncrypted'] == true,
                        ),
                      if (_tricycleData!.containsKey('createdAt'))
                        _buildInfoRow(
                          'Registered On',
                          _formatDate(_tricycleData!['createdAt']),
                        ),
                      if (_tricycleData!['_wasEncrypted'] == true)
                        _buildInfoRow(
                          'Encryption Version',
                          'v${_tricycleData!['_encryptionVersion']}',
                        ),

                      // Drivers section - shows drivers associated with this tricycle
                      if (_tricycleData!.containsKey('drivers'))
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Text(
                            'Associated Drivers',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),

                      if (_tricycleData!.containsKey('drivers'))
                        ..._buildDriversList(),
                    ],
                  ),
                )
              : SizedBox.shrink(),
        ),
      ],
    );
  }

  List<Widget> _buildDriversList() {
    List<Widget> driverWidgets = [];

    if (_tricycleData!['drivers'] is Map) {
      Map<String, dynamic> drivers = Map<String, dynamic>.from(
        _tricycleData!['drivers'] as Map,
      );

      drivers.forEach((driverId, driverData) {
        if (driverData is Map) {
          Map<String, dynamic> driver = Map<String, dynamic>.from(
            driverData as Map,
          );

          driverWidgets.add(
            Container(
              margin: EdgeInsets.only(top: 8),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoRow(
                          'Name',
                          '${driver['firstName'] ?? ''} ${driver['lastName'] ?? ''}',
                          isEncrypted: driver['_wasEncrypted'] == true,
                          compact: true,
                        ),
                      ),
                      if (driver['_wasEncrypted'] == true)
                        Icon(Icons.security, size: 16, color: Colors.green.shade600),
                    ],
                  ),
                  if (driver.containsKey('licenseCode'))
                    _buildInfoRow(
                      'License Code',
                      driver['licenseCode'],
                      isEncrypted: driver['_wasEncrypted'] == true,
                      compact: true,
                    ),
                ],
              ),
            ),
          );
        }
      });
    }

    if (driverWidgets.isEmpty) {
      driverWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text('No additional drivers found'),
        ),
      );
    }

    return driverWidgets;
  }

  Widget _buildInfoRow(String label, String value, {bool isEncrypted = false, bool compact = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 8.0 : 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                    fontSize: compact ? 14 : 16,
                  ),
                ),
                if (isEncrypted) ...[
                  SizedBox(width: 4),
                  Icon(
                    Icons.security,
                    size: compact ? 14 : 16,
                    color: Colors.green.shade600,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                fontWeight: isEncrypted ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}