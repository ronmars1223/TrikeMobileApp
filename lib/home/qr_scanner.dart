import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:async';

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
          content: Text('Error scanning QR code: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    if (!p) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No camera permission')));
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
      setState(() {
        _tricycleData = Map<String, dynamic>.from(snapshot.value as Map);
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
        title: const Text(
          'Scan Driver QR Code',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(
          color: Colors.white, // back button color
        ),
        backgroundColor: Colors.blue,
      ),

      body: Column(
        children: [
          // Instructions
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
                    'Fetching driver information...',
                    style: TextStyle(color: Colors.white),
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
              Center(
                child: Container(
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
              ),
              SizedBox(height: 40),

              // Driver Details Section
              Text(
                'Driver Details',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 30),
              _buildInfoRow('Driver ID', _driverData!['tricycleId'] ?? 'N/A'),
              _buildInfoRow('First Name', _driverData!['firstName'] ?? 'N/A'),
              _buildInfoRow('Last Name', _driverData!['lastName'] ?? 'N/A'),
              _buildInfoRow(
                'License Code',
                _driverData!['licenseCode'] ?? 'N/A',
              ),
              _buildInfoRow('Tricycle ID', _driverData!['tricycleId'] ?? 'N/A'),
              if (_driverData!.containsKey('createdAt'))
                _buildInfoRow(
                  'Registered On',
                  _formatDate(_driverData!['createdAt']),
                ),

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
        // Expandable Tricycle Section
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
                  child: Text(
                    'Tricycle Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
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
          child:
              _isTricycleExpanded
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
                        _buildInfoRow(
                          'Tricycle ID',
                          _tricycleData!['createdAt'] != null
                              ? _tricycleData!.keys.first
                              : 'N/A',
                        ),
                        if (_tricycleData!.containsKey('orCr'))
                          _buildInfoRow(
                            'OR/CR',
                            _tricycleData!['orCr'] ?? 'N/A',
                          ),
                        if (_tricycleData!.containsKey('plateNumber'))
                          _buildInfoRow(
                            'Plate Number',
                            _tricycleData!['plateNumber'] ?? 'N/A',
                          ),
                        if (_tricycleData!.containsKey('createdAt'))
                          _buildInfoRow(
                            'Registered On',
                            _formatDate(_tricycleData!['createdAt']),
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
                  _buildInfoRow(
                    'Name',
                    '${driver['firstName'] ?? ''} ${driver['lastName'] ?? ''}',
                  ),
                  if (driver.containsKey('licenseCode'))
                    _buildInfoRow('License Code', driver['licenseCode']),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(flex: 3, child: Text(value, style: TextStyle(fontSize: 16))),
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
