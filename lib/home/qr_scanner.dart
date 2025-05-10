import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

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
      return Map<String, dynamic>.from(snapshot.value as Map);
    } else {
      throw Exception('Driver not found');
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
      _isScanning = true;
    });
    controller?.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan Driver QR Code'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.blue.shade50,
            width: double.infinity,
            child: Column(
              children: [
                Icon(Icons.qr_code_scanner, size: 48, color: Colors.blue),
                SizedBox(height: 10),
                Text(
                  'Scan a driver\'s QR code',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 5),
                Text(
                  'Position the QR code within the frame to scan',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),

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
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
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
              child: Icon(Icons.person, size: 60, color: Colors.blue.shade800),
            ),
          ),
          SizedBox(height: 30),
          Text(
            'Driver Details',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          _buildInfoRow('Driver ID', _driverData!['tricycleId'] ?? 'N/A'),
          _buildInfoRow('First Name', _driverData!['firstName'] ?? 'N/A'),
          _buildInfoRow('Last Name', _driverData!['lastName'] ?? 'N/A'),
          _buildInfoRow('License Code', _driverData!['licenseCode'] ?? 'N/A'),
          if (_driverData!.containsKey('createdAt'))
            _buildInfoRow(
              'Registered On',
              _formatDate(_driverData!['createdAt']),
            ),
          SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _resetScanner,
                  icon: Icon(Icons.qr_code_scanner),
                  label: Text('Scan Again'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _proceedToLocationInput,
                  icon: Icon(Icons.navigate_next),
                  label: Text('Continue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
